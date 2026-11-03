using Microsoft.Data.SqlClient;

namespace WayMark.CoreSqlReadiness;

public sealed record TestAccount(string Id, string UserName);
public sealed record ReadinessPlan(Guid RunId, string ExpectedServerName, int SiteId, int[] FloorIds,
    TestAccount CreatorA, TestAccount CreatorB, string ImageRoot, bool WritesApproved = false,
    string? CreatorScopeAcknowledgement = null, bool LocalDevelopmentCertificateExceptionApproved = false,
    bool LocalDevelopmentSysadminRuntimeExceptionApproved = false, string? ExpectedWindowsIdentity = null)
{
    public const string Database = "WayMarkDatabase";
    public const string CreatorAcknowledgement = "Creator and owned-map publication are granted only within the approved Site membership";
    // For server permissions both securable and class are NULL. 'SERVER' as
    // class makes SQL Server return NULL, which must never be treated as a grant.
    public const string SessionVerificationSql = """
SELECT DB_NAME(),CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')),@@TRANCOUNT,@@OPTIONS,
 IS_SRVROLEMEMBER('sysadmin'),HAS_PERMS_BY_NAME(NULL,NULL,'CONTROL SERVER'),
 HAS_PERMS_BY_NAME(DB_NAME(),'DATABASE','CONTROL'),HAS_PERMS_BY_NAME(DB_NAME(),'DATABASE','ALTER ANY SCHEMA'),
 HAS_PERMS_BY_NAME(DB_NAME(),'DATABASE','CREATE TABLE'),HAS_PERMS_BY_NAME(DB_NAME(),'DATABASE','ALTER ANY USER'),
 HAS_PERMS_BY_NAME(DB_NAME(),'DATABASE','ALTER ANY ROLE'),
 HAS_PERMS_BY_NAME(NULL,NULL,'ALTER ANY LOGIN'),HAS_PERMS_BY_NAME(NULL,NULL,'IMPERSONATE ANY LOGIN'),
 HAS_PERMS_BY_NAME(NULL,NULL,'ALTER ANY DATABASE'),HAS_PERMS_BY_NAME(NULL,NULL,'CREATE ANY DATABASE'),
 HAS_PERMS_BY_NAME(NULL,NULL,'CONNECT ANY DATABASE'),IS_SRVROLEMEMBER('securityadmin'),
 IS_SRVROLEMEMBER('serveradmin'),IS_SRVROLEMEMBER('dbcreator'),ORIGINAL_LOGIN(),
 (SELECT auth_scheme FROM sys.dm_exec_connections WHERE session_id=@@SPID),
 (SELECT net_transport FROM sys.dm_exec_connections WHERE session_id=@@SPID),
 (SELECT encrypt_option FROM sys.dm_exec_connections WHERE session_id=@@SPID)
""";
    public void ValidateActualTarget(string database, string server, int transactionCount, int options,
        IReadOnlyList<int?> dangerousPermissions, bool runtime, string? originalLogin = null,
        string? authScheme = null, string? netTransport = null, bool? sessionEncrypted = null,
        bool bootstrap = false)
    {
        if (database != Database || server != ExpectedServerName || transactionCount != 0 || (options & 2) != 0)
            throw new InvalidOperationException("Actual target/session/runtime privileges refused. No writes started");
        if (LocalDevelopmentSysadminRuntimeExceptionApproved) {
            RequireApproval(true, bootstrap);
            if (!ExpectedServerName.Equals(Environment.MachineName, StringComparison.OrdinalIgnoreCase)
                || string.IsNullOrWhiteSpace(ExpectedWindowsIdentity)
                || !ExpectedWindowsIdentity.StartsWith(Environment.MachineName + "\\", StringComparison.OrdinalIgnoreCase)
                || !string.Equals(originalLogin, ExpectedWindowsIdentity, StringComparison.OrdinalIgnoreCase)
                || authScheme is not ("NTLM" or "KERBEROS")
                || netTransport is not ("Shared memory" or "TCP" or "Named pipe")
                || sessionEncrypted is null || (sessionEncrypted != true && netTransport != "Shared memory"))
                throw new InvalidOperationException("Local Development SQL identity/transport exception refused");
        }
        if (runtime && (dangerousPermissions.Count != 15 || dangerousPermissions.Any(p => p is null || p is < 0 or > 1)
            || (dangerousPermissions.Any(p => p != 0)
                && !(LocalDevelopmentSysadminRuntimeExceptionApproved && dangerousPermissions[0] == 1))))
            throw new InvalidOperationException("Runtime privileges refused without the explicit verified local sysadmin exception");
    }
    public void RequireApproval(bool execute, bool bootstrap = false)
    {
        if (!execute || !WritesApproved || CreatorScopeAcknowledgement != CreatorAcknowledgement)
            throw new InvalidOperationException("WAITING FOR USER APPROVAL: explicit execution and reviewed write/Creator scope required");
        if (RunId == Guid.Empty || string.IsNullOrWhiteSpace(ExpectedServerName) || SiteId <= 0
            || FloorIds is null || FloorIds.Length != 2 || FloorIds.Any(x => x <= 0) || FloorIds.Distinct().Count() != 2)
            throw new InvalidOperationException("Supply the approved server, Site and exactly two existing test floors");
        var prefix = "wm-core3-" + RunId.ToString("N") + "-";
        if (CreatorA is null || CreatorB is null
            || (bootstrap ? CreatorA.Id != "" || CreatorB.Id != "" : CreatorA.Id == CreatorB.Id
                || string.IsNullOrWhiteSpace(CreatorA.Id) || string.IsNullOrWhiteSpace(CreatorB.Id))
            || CreatorA.UserName != prefix + "a" || CreatorB.UserName != prefix + "b")
            throw new InvalidOperationException("Two explicit, distinct test account IDs/names are required; no account adoption");
    }
    public SqlConnectionStringBuilder Connection(string? value, bool runtime, bool bootstrap = false)
    {
        SqlConnectionStringBuilder c;
        try { c = new(value ?? ""); } catch { throw new InvalidOperationException("Invalid private SQL configuration"); }
        if (c.InitialCatalog != Database || string.IsNullOrWhiteSpace(c.DataSource) || c.AttachDBFilename.Length > 0
            || c.FailoverPartner.Length > 0 || c.PersistSecurityInfo || c.UserInstance || c.ConnectTimeout is < 1 or > 10
            || c.Encrypt.ToString() != "True")
            throw new InvalidOperationException("Only explicit WayMarkDatabase, encryption with certificate validation and bounded timeout are accepted; no fallback or certificate trust override");
        if (c.TrustServerCertificate) {
            // An operator may approve this exception ONLY for the current
            // machine/default instance, integrated Windows login and one run.
            // It never changes application configuration or the system trust store.
            RequireApproval(true, bootstrap);
            if (!LocalDevelopmentCertificateExceptionApproved || !c.IntegratedSecurity
                || !ExpectedServerName.Equals(Environment.MachineName, StringComparison.OrdinalIgnoreCase)
                || !(c.DataSource == "." || c.DataSource.Equals(Environment.MachineName, StringComparison.OrdinalIgnoreCase)
                    || c.DataSource.Equals("localhost", StringComparison.OrdinalIgnoreCase)))
                throw new InvalidOperationException("Certificate trust exception is not approved for this local Windows-authenticated target");
        }
        if (LocalDevelopmentSysadminRuntimeExceptionApproved) {
            RequireApproval(true, bootstrap);
            if (!ExpectedServerName.Equals(Environment.MachineName, StringComparison.OrdinalIgnoreCase)
                || string.IsNullOrWhiteSpace(ExpectedWindowsIdentity)
                || !ExpectedWindowsIdentity.StartsWith(Environment.MachineName + "\\", StringComparison.OrdinalIgnoreCase)
                || !c.IntegratedSecurity || !(c.DataSource == "." || c.DataSource.Equals(Environment.MachineName, StringComparison.OrdinalIgnoreCase)
                    || c.DataSource.Equals("localhost", StringComparison.OrdinalIgnoreCase)))
                throw new InvalidOperationException("Local Development runtime requires approved Windows identity on this machine/default instance");
        }
        // Runtime privileges are checked against SQL SERVER after opening; a username is not proof.
        c.ApplicationName = runtime ? "WayMark.Core3.Runtime" : "WayMark.Core3.Provisioning";
        c.Pooling = false;
        return c;
    }
    public void ValidateImageRoot(string repo)
    {
        if (string.IsNullOrWhiteSpace(ImageRoot) || !Path.IsPathFullyQualified(ImageRoot) || ImageRoot.StartsWith("\\\\"))
            throw new InvalidOperationException("Use a private absolute local image root");
        var root = new DirectoryInfo(Path.GetFullPath(ImageRoot));
        if (root.Name != "images" || root.Parent?.Name != RunId.ToString("N") || root.FullName.StartsWith(Path.GetFullPath(repo) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Use an outside-repository <run UUID>/images root");
        for (var d = root; d is not null; d = d.Parent)
            if (d.LinkTarget is not null || (d.Exists && d.Attributes.HasFlag(FileAttributes.ReparsePoint))
                || Directory.Exists(Path.Combine(d.FullName, ".git")) || File.Exists(Path.Combine(d.FullName, ".git")))
                throw new InvalidOperationException("Git trees and linked storage paths are refused");
        if (root.Exists && root.EnumerateFileSystemInfos().Any())
            throw new InvalidOperationException("First E2E execution requires an unused storage root; existing files are retained");
    }
}
