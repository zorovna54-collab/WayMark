using System.Data.Common;
using System.IdentityModel.Tokens.Jwt;
using System.Net.Http.Headers;
using System.Security.Claims;
using System.Security.Cryptography;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Storage;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.IdentityModel.Tokens;
using WayMark.Api.Controllers;
using WayMark.Api.Data;
using WayMark.Api.Models;
using WayMark.Api.Security;
using WayMark.Api.Services.MapDrafts;
using WayMark.Api.Services;
using WayMarkEntity = WayMark.Api.Models.WayMark;

namespace WayMark.Api.Tests;

// Relational database exists ONLY in this process; no SQL Server connection/config is loaded.
internal sealed class MapDraftTestHost(IMapImageStorage? storage = null,
    Action<MapDraftLimitsOptions>? configureLimits = null, string? sqlitePath = null, string? listenUrl = null,
    bool withIdentity = false) : IAsyncDisposable
{
    private readonly SqliteConnection connection = new(new SqliteConnectionStringBuilder
        { DataSource = sqlitePath ?? ":memory:" }.ToString());
    private readonly byte[] key = RandomNumberGenerator.GetBytes(32);
    private IHost host = null!;
    public HttpClient Client { get; private set; } = null!;
    public FailingWriteInterceptor Failure { get; } = new();
    public PostCommitFailureInterceptor PostCommitFailure { get; } = new();
    public TestAccountEmail Email { get; } = new();
    public IServiceScope Scope() => host.Services.CreateScope();
    public HttpClient NewClient() => listenUrl is null ? host.GetTestClient() : new HttpClient { BaseAddress = new Uri(listenUrl) };

    public async Task StartAsync()
    {
        if (listenUrl is not null && (!Uri.TryCreate(listenUrl, UriKind.Absolute, out var uri) || !uri.IsLoopback
            || uri.Scheme != "http" || uri.Port < 1024 || uri.UserInfo.Length > 0 || uri.AbsolutePath != "/"))
            throw new InvalidOperationException("Isolated evidence host must listen on one loopback development address");
        await connection.OpenAsync();
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Jwt:SecretKey"] = Convert.ToBase64String(key), ["Jwt:Issuer"] = "draft-test", ["Jwt:Audience"] = "draft-test"
        }).Build();
        host = await new HostBuilder().ConfigureLogging(x => x.ClearProviders()).ConfigureWebHost(web => {
            if (listenUrl is null) web.UseTestServer(); else web.UseKestrel().UseUrls(listenUrl);
            web
            .ConfigureServices(services =>
            {
                services.AddDbContext<WayMarkDbContext>(options => options.UseSqlite(connection).AddInterceptors(Failure, PostCommitFailure));
                services.AddWayMarkSecurity(configuration);
                services.AddPasswordResetLimits();
                if (withIdentity) {
                    services.AddSingleton<IConfiguration>(configuration);
                    services.AddDbContext<AuthDbContext>(options => options.UseSqlite(connection));
                    services.AddIdentityCore<IdentityUser>(o => { o.Password.RequiredLength = 8; o.Password.RequireNonAlphanumeric = false; })
                        .AddRoles<IdentityRole>().AddEntityFrameworkStores<AuthDbContext>().AddDefaultTokenProviders();
                    services.AddDataProtection().UseEphemeralDataProtectionProvider();
                    services.Configure<DataProtectionTokenProviderOptions>(o => o.TokenLifespan = TimeSpan.FromMinutes(30));
                    services.AddSingleton<ISmtpEmailService>(Email);
                }
                if (storage is not null) services.AddSingleton<IMapImageStorage>(storage);
                services.AddMapDraftFoundation();
                if (configureLimits is not null) services.Configure(configureLimits);
                services.AddControllers().AddApplicationPart(typeof(MapDraftsController).Assembly);
            }).Configure(app =>
            {
                app.UseRouting(); app.UseAuthentication(); app.UseRateLimiter(); app.UseAuthorization();
                app.UseEndpoints(routes => routes.MapControllers());
            }); }).StartAsync();
        Client = listenUrl is null ? host.GetTestClient() : new HttpClient { BaseAddress = new Uri(listenUrl) };
        using var scope = Scope();
        var db = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
        if (!await db.Database.EnsureCreatedAsync()) { Token(); return; } // ONLY an isolated test SQLite database.
        if (withIdentity) await scope.ServiceProvider.GetRequiredService<AuthDbContext>().GetService<IRelationalDatabaseCreator>().CreateTablesAsync();
        db.Sites.AddRange(new Site { Id = 1, Code = "TEST-A", Name = "Test A" }, new Site { Id = 2, Code = "TEST-B", Name = "Test B" });
        db.Buildings.AddRange(new Building { Id = 1, SiteId = 1, Name = "Building A", BuildingCode = "A" },
            new Building { Id = 2, SiteId = 2, Name = "Building B", BuildingCode = "B" });
        db.Floors.AddRange(new Floor { Id = 10, BuildingId = 1, Name = "Ground", FloorCode = "G" },
            new Floor { Id = 11, BuildingId = 1, Name = "Level 1", FloorCode = "L1" },
            new Floor { Id = 20, BuildingId = 2, Name = "Other hospital", FloorCode = "G" });
        db.SiteMapMemberships.AddRange(new SiteMapMembership { SiteId = 1, UserId = "admin-a", IsActive = true, CanEditDrafts = true },
            new SiteMapMembership { SiteId = 2, UserId = "admin-b", IsActive = true, CanEditDrafts = true },
            new SiteMapMembership { SiteId = 1, UserId = "inactive", IsActive = false, CanEditDrafts = true },
            new SiteMapMembership { SiteId = 1, UserId = "no-edit", IsActive = true, CanEditDrafts = false });
        db.NavigationNodes.AddRange(new NavigationNode { Id = 100, FloorId = 10, NodeCode = "PUBLISHED-START", Name = "Published A", X = .1m, Y = .2m },
            new NavigationNode { Id = 101, FloorId = 10, NodeCode = "PUBLISHED-END", Name = "Published B", X = .8m, Y = .2m });
        db.NavigationEdges.Add(new NavigationEdge { Id = 100, FromNodeId = 100, ToNodeId = 101, DistanceMeters = 40m });
        db.WayMarks.AddRange(new WayMarkEntity { Id = 100, WayMarkCode = "PUBLISHED-QR-A", Name = "Published A", Location = "Ground", NavigationNodeId = 100 },
            new WayMarkEntity { Id = 101, WayMarkCode = "PUBLISHED-QR-B", Name = "Published B", Location = "Ground", NavigationNodeId = 101 });
        await db.SaveChangesAsync();
        Token();
    }

    public ClaimsPrincipal Principal(string id = "admin-a") => new(new ClaimsIdentity(
        [new Claim(ClaimTypes.NameIdentifier, id), new Claim(ClaimTypes.Role, "Admin")], "test"));

    public void Token(string kind = "admin", string userId = "admin-a", string[]? roles = null)
    {
        if (kind == "missing") { Client.DefaultRequestHeaders.Authorization = null; return; }
        var claims = new List<Claim>();
        if (kind != "missing-subject") claims.Add(new(ClaimTypes.NameIdentifier, userId));
        if (roles is not null) claims.AddRange(roles.Select(role => new Claim(ClaimTypes.Role, role)));
        else if (kind is not ("user" or "forged-role")) claims.Add(new(ClaimTypes.Role, "Admin"));
        var signing = kind == "bad-signature" ? RandomNumberGenerator.GetBytes(32) : key;
        var token = new JwtSecurityToken("draft-test", "draft-test", claims,
            DateTime.UtcNow.AddMinutes(-10), DateTime.UtcNow.AddMinutes(kind == "expired" ? -5 : 5),
            new SigningCredentials(new SymmetricSecurityKey(signing), SecurityAlgorithms.HmacSha256));
        var encoded = new JwtSecurityTokenHandler().WriteToken(token);
        if (kind == "forged-role")
        {
            var parts = encoded.Split('.');
            var payload = System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, System.Text.Json.JsonElement>>(Base64UrlEncoder.Decode(parts[1]))!;
            payload["role"] = System.Text.Json.JsonSerializer.SerializeToElement("Admin");
            encoded = parts[0] + "." + Base64UrlEncoder.Encode(System.Text.Json.JsonSerializer.Serialize(payload)) + "." + parts[2];
        }
        Client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", encoded);
    }

    public async ValueTask DisposeAsync()
    {
        Client?.Dispose(); if(host is not null){await host.StopAsync();host.Dispose();} await connection.DisposeAsync();
    }
}

