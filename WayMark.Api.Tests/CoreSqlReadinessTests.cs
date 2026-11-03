using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using WayMark.Api.Data;
using WayMark.CoreSqlReadiness;
using Xunit;

namespace WayMark.Api.Tests;

public sealed class CoreSqlReadinessTests
{
    private static ReadinessPlan Plan()
    {
        var run = Guid.NewGuid(); var prefix = "wm-core3-" + run.ToString("N");
        return new(run, "APPROVED-SERVER", 1, [10, 11], new("a-id", prefix + "-a"), new("b-id", prefix + "-b"),
            Path.Combine(Path.GetTempPath(), run.ToString("N"), "images"), true, ReadinessPlan.CreatorAcknowledgement);
    }
    [Fact]
    public void Approval_is_explicit_and_storage_validation_does_not_create_files()
    {
        var p = Plan();
        Assert.Throws<InvalidOperationException>(() => p.RequireApproval(false));
        Assert.Throws<InvalidOperationException>(() => (p with { WritesApproved = false }).RequireApproval(true));
        Assert.Throws<InvalidOperationException>(() => (p with { CreatorScopeAcknowledgement = null }).RequireApproval(true));
        Assert.Throws<InvalidOperationException>(() => (p with { CreatorA = new("existing", "admin") }).RequireApproval(true));
        p.RequireApproval(true);
        p.ValidateImageRoot(AppContext.BaseDirectory);
        Assert.False(Directory.Exists(p.ImageRoot));
    }
    [Theory]
    [InlineData("")]
    [InlineData("Server=.;Database=WayMarkAuthDatabase;Integrated Security=True;Encrypt=True;Connect Timeout=5")]
    [InlineData("Server=.;Database=WayMark_MapDraft_E2E_Test;Integrated Security=True;Encrypt=True;Connect Timeout=5")]
    [InlineData("Server=.;Database=WayMarkDatabase;Integrated Security=True;Encrypt=False;Connect Timeout=5")]
    [InlineData("Server=.;Database=WayMarkDatabase;Integrated Security=True;Encrypt=True;TrustServerCertificate=True;Connect Timeout=5")]
    public void Connection_target_never_falls_back(string value) => Assert.Throws<InvalidOperationException>(() => Plan().Connection(value, true));

    [Theory]
    [InlineData(".")]
    [InlineData("localhost")]
    public void Local_certificate_exception_requires_explicit_approved_run_and_keeps_encryption(string server)
    {
        var p = Plan() with { ExpectedServerName = Environment.MachineName, LocalDevelopmentCertificateExceptionApproved = true };
        var text = $"Server={server};Database=WayMarkDatabase;Integrated Security=True;Encrypt=True;TrustServerCertificate=True;Connect Timeout=5";
        var result = p.Connection(text, true);
        Assert.True(result.TrustServerCertificate); Assert.Equal("True", result.Encrypt.ToString());
        Assert.Throws<InvalidOperationException>(() => (p with { LocalDevelopmentCertificateExceptionApproved = false }).Connection(text, true));
        Assert.Throws<InvalidOperationException>(() => (p with { WritesApproved = false }).Connection(text, true));
        Assert.Throws<InvalidOperationException>(() => (p with { CreatorScopeAcknowledgement = null }).Connection(text, true));
        Assert.Throws<InvalidOperationException>(() => (p with { ExpectedServerName = "OTHER-SERVER" }).Connection(text, true));
    }
    [Theory]
    [InlineData("Server=REMOTE-SERVER;Database=WayMarkDatabase;Integrated Security=True;Encrypt=True;TrustServerCertificate=True;Connect Timeout=5")]
    [InlineData("Server=tcp:192.168.1.15,1433;Database=WayMarkDatabase;Integrated Security=True;Encrypt=True;TrustServerCertificate=True;Connect Timeout=5")]
    [InlineData("Server=.;Database=WayMarkAuthDatabase;Integrated Security=True;Encrypt=True;TrustServerCertificate=True;Connect Timeout=5")]
    [InlineData("Server=.;Database=WayMarkDatabase;Integrated Security=True;Encrypt=False;TrustServerCertificate=True;Connect Timeout=5")]
    [InlineData("Server=.;Database=WayMarkDatabase;User ID=test-fixture-only;Encrypt=True;TrustServerCertificate=True;Connect Timeout=5")]
    public void Local_certificate_exception_never_allows_remote_wrong_database_plaintext_or_SQL_login(string text)
    {
        var p = Plan() with { ExpectedServerName = Environment.MachineName, LocalDevelopmentCertificateExceptionApproved = true };
        Assert.Throws<InvalidOperationException>(() => p.Connection(text, true));
    }

    [Fact]
    public void Legacy_Admin_consent_does_not_authorize_the_new_Creator_grant()
    {
        var json = new System.Text.Json.JsonSerializerOptions(System.Text.Json.JsonSerializerDefaults.Web);
        var node = System.Text.Json.JsonSerializer.SerializeToNode(Plan(), json)!.AsObject();
        node.Remove("creatorScopeAcknowledgement");
        node["adminScopeAcknowledgement"] = "Admin grants global WayMark write access, not only test maps";
        var legacy = node.Deserialize<ReadinessPlan>(json)!;
        Assert.Throws<InvalidOperationException>(() => legacy.RequireApproval(true));
    }

