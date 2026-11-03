using System.Text.Json;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Identity;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using WayMark.Api.Data;
using WayMark.Api.Security;
using WayMark.Api.Services;
using WayMark.Api.Services.MapDrafts;

// No API host, login, migrations, storage provider or seed is started here.
// Reproduce Development configuration + the actual shared DI registration,
// then run only fixed SELECT commands. Never output configuration values.
if ((args.Length != 1 && !(args.Length == 2 && args[1] == "--tls-config"))
    || !Directory.Exists(Path.Combine(args[0], "WayMark.Api")))
    throw new ArgumentException("Supply the WayMark repository root");
var root = Path.GetFullPath(args[0]);
var env = Environment.GetEnvironmentVariable("DOTNET_ENVIRONMENT")
    ?? Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") ?? "Development";
if (env != "Development") throw new InvalidOperationException("Audit only supports Development; no profile fallback");
var builder = WebApplication.CreateBuilder(new WebApplicationOptions {
    ContentRootPath = Path.Combine(root, "WayMark.Api"), EnvironmentName = env,
    ApplicationName = typeof(WayMarkDbContext).Assembly.GetName().Name, Args = [] });
builder.Logging.ClearProviders();
var profile = E2ESafetyProfile.ReadAndApply(builder.Configuration, builder.Environment);
builder.Services.AddWayMarkDatabases(builder.Configuration, profile);
builder.Services.AddIdentityCore<IdentityUser>().AddRoles<IdentityRole>().AddEntityFrameworkStores<AuthDbContext>();
using var services = builder.Services.BuildServiceProvider();
using var scope = services.CreateScope();
var graph = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
var auth = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
var config = (IConfigurationRoot)builder.Configuration;
string? Source(string key) => config.Providers.Reverse().FirstOrDefault(p => p.TryGet(key, out _))?.ToString();
var settings = new Dictionary<string, object?>();
foreach (var key in new[] { "ConnectionStrings:WayMarkDatabase", "ConnectionStrings:WayMarkAuthDatabase",
    "Jwt:SecretKey", "Jwt:Issuer", "Jwt:Audience" })
    settings[key] = new { Provided = !string.IsNullOrWhiteSpace(config[key]), Provider = Source(key) };
var smtp = config.GetSection(EmailTestOptions.SectionName).Get<EmailTestOptions>() ?? new();
var images = config.GetSection(ManagedMapImageOptions.Section).Get<ManagedMapImageOptions>() ?? new();
var graphConnection = new SqlConnectionStringBuilder(graph.Database.GetConnectionString());
var authConnection = new SqlConnectionStringBuilder(auth.Database.GetConnectionString());
if (graphConnection.InitialCatalog != "WayMarkDatabase" || authConnection.InitialCatalog != "WayMarkDatabase")
    throw new InvalidOperationException("Database targets differ from this reviewed audit; no connection opened");
if (graphConnection.DataSource != authConnection.DataSource)
    throw new InvalidOperationException("DbContext servers differ; no connection opened");
if (args.Length == 2) {
    Console.WriteLine(JsonSerializer.Serialize(new {
        Mode = "Offline TLS configuration only; no SQL connection opened",
        Server = graphConnection.DataSource, Database = graphConnection.InitialCatalog,
        Encrypt = graphConnection.Encrypt.ToString(), graphConnection.TrustServerCertificate,
        Client = typeof(SqlConnection).Assembly.GetName().Version?.ToString(),
        ConnectionConfigurationProvider = Source("ConnectionStrings:WayMarkDatabase")
    }, new JsonSerializerOptions { WriteIndented = true }));
    return;
}
Console.WriteLine(JsonSerializer.Serialize(new {
    AuditUtc = DateTimeOffset.UtcNow, Environment = env, Configuration = settings,
    Contexts = new[] { Context(graph), Context(auth) },
    IdentityStore = scope.ServiceProvider.GetRequiredService<IUserStore<IdentityUser>>().GetType().FullName,
    SmtpConfigurationComplete = smtp.HasRequiredSettings, SmtpSent = false,
    ImageStorage = new { images.Enabled, RootProvided = !string.IsNullOrWhiteSpace(images.RootPath), images.MaxStorageBytes, images.MaxObjects },
    Note = "DI resolved without running Program.cs or starting HTTP; SQL commands below are SELECT only"
}, new JsonSerializerOptions { WriteIndented = true }));

