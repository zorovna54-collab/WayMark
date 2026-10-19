using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Reflection;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Routing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.IdentityModel.Tokens;
using WayMark.Api.Controllers;
using WayMark.Api.Data;
using WayMark.Api.Models;
using WayMark.Api.Security;
using WayMark.Api.Services;
using WayMark.Api.Services.Routing;
using Xunit;
using WayMarkEntity = WayMark.Api.Models.WayMark;

namespace WayMark.Api.Tests;

/// <summary>Actual controllers, login and production JWT/policy registration.
/// Identity/business stores are EF InMemory; SMTP is a counter, never a network client.</summary>
public sealed class AdminAuthorizationTests : IAsyncLifetime
{
    private readonly byte[] signingKey = RandomNumberGenerator.GetBytes(32);
    private readonly string password = Convert.ToBase64String(RandomNumberGenerator.GetBytes(24)) + "aA1!";
    private readonly CountingEmail email = new();
    private IHost host = null!;
    private HttpClient client = null!;
    private const string Issuer = "security-test-issuer";
    private const string Audience = "security-test-audience";

    public async Task InitializeAsync()
    {
        var id = Guid.NewGuid().ToString();
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(
            new Dictionary<string, string?>
            {
                ["Jwt:SecretKey"] = Convert.ToBase64String(signingKey),
                ["Jwt:Issuer"] = Issuer,
                ["Jwt:Audience"] = Audience,
                ["Jwt:ExpiryMinutes"] = "30"
            }).Build();
        host = await new HostBuilder().ConfigureLogging(logging => logging.ClearProviders())
            .ConfigureWebHost(web => web.UseTestServer().ConfigureServices(services =>
            {
                services.AddSingleton<IConfiguration>(configuration);
                services.AddDbContext<AuthDbContext>(options => options.UseInMemoryDatabase("auth-" + id));
                services.AddDbContext<WayMarkDbContext>(options => options.UseInMemoryDatabase("map-" + id));
                services.AddIdentityCore<IdentityUser>(options =>
                {
                    options.Password.RequiredLength = 8;
                    options.Password.RequireNonAlphanumeric = false;
                }).AddRoles<IdentityRole>().AddEntityFrameworkStores<AuthDbContext>();
                services.AddWayMarkSecurity(configuration);
                services.AddSingleton<DijkstraRouter>();
                services.AddScoped<IRoutePlanner, RoutePlanner>();
                services.AddSingleton<ISmtpEmailService>(email);
                services.AddControllers().AddApplicationPart(typeof(AuthController).Assembly);
            }).Configure(app =>
            {
                app.UseRouting();
                app.UseAuthentication();
                app.UseAuthorization();
                app.UseEndpoints(endpoints => endpoints.MapControllers());
            })).StartAsync();
        client = host.GetTestClient();

        // All test role/account provisioning stays in this random InMemory store.
        using var scope = host.Services.CreateScope();
        var roles = scope.ServiceProvider.GetRequiredService<RoleManager<IdentityRole>>();
        var users = scope.ServiceProvider.GetRequiredService<UserManager<IdentityUser>>();
        Assert.True((await roles.CreateAsync(new IdentityRole(WayMarkSecurity.AdminRole))).Succeeded);
        var reader = new IdentityUser("reader-fixture");
        var admin = new IdentityUser("operator-fixture");
        Assert.True((await users.CreateAsync(reader, password)).Succeeded);
        Assert.True((await users.CreateAsync(admin, password)).Succeeded);
        Assert.True((await users.AddToRoleAsync(admin, WayMarkSecurity.AdminRole)).Succeeded);

        var db = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
        db.Sites.Add(new Site { Id = 1, Code = "TEST", Name = "Test site" });
        db.Buildings.Add(new Building { Id = 1, SiteId = 1, BuildingCode = "TEST", Name = "Test building" });
        db.Floors.Add(new Floor { Id = 10, BuildingId = 1, FloorCode = "G", Name = "Test floor" });
        db.NavigationNodes.AddRange(
            new NavigationNode { Id = 11, FloorId = 10, NodeCode = "SEC-A", Name = "A", X = .1m, Y = .2m },
            new NavigationNode { Id = 12, FloorId = 10, NodeCode = "SEC-B", Name = "B", X = .5m, Y = .6m });
        db.NavigationEdges.Add(new NavigationEdge
        {
            Id = 1, FromNodeId = 11, ToNodeId = 12, DistanceMeters = 5m, IsActive = true
        });
        db.WayMarks.AddRange(
            new WayMarkEntity { Id = 1, Name = "Start", Location = "Test floor", WayMarkCode = "START", NavigationNodeId = 11 },
            new WayMarkEntity { Id = 2, Name = "End", Location = "Test floor", WayMarkCode = "END", NavigationNodeId = 12 });
        await db.SaveChangesAsync();
    }