internal sealed class NoTestEmail : ISmtpEmailService
{
    public Task SendTestEmailAsync(DateTimeOffset sentAtUtc, CancellationToken cancellationToken) => throw new InvalidOperationException("Email not part of isolated Identity login test");
    public Task SendPasswordResetEmailAsync(string toEmail, string username, string resetToken, string resetUrl, CancellationToken cancellationToken)
        => throw new InvalidOperationException("Email not part of isolated Identity login test");
}

// Only isolated test memory, never a network provider and never token logging.
internal sealed class TestAccountEmail : ISmtpEmailService
{
    public string? Recipient, Token, ResetToken, ResetRecipient;
    public int VerificationCalls, ResetCalls;
    public bool Fail;
    public Task SendTestEmailAsync(DateTimeOffset sentAtUtc, CancellationToken ct) => Task.CompletedTask;
    public Task SendEmailVerificationAsync(string email, string username, string token, CancellationToken ct)
    {
        if (Fail) throw new SmtpEmailException(SmtpEmailFailure.Delivery, "Isolated failure");
        Recipient = email; Token = token; VerificationCalls++; return Task.CompletedTask;
    }
    public Task SendPasswordResetEmailAsync(string email, string username, string token, string resetUrl, CancellationToken ct)
    { ResetRecipient = email; ResetToken = token; ResetCalls++; return Task.CompletedTask; }
}

internal sealed class FailingWriteInterceptor : DbCommandInterceptor
{
    public bool Armed { get; set; }
    public int FailAtWrite { get; set; } = 2;
    public int WritesObserved { get; private set; }
    public override ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(DbCommand command,
        CommandEventData eventData, InterceptionResult<DbDataReader> result, CancellationToken cancellationToken = default)
    {
        if (Armed && (command.CommandText.StartsWith("INSERT", StringComparison.OrdinalIgnoreCase)
            || command.CommandText.StartsWith("UPDATE", StringComparison.OrdinalIgnoreCase)))
        {
            WritesObserved++;
            if (WritesObserved == FailAtWrite) { Armed = false; throw new InvalidOperationException("Injected isolated test write failure"); }
        }
        return base.ReaderExecutingAsync(command, eventData, result, cancellationToken);
    }
}

internal sealed class PostCommitFailureInterceptor : SaveChangesInterceptor
{
    public bool Armed { get; set; }
    public override ValueTask<int> SavedChangesAsync(SaveChangesCompletedEventData eventData, int result,
        CancellationToken cancellationToken = default)
    {
        if (Armed)
        {
            Armed = false;
            throw new InvalidOperationException("Injected failure after isolated SQL commit");
        }
        return base.SavedChangesAsync(eventData, result, cancellationToken);
    }
}