// Offline SQL Server provider generation, not EF CLI against any target.
var script = graph.GetService<IMigrator>().GenerateScript("20261018053754_AddNavigationSchema", "20261023063955_AddPublishedMapProjects");
var evidence = Path.Combine(root, "waymark", "build", "core-verification-evidence");
Directory.CreateDirectory(evidence);
File.WriteAllText(Path.Combine(evidence, "PendingMapMigrations.review.sql"), script);
Console.WriteLine("SQL_SERVER_PROVIDER_SCRIPT_GENERATED_OFFLINE (not executed)");
foreach (var name in new[] { "WayMarkDatabase", "WayMarkAuthDatabase" })
{
    var connection = new SqlConnectionStringBuilder(graphConnection.ConnectionString) {
        InitialCatalog = name, ConnectTimeout = 5, ApplicationIntent = ApplicationIntent.ReadOnly,
        ApplicationName = "WayMark.CoreVerification.ReadOnly", Pooling = false };
    using var sql = new SqlConnection(connection.ConnectionString);
    try {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(25));
        await sql.OpenAsync(timeout.Token);
        Console.WriteLine("DATABASE " + name);
        await Select(sql, "SELECT DB_NAME() AS DatabaseName, CONVERT(nvarchar(128), SERVERPROPERTY('ServerName')) AS ServerName, IS_SRVROLEMEMBER('sysadmin') AS IsSysadmin, DATABASEPROPERTYEX(DB_NAME(),'Status') AS Status", timeout.Token);
        var tables = new HashSet<string>();
        using (var cmd = sql.CreateCommand()) {
            cmd.CommandText = "SELECT s.name + '.' + t.name FROM sys.tables t INNER JOIN sys.schemas s ON s.schema_id=t.schema_id ORDER BY s.name,t.name";
            cmd.CommandTimeout = 5;
            using var reader = await cmd.ExecuteReaderAsync(timeout.Token);
            while (await reader.ReadAsync(timeout.Token)) tables.Add(reader.GetString(0));
        }
        Console.WriteLine(JsonSerializer.Serialize(new { Tables = tables }));
        Console.WriteLine("LATEST_FULL_BACKUP_IN_MSDB (no row means history contains no full backup; files not verified)");
        await Select(sql, "SELECT TOP (1) backup_finish_date, is_copy_only, backup_size FROM msdb.dbo.backupset WHERE database_name=DB_NAME() AND type='D' ORDER BY backup_finish_date DESC", timeout.Token);
        if (name == "WayMarkDatabase") {
            Console.WriteLine("EXISTING_HIERARCHY_KEYS");
            await Select(sql, "SELECT t.name AS TableName,c.name AS ColumnName,TYPE_NAME(c.user_type_id) AS SqlType,c.is_nullable,c.is_identity FROM sys.tables t JOIN sys.columns c ON c.object_id=t.object_id WHERE t.name IN ('Sites','Buildings','Floors') AND c.name IN ('Id','SiteId','BuildingId') ORDER BY t.name,c.column_id", timeout.Token);
        }
        foreach (var history in new[] { "__EFMigrationsHistory", "__AuthMigrationsHistory" })
            if (tables.Contains("dbo." + history)) {
                Console.WriteLine("HISTORY " + history);
                await Select(sql, "SELECT MigrationId, ProductVersion FROM [dbo].[" + history + "] ORDER BY MigrationId", timeout.Token);
            }
        // Counts only. No usernames, addresses, hashes, tokens or claims are read.
        foreach (var table in new[] { "AspNetUsers", "AspNetRoles", "AspNetUserRoles", "Sites", "Buildings", "Floors",
            "NavigationNodes", "NavigationEdges", "WayMarks", "SiteMapMemberships", "FloorMapDrafts", "FloorMapImageAssets", "MapProjects", "MapPublications", "MapNodeQrs" })
            if (tables.Contains("dbo." + table)) {
                Console.WriteLine("COUNT " + table);
                await Select(sql, "SELECT COUNT_BIG(*) AS Rows FROM [dbo].[" + table + "]", timeout.Token);
            }
    } catch (SqlException ex) {
        Console.WriteLine(JsonSerializer.Serialize(new { Database = name, SqlErrorNumber = ex.Number, Verified = false }));
        Environment.ExitCode = 2; // Do not output exception text: it can contain connection details.
    } catch (OperationCanceledException) {
        Console.WriteLine("AUDIT_TIMEOUT " + name); Environment.ExitCode = 2;
    }
}
object Context(DbContext db) => new { Context = db.GetType().Name, Provider = db.Database.ProviderName,
    Server = db.Database.GetDbConnection().DataSource, Database = db.Database.GetDbConnection().Database,
    History = db.GetService<IHistoryRepository>().GetCreateScript().Contains("__AuthMigrationsHistory") ? "__AuthMigrationsHistory" : "__EFMigrationsHistory",
    Migrations = db.Database.GetMigrations().ToArray() };
static async Task Select(SqlConnection sql, string query, CancellationToken ct)
{
    if (!query.StartsWith("SELECT ", StringComparison.Ordinal)) throw new InvalidOperationException("SELECT only");
    using var cmd = sql.CreateCommand(); cmd.CommandText = query; cmd.CommandTimeout = 5;
    using var reader = await cmd.ExecuteReaderAsync(ct);
    while (await reader.ReadAsync(ct)) {
        var row = new Dictionary<string, object?>();
        for (var i = 0; i < reader.FieldCount; i++) row[reader.GetName(i)] = reader.IsDBNull(i) ? null : reader.GetValue(i);
        Console.WriteLine(JsonSerializer.Serialize(row));
    }
}
