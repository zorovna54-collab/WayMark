using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration.Json;
using WayMark.Api.Services.MapDrafts;

namespace WayMark.Api.Security;

/// <summary>Explicit opt-in isolation. No connection or filesystem write occurs during parsing.</summary>
public sealed class E2ESafetyProfile
{
    public const string EnvironmentName = "MapDraftE2E";
    public const string DatabaseName = "WayMark_MapDraft_E2E_Test";
    public const string Issuer = "waymark-mapdraft-e2e";
    public const string Audience = "waymark-mapdraft-e2e-web";
    public string ConnectionString { get; }
    public string ExpectedServerName { get; }
    public string Login { get; }
    public string ImageRoot { get; }
    public string AllowedOrigin { get; }
    public ManagedMapImageOptions Images { get; }
    public MapDraftLimitsOptions Limits { get; }

    private E2ESafetyProfile(string connection, string server, string root, string origin,
        ManagedMapImageOptions images, MapDraftLimitsOptions limits)
    {
        ConnectionString = connection; ExpectedServerName = server;
        Login = new SqlConnectionStringBuilder(connection).UserID;
        ImageRoot = root; AllowedOrigin = origin; Images = images; Limits = limits;
    }

    public static E2ESafetyProfile? ReadAndApply(ConfigurationManager configuration, IHostEnvironment environment)
    {
        var enabled = configuration.GetValue<bool>("E2E:Enabled");
        if (!environment.IsEnvironment(EnvironmentName))
        {
            if (enabled || !string.IsNullOrWhiteSpace(configuration["E2E:SqlConnectionString"]))
                throw Refused("E2E settings cannot run in another environment");
            return null;
        }
        if (!enabled) throw Refused("E2E:Enabled must be explicit");
        var connection = Required(configuration, "E2E:SqlConnectionString");
        var server = Required(configuration, "E2E:ExpectedServerName");
        var declaredSource = Required(configuration, "E2E:SqlDataSource");
        var parsed = Parse(connection);
        if (!string.Equals(parsed.DataSource, declaredSource, StringComparison.OrdinalIgnoreCase))
            throw Refused("SQL data source does not match the approved E2E profile");
        ValidateSql(connection);
        RequirePrivateSource(configuration, "E2E:SqlConnectionString", environment.ContentRootPath);
        foreach (var name in configuration.GetSection("ConnectionStrings").GetChildren())
            if (!string.IsNullOrWhiteSpace(name.Value) && !SameConnection(connection, name.Value))
                throw Refused("A conflicting DbContext connection/fallback is configured");
        // EF may supply its own Application Name when omitted. Pin it explicitly so
        // the full connection comparison stays strict before and after EF opens it.
        if (!parsed.ShouldSerialize("Application Name")) parsed.ApplicationName = "WayMark.MapDraftE2E";
        connection = parsed.ConnectionString;

        var key = Required(configuration, "E2E:JwtSecretKey");
        byte[] keyBytes;
        try { keyBytes = Convert.FromBase64String(key); }
        catch (FormatException) { throw Refused("E2E JWT key must be Base64"); }
        if (keyBytes.Length < 32 || key == configuration["Jwt:SecretKey"])
            throw Refused("Supply an independent E2E JWT key of at least 32 bytes");
        RequirePrivateSource(configuration, "E2E:JwtSecretKey", environment.ContentRootPath);
        var rootValue = Required(configuration, "MapImages:RootPath");
        var expectedValue = Required(configuration, "E2E:ImageRoot");
        if (!Path.IsPathFullyQualified(rootValue) || !Path.IsPathFullyQualified(expectedValue))
            throw Refused("Image roots must be absolute");
        var root = Path.GetFullPath(rootValue);
        var expectedRoot = Path.GetFullPath(expectedValue);
        if (!PathsEqual(root, expectedRoot) || !configuration.GetValue<bool>("E2E:StorageIsolationConfirmed"))
            throw Refused("E2E image isolation must be confirmed explicitly");
        // Reuse the provider's root/Git/symlink checks without Prepare or creating a file.
        _ = new ManagedStoragePaths(root, environment.ContentRootPath, Path.Combine(environment.ContentRootPath, "wwwroot"));
        if (!string.Equals(new DirectoryInfo(root).Parent?.Name, DatabaseName, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(Path.GetFileName(root), "images", StringComparison.OrdinalIgnoreCase))
            throw Refused("Use a dedicated <test-database>/images directory");
        var protectedRoots = configuration.GetSection("E2E:ProtectedImageRoots").Get<string[]>() ?? [];
        if (protectedRoots.Length == 0 || protectedRoots.Any(string.IsNullOrWhiteSpace))
            throw Refused("Declare development/production image roots to exclude");
        foreach (var other in protectedRoots)
        {
            if (!Path.IsPathFullyQualified(other) || Overlaps(root, Path.GetFullPath(other)))
                throw Refused("E2E image root overlaps a protected root");
        }
        var images = configuration.GetSection("MapImages").Get<ManagedMapImageOptions>() ?? new();
        var limits = configuration.GetSection("MapDraftLimits").Get<MapDraftLimitsOptions>() ?? new();
        if (!images.Enabled || images.MaxStorageBytes < MapImageRules.MaxBytes || images.MaxStorageBytes > 128L * 1024 * 1024
            || images.MaxObjects is < 1 or > 50 || limits.MaxImagesPerFloor is < 1 or > 8
            || limits.MaxImageBytesPerFloor is < MapImageRules.MaxBytes or > 33554432
            || limits.MaxRevisionsPerFloor is < 1 or > 20)
            throw Refused("E2E storage must use bounded E2E quotas");
        var origin = Required(configuration, "E2E:AllowedOrigin");
        if (!Uri.TryCreate(origin, UriKind.Absolute, out var uri) || !uri.IsLoopback || uri.Scheme != "http"
            || uri.AbsolutePath != "/" || uri.Query.Length != 0 || uri.Fragment.Length != 0 || uri.UserInfo.Length != 0
            || origin != uri.GetLeftPart(UriPartial.Authority))
            throw Refused("E2E CORS origin must be one explicit loopback HTTP origin");

        // Only this process/environment is changed. Never write User Secrets or config files.
        configuration.AddInMemoryCollection(new Dictionary<string, string?> {
            ["Jwt:SecretKey"] = key, ["Jwt:Issuer"] = Issuer, ["Jwt:Audience"] = Audience,
            ["ConnectionStrings:WayMarkDatabase"] = connection });
        return new(connection, server, root, origin, images, limits);
    }

    public void ValidateConnection(string connection, bool beforeOpen = true)
    {
        ValidateSql(connection, beforeOpen);
        if (!SameConnection(ConnectionString, connection, ignorePassword: !beforeOpen)) throw Refused("DbContext target differs from E2E profile");
    }
    public void ValidateIdentity(E2ESqlIdentity identity)
    {
        if (!string.Equals(identity.Database, DatabaseName, StringComparison.Ordinal)
            || !string.Equals(identity.Server, ExpectedServerName, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(identity.Login, Login, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(identity.OriginalLogin, Login, StringComparison.OrdinalIgnoreCase)
            || identity.IsSysadmin != false || identity.ControlServer != false || identity.AlterLogins != false
            || identity.CreateDatabases != false || identity.CanAccessProtectedMap == true || identity.CanAccessProtectedAuth == true)
            throw Refused("Actual SQL database/server/login/privileges are not isolated");
    }
    private static void ValidateSql(string value, bool requirePassword = true)
    {
        var c = Parse(value);
        if (c.InitialCatalog != DatabaseName || string.IsNullOrWhiteSpace(c.DataSource) || c.IntegratedSecurity
            || string.IsNullOrWhiteSpace(c.UserID) || (requirePassword && string.IsNullOrWhiteSpace(c.Password))
            || !string.IsNullOrEmpty(c.AttachDBFilename) || !string.IsNullOrEmpty(c.FailoverPartner)
            || c.UserInstance || c.Authentication is not (SqlAuthenticationMethod.NotSpecified or SqlAuthenticationMethod.SqlPassword)
            || c.Encrypt.ToString() != "True" || c.PersistSecurityInfo || c.ConnectTimeout is < 1 or > 10)
            throw Refused("Require the allowlisted test catalog, SQL login, encryption and short connection timeout");
    }
    private static SqlConnectionStringBuilder Parse(string value)
    {
        try { return new(value); } catch (ArgumentException) { throw Refused("Invalid SQL connection configuration"); }
    }
    private static bool SameConnection(string a, string b, bool ignorePassword = false)
    {
        var first = Parse(a); var second = Parse(b);
        if (ignorePassword) { first.Remove("Password"); second.Remove("Password"); }
        return first.EquivalentTo(second);
    }
    private static string Required(IConfiguration c, string key) =>
        string.IsNullOrWhiteSpace(c[key]) ? throw Refused($"Missing {key}") : c[key]!;
    private static void RequirePrivateSource(IConfigurationRoot c, string key, string contentRoot)
    {
        var provider = c.Providers.Reverse().FirstOrDefault(p => p.TryGet(key, out _));
        if (provider is not JsonConfigurationProvider json) return;
        var file = json.Source.FileProvider?.GetFileInfo(json.Source.Path!);
        if (file?.PhysicalPath is not string path || Overlaps(path, contentRoot))
            throw Refused("E2E credentials cannot be read from application JSON templates");
        for (var parent = new FileInfo(path).Directory; parent is not null; parent = parent.Parent)
            if (Directory.Exists(Path.Combine(parent.FullName, ".git")) || File.Exists(Path.Combine(parent.FullName, ".git")))
                throw Refused("E2E credentials cannot come from a Git checkout");
    }
    private static bool PathsEqual(string a, string b) => string.Equals(Path.TrimEndingDirectorySeparator(a),
        Path.TrimEndingDirectorySeparator(b), OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal);
    private static bool Overlaps(string a, string b) => Inside(a, b) || Inside(b, a);
    private static bool Inside(string path, string parent)
    {
        var relative = Path.GetRelativePath(parent, path);
        return relative == "." || (!Path.IsPathRooted(relative) && relative != ".." && !relative.StartsWith(".." + Path.DirectorySeparatorChar));
    }
    public static InvalidOperationException Refused(string reason) => new($"E2E refused: {reason}. No migration/seed is authorized.");
}

public sealed record E2ESqlIdentity(string Database, string Server, string Login, string OriginalLogin,
    bool? IsSysadmin, bool? ControlServer, bool? AlterLogins, bool? CreateDatabases,
    bool? CanAccessProtectedMap, bool? CanAccessProtectedAuth);