    [Theory]
    [InlineData("Admin")]
    [InlineData("SiteManager")]
    [InlineData("SitePublisher:2")]
    public async Task Creator_setup_refuses_privileged_or_other_Site_accounts_without_removing_roles(string role)
    {
        await using var h = new MapDraftTestHost(withIdentity: true); await h.StartAsync(); var p = Plan();
        using var scope = h.Scope(); var users = scope.ServiceProvider.GetRequiredService<UserManager<IdentityUser>>();
        var roles = scope.ServiceProvider.GetRequiredService<RoleManager<IdentityRole>>();
        var a = new IdentityUser { UserName = p.CreatorA.UserName, Email = p.CreatorA.UserName + "@example.invalid" };
        var b = new IdentityUser { UserName = p.CreatorB.UserName, Email = p.CreatorB.UserName + "@example.invalid" };
        Assert.True((await users.CreateAsync(a)).Succeeded); Assert.True((await users.CreateAsync(b)).Succeeded);
        Assert.True((await roles.CreateAsync(new(role))).Succeeded); Assert.True((await users.AddToRoleAsync(a, role)).Succeeded);
        p = p with { CreatorA = p.CreatorA with { Id = a.Id }, CreatorB = p.CreatorB with { Id = b.Id } };
        var map = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>(); var auth = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
        await Assert.ThrowsAsync<InvalidOperationException>(() => TestCreatorAccess.GrantAsync(p, true, users, roles, auth, map));
        Assert.Equal(new[] { role }, await users.GetRolesAsync(a)); Assert.Empty(await users.GetRolesAsync(b));
        Assert.Equal(1, await auth.Roles.CountAsync());
        Assert.False(await map.SiteMapMemberships.AnyAsync(m => m.UserId == a.Id || m.UserId == b.Id));
    }

    [Theory]
    [InlineData("database")]
    [InlineData("server")]
    [InlineData("transaction")]
    [InlineData("implicit")]
    [InlineData("sysadmin")]
    [InlineData("securityadmin")]
    [InlineData("unknown-permission")]
    [InlineData("missing-permissions")]
    public void Actual_runtime_target_and_privileges_fail_closed(string fault)
    {
        var p = Plan(); var permissions = Enumerable.Repeat<int?>(0, 15).ToArray();
        if (fault == "sysadmin") permissions[0] = 1;
        if (fault == "securityadmin") permissions[12] = 1;
        if (fault == "unknown-permission") permissions[0] = null;
        Assert.Throws<InvalidOperationException>(() => p.ValidateActualTarget(fault == "database" ? "WayMarkAuthDatabase" : ReadinessPlan.Database,
            fault == "server" ? "OTHER-SERVER" : p.ExpectedServerName, fault == "transaction" ? 1 : 0, fault == "implicit" ? 2 : 0,
            fault == "missing-permissions" ? [] : permissions, true));
        p.ValidateActualTarget(ReadinessPlan.Database, p.ExpectedServerName, 0, 0, Enumerable.Repeat<int?>(0, 15).ToArray(), true);
    }

    [Fact]
    public void Existing_storage_files_are_preserved_when_refused()
    {
        using var disk = new ManagedImageTestStorage(); var p = Plan();
        var root = Path.Combine(disk.DirectoryPath, p.RunId.ToString("N"), "images"); Directory.CreateDirectory(root);
        var file = Path.Combine(root, "keep.txt"); File.WriteAllText(file, "test-owned content");
        Assert.Throws<InvalidOperationException>(() => (p with { ImageRoot = root }).ValidateImageRoot(AppContext.BaseDirectory));
        Assert.Equal("test-owned content", File.ReadAllText(file));
    }