    public static IEnumerable<object[]> RejectedWrites()
    {
        foreach (var operation in new[] { "create", "update", "delete", "email" })
        foreach (var token in new[] { "missing", "user", "client-role", "expired", "wrong-signature",
                     "forged-payload", "wrong-issuer", "wrong-audience", "unsigned", "wrong-role" })
            yield return [operation, token, token is "user" or "client-role" or "wrong-role" ? 403 : 401];
    }

    [Theory]
    [MemberData(nameof(RejectedWrites))]
    public async Task RejectedWriteCannotChangeDataOrSendEmail(string operation, string kind, int status)
    {
        var before = await Snapshot();
        var token = kind switch
        {
            "missing" => null,
            "user" or "client-role" => await Login("reader-fixture"),
            "forged-payload" => ForgeRole(await Login("reader-fixture")),
            _ => SignedAdminToken(kind)
        };
        SetToken(token);
        client.DefaultRequestHeaders.Add("X-Role", "Admin");
        client.DefaultRequestHeaders.Add("X-Is-Admin", "true");
        using var response = await Write(operation);
        Assert.Equal(status, (int)response.StatusCode);
        Assert.Equal(before, await Snapshot());
        Assert.Equal(0, email.Calls);
    }

    [Theory]
    [InlineData("create", 201)]
    [InlineData("update", 200)]
    [InlineData("delete", 204)]
    [InlineData("email", 200)]
    public async Task DatabaseAdminCanWriteUsingTokenFromRealLogin(string operation, int status)
    {
        var token = await Login("operator-fixture");
        var jwt = new JwtSecurityTokenHandler().ReadJwtToken(token);
        Assert.Contains(jwt.Claims, claim => IsRole(claim) && claim.Value == WayMarkSecurity.AdminRole);
        SetToken(token);
        var before = await Snapshot();
        using var response = await Write(operation);
        Assert.Equal(status, (int)response.StatusCode);
        using var scope = host.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
        switch (operation)
        {
            case "create":
                Assert.Equal(3, await db.WayMarks.CountAsync());
                Assert.True(await db.WayMarks.AnyAsync(mark => mark.WayMarkCode == "SECURITY-NEW"));
                break;
            case "update":
                Assert.Equal("Changed by test", (await db.WayMarks.SingleAsync(mark => mark.Id == 1)).Name);
                break;
            case "delete":
                Assert.False(await db.WayMarks.AnyAsync(mark => mark.Id == 1));
                break;
            case "email":
                Assert.Equal(before, await Snapshot());
                Assert.Equal(1, email.Calls);
                break;
        }
    }

