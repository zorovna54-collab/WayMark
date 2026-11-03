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
using Microsoft.AspNetCore.DataProtection;
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
                }).AddRoles<IdentityRole>().AddEntityFrameworkStores<AuthDbContext>().AddDefaultTokenProviders();
                services.AddDataProtection().UseEphemeralDataProtectionProvider();
                services.AddWayMarkSecurity(configuration);
                services.AddPasswordResetLimits();
                services.AddSingleton<DijkstraRouter>();
                services.AddScoped<IRoutePlanner, RoutePlanner>();
                services.AddSingleton<ISmtpEmailService>(email);
                services.AddControllers().AddApplicationPart(typeof(AuthController).Assembly);
            }).Configure(app =>
            {
                app.UseRouting();
                app.UseRateLimiter();
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
        Assert.Equal(0, email.PasswordResetCalls);
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
    public void EveryWriteActionRequiresItsExplicitAdminResourceOrSelfProfileAuthorization()
    {
        var controllers = typeof(WayMarksController).Assembly.GetTypes()
            .Where(type => !type.IsAbstract && typeof(ControllerBase).IsAssignableFrom(type));
        var protectedActions = 0;
        var authorActions = 0;
        var selfProfileActions = 0;
        var personalActions = 0;
        var accountSecurityActions = 0;
        var privateHistoryActions = 0;
        foreach (var controller in controllers)
        foreach (var method in controller.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly))
        {
            if (!method.GetCustomAttributes<HttpMethodAttribute>().Any(attribute =>
                    attribute.HttpMethods.Any(verb => verb is "POST" or "PUT" or "PATCH" or "DELETE"))) continue;
            if (controller == typeof(AuthController) && method.Name is "Login" or "Register" or "ForgotPassword" or "ResetPassword")
            {
                Assert.Single(method.GetCustomAttributes<AllowAnonymousAttribute>());
                continue;
            }
            if (controller == typeof(RoutesController) && method.Name == "FindRoute") continue;
            if (controller == typeof(AuthController) && method.Name is "RequestEmailBinding" or "ConfirmEmailBinding" or "ChangeOwnPassword") {
                Assert.Single(method.GetCustomAttributes<AuthorizeAttribute>());
                Assert.Empty(method.GetCustomAttributes<AllowAnonymousAttribute>());
                accountSecurityActions++; continue;
            }
            if (controller == typeof(NavigationHistoryController)) {
                Assert.Single(controller.GetCustomAttributes<AuthorizeAttribute>());
                Assert.Empty(controller.GetCustomAttributes<AllowAnonymousAttribute>());
                privateHistoryActions++; continue; // HTTP tests verify per-subject access, including denial to other Admins.
            }
            if (controller == typeof(PersonalMapsController)) {
                Assert.Single(controller.GetCustomAttributes<AuthorizeAttribute>());
                Assert.Empty(controller.GetCustomAttributes<AllowAnonymousAttribute>());
                Assert.Empty(method.GetCustomAttributes<AllowAnonymousAttribute>());
                personalActions++;
                continue; // HTTP tests verify user identity, new-scope-only grants and atomic rollback.
            }
            if (controller == typeof(AuthController) && method.Name == nameof(AuthController.UpdateMe)) {
                Assert.Single(method.GetCustomAttributes<AuthorizeAttribute>());
                Assert.Empty(method.GetCustomAttributes<AllowAnonymousAttribute>());
                var parameter = Assert.Single(method.GetParameters());
                Assert.Equal(typeof(UpdateProfileRequest), parameter.ParameterType);
                Assert.Equal(new[] { "DisplayName" }, parameter.ParameterType.GetProperties().Select(p => p.Name));
                selfProfileActions++;
                continue; // Dedicated HTTP tests verify JWT subject binding and no privilege/identity writes.
            }
            var authorization = controller.GetCustomAttributes<AuthorizeAttribute>()
                .Concat(method.GetCustomAttributes<AuthorizeAttribute>());
            var mapAuthor = controller == typeof(MapDraftsController) || controller == typeof(MapProjectsController);
            Assert.Contains(authorization, attribute => attribute.Policy == (mapAuthor
                ? WayMarkSecurity.MapAuthorPolicy : WayMarkSecurity.AdminPolicy));
            if (mapAuthor) authorActions++;
            Assert.Empty(controller.GetCustomAttributes<AllowAnonymousAttribute>());
            Assert.Empty(method.GetCustomAttributes<AllowAnonymousAttribute>());
            protectedActions++;
        }
        Assert.Equal(14, protectedActions); // Nine existing actions + five owner-scoped project/publish/QR actions.
        Assert.Equal(10, authorActions); // Explicit exception only for floor/project resource authorization; four global writes stay AdminOnly.
        Assert.Equal(1, selfProfileActions);
        Assert.Equal(2, personalActions);
        Assert.Equal(3, accountSecurityActions);
        Assert.Equal(5, privateHistoryActions); // Scan, destination, start, end and delete; all JWT + per-subject.
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

    [Fact]
    public async Task Profile_persists_display_name_but_cannot_change_roles_or_identity()
    {
        SetToken(await Login("reader-fixture"));
        using var response = await client.PutAsJsonAsync("/api/Auth/me", new {
            displayName = "  Người dùng thử  ", roles = new[] { "Admin" },
            userName = "operator-fixture", email = "changed@example.invalid", emailVerified = true
        });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var profile = await client.GetFromJsonAsync<JsonElement>("/api/Auth/me");
        Assert.Equal("Người dùng thử", profile.GetProperty("displayName").GetString());
        Assert.Equal("reader-fixture", profile.GetProperty("userName").GetString());
        Assert.False(profile.GetProperty("emailVerified").GetBoolean());
        Assert.Empty(profile.GetProperty("roles").EnumerateArray());
        using var scope = host.Services.CreateScope();
        var users = scope.ServiceProvider.GetRequiredService<UserManager<IdentityUser>>();
        var reader = (await users.FindByNameAsync("reader-fixture"))!;
        Assert.Empty(await users.GetRolesAsync(reader));
        Assert.NotEqual("changed@example.invalid", reader.Email);
        Assert.DoesNotContain(await users.GetClaimsAsync((await users.FindByNameAsync("operator-fixture"))!), c => c.Type == "waymark:display_name");
    }

    [Theory]
    [InlineData("missing")]
    [InlineData("expired")]
    [InlineData("wrong-signature")]
    [InlineData("forged")]
    public async Task Profile_requires_a_valid_signed_JWT_without_mutation(string kind)
    {
        SetToken(kind switch {
            "missing" => null,
            "forged" => ForgeRole(await Login("reader-fixture")),
            _ => SignedAdminToken(kind)
        });
        using var get = await client.GetAsync("/api/Auth/me");
        using var put = await client.PutAsJsonAsync("/api/Auth/me", new { displayName = "must-not-save" });
        Assert.Equal(HttpStatusCode.Unauthorized, get.StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, put.StatusCode);
        using var scope = host.Services.CreateScope();
        var auth = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
        Assert.False(await auth.UserClaims.AnyAsync(c => c.ClaimType == "waymark:display_name"));
    }

    [Fact]
    public async Task Profile_rejects_invalid_names_and_displays_effective_roles()
    {
        SetToken(await Login("operator-fixture"));
        foreach (var name in new[] { "  ", new string('x', 81), "name\nrole" }) {
            using var response = await client.PutAsJsonAsync("/api/Auth/me", new { displayName = name });
            Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        }
        var profile = await client.GetFromJsonAsync<JsonElement>("/api/Auth/me");
        Assert.Contains("Admin", profile.GetProperty("roles").EnumerateArray().Select(r => r.GetString()));
    }

    [Fact]
    public async Task Password_reset_token_is_user_bound_single_use_and_changes_login()
    {
        using (var scope = host.Services.CreateScope()) {
            var users = scope.ServiceProvider.GetRequiredService<UserManager<IdentityUser>>();
            Assert.True((await users.SetEmailAsync((await users.FindByNameAsync("reader-fixture"))!, "reader@example.invalid")).Succeeded);
        }
        using var sent = await client.PostAsJsonAsync("/api/Auth/forgot-password", new { usernameOrEmail = "reader-fixture" });
        Assert.Equal(HttpStatusCode.OK, sent.StatusCode);
        Assert.False(string.IsNullOrEmpty(email.ResetToken));
        var next = Convert.ToBase64String(RandomNumberGenerator.GetBytes(24)) + "aA1!";
        using var wrongUser = await client.PostAsJsonAsync("/api/Auth/reset-password", new { usernameOrEmail = "operator-fixture", token = email.ResetToken, newPassword = next });
        Assert.Equal(HttpStatusCode.BadRequest, wrongUser.StatusCode);
        using var reset = await client.PostAsJsonAsync("/api/Auth/reset-password", new { usernameOrEmail = "reader-fixture", token = email.ResetToken, newPassword = next });
        Assert.Equal(HttpStatusCode.OK, reset.StatusCode);
        using var replay = await client.PostAsJsonAsync("/api/Auth/reset-password", new { usernameOrEmail = "reader-fixture", token = email.ResetToken, newPassword = next });
        Assert.Equal(HttpStatusCode.BadRequest, replay.StatusCode);
        using var oldLogin = await client.PostAsJsonAsync("/api/Auth/login", new { username = "reader-fixture", password });
        Assert.Equal(HttpStatusCode.Unauthorized, oldLogin.StatusCode);
        using var newLogin = await client.PostAsJsonAsync("/api/Auth/login", new { username = "reader-fixture", password = next });
        Assert.Equal(HttpStatusCode.OK, newLogin.StatusCode);
    }

    [Fact]
    public async Task Password_reset_requests_do_not_enumerate_accounts_and_are_rate_limited()
    {
        using var existing = await client.PostAsJsonAsync("/api/Auth/forgot-password", new { usernameOrEmail = "reader-fixture" });
        using var missing = await client.PostAsJsonAsync("/api/Auth/forgot-password", new { usernameOrEmail = "absent-fixture" });
        Assert.Equal(await existing.Content.ReadAsStringAsync(), await missing.Content.ReadAsStringAsync());
        for (var i = 0; i < 3; i++) {
            using var response = await client.PostAsJsonAsync("/api/Auth/forgot-password", new { usernameOrEmail = "absent-fixture" });
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        }
        using var limited = await client.PostAsJsonAsync("/api/Auth/reset-password", new { usernameOrEmail = "reader-fixture", token = "invalid", newPassword = "Wrong-test-only1" });
        Assert.Equal(HttpStatusCode.TooManyRequests, limited.StatusCode);
    }

    [Fact]
    public async Task Password_reset_rejects_expired_tokens_without_password_change()
    {
        using var scope = host.Services.CreateScope();
        var users = scope.ServiceProvider.GetRequiredService<UserManager<IdentityUser>>();
        var user = (await users.FindByNameAsync("reader-fixture"))!;
        var options = scope.ServiceProvider.GetRequiredService<Microsoft.Extensions.Options.IOptions<Microsoft.AspNetCore.Identity.DataProtectionTokenProviderOptions>>().Value;
        options.TokenLifespan = TimeSpan.FromMilliseconds(1);
        var token = await users.GeneratePasswordResetTokenAsync(user);
        await Task.Delay(30);
        using var response = await client.PostAsJsonAsync("/api/Auth/reset-password", new { usernameOrEmail = "reader-fixture", token, newPassword = "New-test-only1" });
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.True(await users.CheckPasswordAsync((await users.FindByIdAsync(user.Id))!, password));
    }

    [Fact]
    public async Task Password_reset_ambiguous_email_does_not_choose_an_account()
    {
        using (var scope = host.Services.CreateScope()) {
            var users = scope.ServiceProvider.GetRequiredService<UserManager<IdentityUser>>();
            foreach (var name in new[] { "reader-fixture", "operator-fixture" })
                Assert.True((await users.SetEmailAsync((await users.FindByNameAsync(name))!, "shared@example.invalid")).Succeeded);
        }
        using var shared = await client.PostAsJsonAsync("/api/Auth/forgot-password", new { usernameOrEmail = "shared@example.invalid" });
        using var absent = await client.PostAsJsonAsync("/api/Auth/forgot-password", new { usernameOrEmail = "absent@example.invalid" });
        Assert.Equal(HttpStatusCode.OK, shared.StatusCode);
        Assert.Equal(await absent.Content.ReadAsStringAsync(), await shared.Content.ReadAsStringAsync());
        Assert.Equal(0, email.PasswordResetCalls);
        using var username = await client.PostAsJsonAsync("/api/Auth/forgot-password", new { usernameOrEmail = "reader-fixture" });
        Assert.Equal(HttpStatusCode.OK, username.StatusCode);
        Assert.Equal(1, email.PasswordResetCalls);
    }

    [Fact]
    public async Task Anonymous_forgot_password_does_not_call_or_relax_Admin_email_endpoint_even_on_SMTP_failure()
    {
        using (var scope = host.Services.CreateScope()) {
            var users = scope.ServiceProvider.GetRequiredService<UserManager<IdentityUser>>();
            Assert.True((await users.SetEmailAsync((await users.FindByNameAsync("reader-fixture"))!, "reset@example.invalid")).Succeeded);
        }
        SetToken(null); email.FailReset = true;
        using var response = await client.PostAsJsonAsync("/api/Auth/forgot-password", new { usernameOrEmail = "reader-fixture" });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(1, email.PasswordResetCalls); Assert.Equal(0, email.Calls);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.PostAsync("/api/Email/test", null)).StatusCode);
        SetToken(await Login("reader-fixture"));
        Assert.Equal(HttpStatusCode.Forbidden, (await client.PostAsync("/api/Email/test", null)).StatusCode);
    }

    [Fact]
    public async Task Map_author_role_revocation_is_effective_for_an_existing_JWT()
    {
        SetToken(await Login("operator-fixture"));
        using (var scope = host.Services.CreateScope()) {
            var users = scope.ServiceProvider.GetRequiredService<UserManager<IdentityUser>>();
            Assert.True((await users.RemoveFromRoleAsync((await users.FindByNameAsync("operator-fixture"))!, "Admin")).Succeeded);
        }
        Assert.Equal(HttpStatusCode.Forbidden, (await client.GetAsync("/api/admin/map-projects")).StatusCode);
        var before = await Snapshot();
        Assert.Equal(HttpStatusCode.Forbidden, (await Write("create")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await Write("email")).StatusCode);
        Assert.Equal(before, await Snapshot());
        var me = await client.GetFromJsonAsync<JsonElement>("/api/Auth/me");
        Assert.Empty(me.GetProperty("roles").EnumerateArray());
        Assert.False(me.GetProperty("capabilities").GetProperty("isSystemAdmin").GetBoolean());
    }

    public async Task DisposeAsync()
    {
        client.Dispose();
        await host.StopAsync();
        host.Dispose();
    }

    [Fact]
    public async Task PasswordResetEmailIsCountedSeparatelyWithoutSmtp()
    {
        using (var scope = host.Services.CreateScope())
        {
            var users = scope.ServiceProvider.GetRequiredService<UserManager<IdentityUser>>();
            var user = (await users.FindByNameAsync("reader-fixture"))!;
            Assert.True((await users.SetEmailAsync(user, "reader@example.invalid")).Succeeded);
        }
        using var response = await client.PostAsJsonAsync("/api/Auth/forgot-password", new { usernameOrEmail = "reader-fixture" });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(1, email.PasswordResetCalls);
        Assert.Equal("reader@example.invalid", email.ResetRecipient);
        Assert.Equal(0, email.Calls);
        using var unknown = await client.PostAsJsonAsync("/api/Auth/forgot-password", new { usernameOrEmail = "unknown-fixture" });
        Assert.Equal(HttpStatusCode.OK, unknown.StatusCode);
        Assert.Equal(1, email.PasswordResetCalls);
    }

    [Fact]
    public async Task AccountWithoutEmailDoesNotSendResetMail()
    {
        using var response = await client.PostAsJsonAsync("/api/Auth/forgot-password", new { usernameOrEmail = "reader-fixture" });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(0, email.PasswordResetCalls);
        Assert.Equal(0, email.Calls);
    }

    private sealed class CountingEmail : ISmtpEmailService
    {
        public int Calls { get; private set; }
        public int PasswordResetCalls { get; private set; }
        public string? ResetRecipient { get; private set; }
        public string? ResetToken { get; private set; } // Isolated test memory only; never logged.
        public bool FailReset { get; set; }
        public Task SendTestEmailAsync(DateTimeOffset sentAtUtc, CancellationToken cancellationToken)
        {
            Calls++;
            return Task.CompletedTask;
        }
        public Task SendPasswordResetEmailAsync(string toEmail, string username,
            string resetToken, string resetUrl, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            PasswordResetCalls++;
            ResetRecipient = toEmail;
            ResetToken = resetToken;
            if (FailReset) throw new SmtpEmailException(SmtpEmailFailure.Configuration, "Isolated missing SMTP config");
            return Task.CompletedTask;
        }
    }
}