    [Fact]
    public async Task Failed_membership_write_rolls_back_Identity_role_and_both_grants()
    {
        await using var h = new MapDraftTestHost(withIdentity: true); await h.StartAsync(); var p = Plan();
        using (var scope = h.Scope()) {
            var users = scope.ServiceProvider.GetRequiredService<UserManager<IdentityUser>>();
            var a = new IdentityUser { UserName = p.CreatorA.UserName, Email = p.CreatorA.UserName + "@example.invalid" };
            var b = new IdentityUser { UserName = p.CreatorB.UserName, Email = p.CreatorB.UserName + "@example.invalid" };
            Assert.True((await users.CreateAsync(a)).Succeeded); Assert.True((await users.CreateAsync(b)).Succeeded);
            p = p with { CreatorA = p.CreatorA with { Id = a.Id }, CreatorB = p.CreatorB with { Id = b.Id } };
            var map = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
            h.Failure.Armed = true; h.Failure.FailAtWrite = 1;
            await Assert.ThrowsAnyAsync<Exception>(() => TestCreatorAccess.GrantAsync(p, true, users,
                scope.ServiceProvider.GetRequiredService<RoleManager<IdentityRole>>(), scope.ServiceProvider.GetRequiredService<AuthDbContext>(), map));
        }
        using var check = h.Scope();
        var auth = check.ServiceProvider.GetRequiredService<AuthDbContext>();
        Assert.Empty(await auth.Roles.ToListAsync()); Assert.Empty(await auth.UserRoles.ToListAsync());
        Assert.False(await check.ServiceProvider.GetRequiredService<WayMarkDbContext>().SiteMapMemberships.AnyAsync(x => x.UserId == p.CreatorA.Id || x.UserId == p.CreatorB.Id));
        Assert.Equal(2, await auth.Users.CountAsync());
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void Sql_server_preview_is_additive_target_guarded_and_only_writes_migration_history(bool idempotent)
    {
        var sql = MigrationPreview.Generate(idempotent);
        foreach (var forbidden in new[] { "DROP ", "TRUNCATE ", "DELETE FROM ", "UPDATE [", "CREATE DATABASE", "USE [", "CREATE TABLE [AspNet", "ALTER TABLE [WayMarks]" })
            Assert.DoesNotContain(forbidden, sql, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("SESSION_CONTEXT(N'WayMarkApprovedServer')", sql);
        Assert.Contains("IF @@TRANCOUNT <> 0", sql);
        Assert.True(sql.IndexOf("RAISERROR", StringComparison.Ordinal) < sql.IndexOf("SET XACT_ABORT ON", StringComparison.Ordinal));
        Assert.Contains("DB_NAME()", sql);
        Assert.Contains("INSERT INTO [__EFMigrationsHistory]", sql);
        Assert.DoesNotContain("INSERT INTO [AspNet", sql);
        Assert.Equal(idempotent, sql.Contains("WHERE [MigrationId] = N'20261020094848_AddMapDraftFoundation'", StringComparison.Ordinal));
    }

    [Fact]
    public async Task Real_Identity_login_grant_multifloor_http_workflow_and_restart_on_sqlite_files()
    {
        using var disk = new ManagedImageTestStorage(); var p = Plan();
        var password = "Aa1!" + Convert.ToBase64String(RandomNumberGenerator.GetBytes(24));
        E2eEvidence result;
        await using (var h = new MapDraftTestHost(disk.Provider(), sqlitePath: disk.DatabasePath, withIdentity: true)) {
            await h.StartAsync();
            using (var scope = h.Scope()) {
                var users = scope.ServiceProvider.GetRequiredService<UserManager<IdentityUser>>();
                var roles = scope.ServiceProvider.GetRequiredService<RoleManager<IdentityRole>>();
                var auth = scope.ServiceProvider.GetRequiredService<AuthDbContext>(); var map = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
                p = await TestCreatorBootstrap.CreateAsync(p with { CreatorA = p.CreatorA with { Id = "" }, CreatorB = p.CreatorB with { Id = "" } },
                    true, users, auth, map, password, password);
                var a = (await users.FindByIdAsync(p.CreatorA.Id))!; var b = (await users.FindByIdAsync(p.CreatorB.Id))!;
                await Assert.ThrowsAsync<InvalidOperationException>(() => TestCreatorAccess.GrantAsync(p, false, users, roles, auth, map));
                Assert.False(await users.IsInRoleAsync(a, "Admin"));
                await TestCreatorAccess.GrantAsync(p, true, users, roles, auth, map);
                await TestCreatorAccess.GrantAsync(p, true, users, roles, auth, map);
                Assert.False(await roles.RoleExistsAsync("Admin"));
                Assert.True(await users.IsInRoleAsync(a, "Creator"));
                Assert.True(await users.IsInRoleAsync(b, "Creator"));
                Assert.True(await users.IsInRoleAsync(a, "SitePublisher:1"));
                Assert.False(await users.IsInRoleAsync(b, "SitePublisher:1"));
                Assert.False(await users.IsInRoleAsync(a, "Admin"));
                Assert.Equal(2, await map.SiteMapMemberships.CountAsync(x => x.UserId == a.Id || x.UserId == b.Id));
            }
            using var aClient = h.NewClient(); using var bClient = h.NewClient(); using var guest = h.NewClient();
            await SqlE2eWorkflow.Login(aClient, p.CreatorA, password); await SqlE2eWorkflow.Login(bClient, p.CreatorB, password);
            result = await SqlE2eWorkflow.Create(aClient, bClient, guest, p, _ => { });
        }
        await using (var h = new MapDraftTestHost(disk.Provider(), sqlitePath: disk.DatabasePath, withIdentity: true)) {
            await h.StartAsync(); using var guest = h.NewClient(); using var aClient = h.NewClient();
            await SqlE2eWorkflow.Verify(guest, result);
            await SqlE2eWorkflow.Login(aClient, p.CreatorA, password);
            await SqlE2eWorkflow.VerifyPrivateAfterRestart(aClient, result);
            await SqlE2eWorkflow.Revoke(aClient, guest, result);
            using var scope = h.Scope(); var map = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
            Assert.Equal(2, await map.NavigationNodes.CountAsync()); Assert.Equal(1, await map.NavigationEdges.CountAsync());
            Assert.Equal(2, await scope.ServiceProvider.GetRequiredService<AuthDbContext>().Users.CountAsync());
        }
    }
}