    [Fact]
    public async Task RegisterAndLoginIgnoreClientRolesEvenWhenUsernameIsAdmin()
    {
        using var registered = await client.PostAsJsonAsync("/api/Auth/register", new
        {
            username = "admin", password, role = "Admin", roles = new[] { "Admin" }, isAdmin = true
        });
        Assert.Equal(HttpStatusCode.OK, registered.StatusCode);
        using var scope = host.Services.CreateScope();
        var manager = scope.ServiceProvider.GetRequiredService<UserManager<IdentityUser>>();
        var user = (await manager.FindByNameAsync("admin"))!;
        Assert.Empty(await manager.GetRolesAsync(user));
        var token = await Login("admin"); // Login also submits an untrusted role property.
        Assert.DoesNotContain(new JwtSecurityTokenHandler().ReadJwtToken(token).Claims, IsRole);
        SetToken(token);
        var before = await Snapshot();
        using var denied = await Write("create");
        Assert.Equal(HttpStatusCode.Forbidden, denied.StatusCode);
        Assert.Equal(before, await Snapshot());
    }

    [Fact]
    public async Task RemovingDatabaseMembershipRemovesAdminFromNextLogin()
    {
        using var scope = host.Services.CreateScope();
        var manager = scope.ServiceProvider.GetRequiredService<UserManager<IdentityUser>>();
        var user = (await manager.FindByNameAsync("operator-fixture"))!;
        Assert.True((await manager.RemoveFromRoleAsync(user, WayMarkSecurity.AdminRole)).Succeeded);
        var token = await Login("operator-fixture");
        Assert.DoesNotContain(new JwtSecurityTokenHandler().ReadJwtToken(token).Claims, IsRole);
        SetToken(token);
        var before = await Snapshot();
        using var denied = await Write("delete");
        Assert.Equal(HttpStatusCode.Forbidden, denied.StatusCode);
        Assert.Equal(before, await Snapshot());
    }

    [Fact]
    public async Task OrdinaryLoginKeepsMapQrAndBothRouteRequestFormatsAvailable()
    {
        SetToken(await Login("reader-fixture"));
        foreach (var path in new[] { "/api/WayMarks", "/api/WayMarks/1", "/api/WayMarks/code/START",
                     "/api/WayMarks/code/START/map-location", "/api/Maps/sites", "/api/Maps/sites/1/buildings",
                     "/api/Maps/buildings/1/floors", "/api/Maps/floors/10/graph" })
        {
            using var response = await client.GetAsync(path);
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        }
        using var legacy = await client.PostAsJsonAsync("/api/routes", new
        {
            startWayMarkCode = "START", destinationWayMarkCode = "END"
        });
        using var options = await client.PostAsJsonAsync("/api/routes", new
        {
            startWayMarkCode = "START", destinationWayMarkCode = "END",
            options = new { avoidStairs = true, wheelchair = false, preference = "ShortestDistance" }
        });
        Assert.Equal(HttpStatusCode.OK, legacy.StatusCode);
        Assert.Equal(HttpStatusCode.OK, options.StatusCode);
        SetToken(null);
        using var deniedRead = await client.GetAsync("/api/Maps/sites");
        using var deniedRoute = await client.PostAsJsonAsync("/api/routes", new
        {
            startWayMarkCode = "START", destinationWayMarkCode = "END"
        });
        Assert.Equal(HttpStatusCode.Unauthorized, deniedRead.StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, deniedRoute.StatusCode);
    }

