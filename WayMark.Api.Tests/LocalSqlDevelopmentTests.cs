using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using WayMark.Api.Data;
using WayMark.Api.Models;
using WayMark.CoreSqlReadiness;
using Xunit;

namespace WayMark.Api.Tests;

public sealed class LocalSqlDevelopmentTests
{
    [Fact]
    public void Server_permission_probe_uses_SQL_Server_null_securable_class()
    {
        Assert.DoesNotContain("HAS_PERMS_BY_NAME(NULL,'SERVER'", ReadinessPlan.SessionVerificationSql);
        Assert.Equal(6, System.Text.RegularExpressions.Regex.Matches(ReadinessPlan.SessionVerificationSql,
            @"HAS_PERMS_BY_NAME\(NULL,NULL,").Count);
        Assert.Contains("HAS_PERMS_BY_NAME(DB_NAME(),'DATABASE','CONTROL')", ReadinessPlan.SessionVerificationSql);
    }
    private static ReadinessPlan Plan()
    {
        var run = Guid.NewGuid(); var prefix = "wm-core3-" + run.ToString("N");
        return new(run, Environment.MachineName, 1, [10, 11], new("a-id", prefix + "-a"), new("b-id", prefix + "-b"),
            Path.Combine(Path.GetTempPath(), run.ToString("N"), "images"), true, ReadinessPlan.CreatorAcknowledgement,
            true, true, Environment.MachineName + "\\fixture-operator");
    }
    private static int?[] Privileges() => [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0];

    [Fact]
    public void Local_sysadmin_exception_is_explicit_and_accepts_only_verified_Windows_session()
    {
        var p = Plan();
        p.ValidateActualTarget("WayMarkDatabase", p.ExpectedServerName, 0, 0, Privileges(), true,
            p.ExpectedWindowsIdentity, "NTLM", "Shared memory", false);
        p.ValidateActualTarget("WayMarkDatabase", p.ExpectedServerName, 0, 0, Privileges(), true,
            p.ExpectedWindowsIdentity, "KERBEROS", "TCP", true);
        var connection = p.Connection("Server=.;Database=WayMarkDatabase;Integrated Security=True;Encrypt=True;TrustServerCertificate=True;Connect Timeout=5", true);
        Assert.True(connection.IntegratedSecurity); Assert.Equal("True", connection.Encrypt.ToString());
        Assert.Throws<InvalidOperationException>(() => (p with { LocalDevelopmentSysadminRuntimeExceptionApproved = false })
            .ValidateActualTarget("WayMarkDatabase", p.ExpectedServerName, 0, 0, Privileges(), true,
                p.ExpectedWindowsIdentity, "NTLM", "Shared memory", false));
    }

    [Theory]
    [InlineData("approval")]
    [InlineData("missing-identity")]
    [InlineData("wrong-identity")]
    [InlineData("remote-server")]
    [InlineData("database")]
    [InlineData("transaction")]
    [InlineData("implicit")]
    [InlineData("SQL-auth")]
    [InlineData("network-plaintext")]
    [InlineData("unknown-encryption")]
    [InlineData("unknown-privilege")]
    [InlineData("missing-privileges")]
    public void Local_exception_does_not_remove_target_approval_identity_transport_or_privilege_checks(string fault)
    {
        var p = Plan(); var permissions = Privileges();
        if (fault == "approval") p = p with { WritesApproved = false };
        if (fault == "missing-identity") p = p with { ExpectedWindowsIdentity = null };
        if (fault == "remote-server") p = p with { ExpectedServerName = "UNAPPROVED-REMOTE" };
        if (fault == "unknown-privilege") permissions[0] = null;
        Assert.Throws<InvalidOperationException>(() => p.ValidateActualTarget(fault == "database" ? "WayMarkAuthDatabase" : "WayMarkDatabase",
            p.ExpectedServerName, fault == "transaction" ? 1 : 0, fault == "implicit" ? 2 : 0,
            fault == "missing-privileges" ? [] : permissions, true,
            fault == "wrong-identity" ? Environment.MachineName + "\\different-account" : p.ExpectedWindowsIdentity,
            fault == "SQL-auth" ? "SQL" : "NTLM", fault == "network-plaintext" ? "TCP" : "Shared memory",
            fault == "unknown-encryption" ? null : false));
    }

    [Theory]
    [InlineData("REMOTE")]
    [InlineData("tcp:192.168.1.15,1433")]
    [InlineData("localhost\\OTHERINSTANCE")]
    public void Elevated_runtime_exception_cannot_connect_to_remote_or_other_instance(string source)
    {
        Assert.Throws<InvalidOperationException>(() => Plan().Connection(
            $"Server={source};Database=WayMarkDatabase;Integrated Security=True;Encrypt=True;TrustServerCertificate=False;Connect Timeout=5", true));
    }

    [Theory]
    [InlineData("not-approved")]
    [InlineData("reserved-name")]
    [InlineData("second-password-invalid")]
    [InlineData("preexisting-id")]
    [InlineData("used-floor")]
    public async Task Bootstrap_refuses_unsafe_or_failed_creation_without_overwriting_existing_users(string fault)
    {
        await using var h = new MapDraftTestHost(withIdentity: true); await h.StartAsync();
        var p = Plan();
        // Both empty IDs and the exact same RunId namespace are mandatory.
        p = p with { CreatorA = new("", "wm-core3-" + p.RunId.ToString("N") + "-a"), CreatorB = new("", "wm-core3-" + p.RunId.ToString("N") + "-b") };
        using var scope = h.Scope();
        var users = scope.ServiceProvider.GetRequiredService<UserManager<IdentityUser>>();
        var auth = scope.ServiceProvider.GetRequiredService<AuthDbContext>(); var map = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
        var password = "Aa1!" + Guid.NewGuid().ToString("N");
        string? preservedId = null;
        if (fault == "reserved-name") {
            var original = new IdentityUser { UserName = p.CreatorA.UserName, Email = "existing@example.invalid" };
            Assert.True((await users.CreateAsync(original, password)).Succeeded); preservedId = original.Id;
        }
        if (fault == "preexisting-id") p = p with { CreatorA = p.CreatorA with { Id = "must-not-adopt" } };
        if (fault == "used-floor") {
            map.FloorMapDrafts.Add(new FloorMapDraft { Id = Guid.NewGuid(), FloorId = 10, Version = 1, CreatedBy = "existing-owner", UpdatedBy = "existing-owner" });
            await map.SaveChangesAsync();
        }
        await Assert.ThrowsAsync<InvalidOperationException>(() => TestCreatorBootstrap.CreateAsync(p, fault != "not-approved", users, auth, map,
            password, fault == "second-password-invalid" ? "lowercase123" : password));
        Assert.Equal(preservedId is null ? 0 : 1, await auth.Users.CountAsync());
        if (preservedId is not null) Assert.Equal("existing@example.invalid", (await users.FindByIdAsync(preservedId))!.Email);
        Assert.Empty(await auth.UserRoles.ToListAsync()); Assert.Empty(await auth.Roles.ToListAsync());
    }
}