    [Fact]
    public void EveryNonAuthNonRoutingWriteActionRequiresAdminPolicy()
    {
        var controllers = typeof(WayMarksController).Assembly.GetTypes()
            .Where(type => !type.IsAbstract && typeof(ControllerBase).IsAssignableFrom(type));
        var protectedActions = 0;
        foreach (var controller in controllers)
        foreach (var method in controller.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly))
        {
            if (!method.GetCustomAttributes<HttpMethodAttribute>().Any(attribute =>
                    attribute.HttpMethods.Any(verb => verb is "POST" or "PUT" or "PATCH" or "DELETE"))) continue;
            if (controller == typeof(AuthController) && method.Name is "Login" or "Register") continue;
            if (controller == typeof(RoutesController) && method.Name == "FindRoute") continue;
            var authorization = controller.GetCustomAttributes<AuthorizeAttribute>()
                .Concat(method.GetCustomAttributes<AuthorizeAttribute>());
            Assert.Contains(authorization, attribute => attribute.Policy == WayMarkSecurity.AdminPolicy);
            Assert.Empty(controller.GetCustomAttributes<AllowAnonymousAttribute>());
            Assert.Empty(method.GetCustomAttributes<AllowAnonymousAttribute>());
            protectedActions++;
        }
        Assert.Equal(4, protectedActions);
    }

    private void SetToken(string? token) => client.DefaultRequestHeaders.Authorization =
        token is null ? null : new AuthenticationHeaderValue("Bearer", token);

    private async Task<string> Login(string username)
    {
        using var response = await client.PostAsJsonAsync("/api/Auth/login", new
        {
            username, password, role = "Admin", roles = new[] { "Admin" }
        });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var json = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal("Bearer", json.GetProperty("tokenType").GetString());
        Assert.Equal(username, json.GetProperty("username").GetString());
        return json.GetProperty("accessToken").GetString()!;
    }

    private Task<HttpResponseMessage> Write(string operation)
    {
        var body = new { name = "Changed by test", location = "Test floor", wayMarkCode = "SECURITY-NEW", role = "Admin" };
        return operation switch
        {
            "create" => client.PostAsJsonAsync("/api/WayMarks?role=Admin", body),
            "update" => client.PutAsJsonAsync("/api/WayMarks/1?role=Admin", body),
            "delete" => client.DeleteAsync("/api/WayMarks/1?role=Admin"),
            "email" => client.PostAsJsonAsync("/api/Email/test?role=Admin", new { role = "Admin" }),
            _ => throw new ArgumentOutOfRangeException(nameof(operation))
        };
    }

    private string SignedAdminToken(string kind)
    {
        var key = kind == "wrong-signature" ? RandomNumberGenerator.GetBytes(32) : signingKey;
        var token = new JwtSecurityToken(
            issuer: kind == "wrong-issuer" ? "wrong" : Issuer,
            audience: kind == "wrong-audience" ? "wrong" : Audience,
            claims: [new Claim(ClaimTypes.Role, kind == "wrong-role" ? "Reviewer" : WayMarkSecurity.AdminRole)],
            notBefore: DateTime.UtcNow.AddMinutes(-10),
            expires: DateTime.UtcNow.AddMinutes(kind == "expired" ? -5 : 5),
            signingCredentials: kind == "unsigned" ? null : new SigningCredentials(
                new SymmetricSecurityKey(key), SecurityAlgorithms.HmacSha256));
        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private static string ForgeRole(string token)
    {
        var parts = token.Split('.');
        var payload = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(
            Base64UrlEncoder.Decode(parts[1]))!;
        payload["role"] = JsonSerializer.SerializeToElement("Admin");
        return parts[0] + "." + Base64UrlEncoder.Encode(JsonSerializer.Serialize(payload)) + "." + parts[2];
    }

    private static bool IsRole(Claim claim) => claim.Type is "role" or "roles" || claim.Type == ClaimTypes.Role;

    private async Task<string> Snapshot()
    {
        using var scope = host.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
        var auth = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
        return JsonSerializer.Serialize(new
        {
            marks = await db.WayMarks.AsNoTracking().OrderBy(mark => mark.Id).ToListAsync(),
            users = await auth.Users.CountAsync(), roles = await auth.Roles.CountAsync(),
            memberships = await auth.UserRoles.CountAsync(), nodes = await db.NavigationNodes.CountAsync(),
            edges = await db.NavigationEdges.CountAsync()
        });
    }

    public async Task DisposeAsync()
    {
        client.Dispose();
        await host.StopAsync();
        host.Dispose();
    }

    private sealed class CountingEmail : ISmtpEmailService
    {
        public int Calls { get; private set; }
        public Task SendTestEmailAsync(DateTimeOffset sentAtUtc, CancellationToken cancellationToken)
        {
            Calls++;
            return Task.CompletedTask;
        }
    }
}
