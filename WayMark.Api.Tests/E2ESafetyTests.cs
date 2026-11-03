using System.Data;
using System.Data.Common;
using System.Diagnostics.CodeAnalysis;
using System.Security.Cryptography;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;
using WayMark.Api.Data;
using WayMark.Api.Security;
using WayMark.Api.Services;
using WayMark.Api.Services.MapDrafts;
using Xunit;

namespace WayMark.Api.Tests;

public sealed class E2ESafetyTests
{
    [Theory]
    [InlineData("Jwt:SecretKey", "")]
    [InlineData("Jwt:SecretKey", "not-base64")]
    [InlineData("Jwt:SecretKey", "AQID")]
    [InlineData("Jwt:Issuer", "")]
    [InlineData("Jwt:Audience", " ")]
    public void MissingOrInvalidJwtConfigurationIsRejectedWithoutExposingTheValue(string key, string value)
    {
        var config = new ConfigurationManager();
        config.AddInMemoryCollection(new Dictionary<string, string?> {
            ["Jwt:SecretKey"] = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)),
            ["Jwt:Issuer"] = "test-issuer", ["Jwt:Audience"] = "test-audience" });
        config[key] = value;
        Assert.Throws<InvalidOperationException>(() => new ServiceCollection().AddWayMarkSecurity(config));
    }

    [Theory]
    [InlineData("E2E:Enabled", "false")]
    [InlineData("E2E:SqlConnectionString", "")]
    [InlineData("E2E:SqlConnectionString", "not a connection")]
    [InlineData("E2E:ExpectedServerName", "")]
    [InlineData("E2E:SqlDataSource", "wrong-server")]
    [InlineData("E2E:JwtSecretKey", "")]
    [InlineData("E2E:JwtSecretKey", "not-base64")]
    [InlineData("E2E:StorageIsolationConfirmed", "false")]
    [InlineData("E2E:ProtectedImageRoots:0", "")]
    [InlineData("MapImages:Enabled", "false")]
    [InlineData("MapImages:RootPath", "relative/images")]
    [InlineData("MapImages:MaxStorageBytes", "1073741824")]
    [InlineData("MapImages:MaxObjects", "5000")]
    [InlineData("MapDraftLimits:MaxRevisionsPerFloor", "500")]
    [InlineData("E2E:AllowedOrigin", "https://example.invalid")]
    [InlineData("E2E:AllowedOrigin", "http://localhost:5628/path")]
    public void MissingOrInvalidProfileFailsBeforeAnyConnectionOrFilesystemWrite(string key, string value)
    {
        using var fixture = new Fixture();
        var config = fixture.Config(); config[key] = value;
        Assert.ThrowsAny<Exception>(() => E2ESafetyProfile.ReadAndApply(config, fixture.Environment));
        Assert.False(Directory.Exists(fixture.Images));
    }

    [Theory]
    [InlineData("WayMarkDatabase")]
    [InlineData("WayMarkAuthDatabase")]
    [InlineData("master")]
    [InlineData("")]
    [InlineData("WayMark_MapDraft_E2E_Test_typo")]
    public void ProtectedAndUnapprovedCatalogsCannotRun(string database)
    {
        using var f = new Fixture(); var c = f.Config();
        var sql = new SqlConnectionStringBuilder(c["E2E:SqlConnectionString"]) { InitialCatalog = database };
        c["E2E:SqlConnectionString"] = sql.ConnectionString;
        Assert.Throws<InvalidOperationException>(() => E2ESafetyProfile.ReadAndApply(c, f.Environment));
    }

    [Theory]
    [InlineData("Integrated Security", "true")]
    [InlineData("Password", "")]
    [InlineData("User ID", "")]
    [InlineData("Encrypt", "false")]
    [InlineData("Persist Security Info", "true")]
    [InlineData("Connect Timeout", "0")]
    [InlineData("Failover Partner", "other-server")]
    [InlineData("AttachDbFilename", "other.mdf")]
    public void UnsafeSqlConnectionOptionsAreRefused(string key, string value)
    {
        using var f = new Fixture(); var c = f.Config();
        var sql = new SqlConnectionStringBuilder(c["E2E:SqlConnectionString"]); sql[key] = value;
        c["E2E:SqlConnectionString"] = sql.ConnectionString;
        Assert.Throws<InvalidOperationException>(() => E2ESafetyProfile.ReadAndApply(c, f.Environment));
    }

    [Theory]
    [InlineData("WayMarkDatabase")]
    [InlineData("WayMarkAuthDatabase")]
    [InlineData("AuthDatabase")]
    public void AnyLegacyOrIdentityConnectionFallbackIsRefused(string key)
    {
        using var f = new Fixture(); var c = f.Config();
        c[$"ConnectionStrings:{key}"] = "Server=.;Database=WayMarkDatabase;Integrated Security=True";
        Assert.Throws<InvalidOperationException>(() => E2ESafetyProfile.ReadAndApply(c, f.Environment));
    }

    [Fact]
    public void OrdinaryDevelopmentRemainsUnchangedButE2ECannotUseAnotherEnvironment()
    {
        using var f = new Fixture();
        var development = new TestEnvironment { ContentRootPath = f.Owner, EnvironmentName = "Development" };
        var empty = new ConfigurationManager();
        empty["ConnectionStrings:WayMarkDatabase"] = "Server=.;Database=WayMarkDatabase;Integrated Security=True";
        Assert.Null(E2ESafetyProfile.ReadAndApply(empty, development));
        Assert.Contains("WayMarkDatabase", empty.GetConnectionString("WayMarkDatabase"));
        Assert.Throws<InvalidOperationException>(() => E2ESafetyProfile.ReadAndApply(f.Config(), development));
        Assert.Throws<InvalidOperationException>(() => E2ESafetyProfile.ReadAndApply(new ConfigurationManager(), f.Environment));
    }

    [Fact]
    public void E2EKeyCannotReuseGenericKeyOrComeFromTrackedJsonTemplate()
    {
        using var f = new Fixture(); var c = f.Config();
        c["Jwt:SecretKey"] = c["E2E:JwtSecretKey"];
        Assert.Throws<InvalidOperationException>(() => E2ESafetyProfile.ReadAndApply(c, f.Environment));
        var app = Path.Combine(f.Owner, "app"); Directory.CreateDirectory(app);
        var template = Path.Combine(app, "template.json");
        File.WriteAllText(template, System.Text.Json.JsonSerializer.Serialize(new { E2E = new { JwtSecretKey = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)) } }));
        c = f.Config(); c.AddJsonFile(template);
        Assert.Throws<InvalidOperationException>(() => E2ESafetyProfile.ReadAndApply(c, new TestEnvironment { ContentRootPath = app }));
    }

    [Fact]
    public void ActualServerCatalogLoginAndPrivilegeChecksFailClosed()
    {
        using var f = new Fixture(); var profile = f.Profile();
        profile.ValidateIdentity(f.Identity());
        foreach (var identity in new[] {
            f.Identity() with { Database = "WayMarkDatabase" }, f.Identity() with { Database = "WayMarkAuthDatabase" },
            f.Identity() with { Server = "wrong-server" }, f.Identity() with { Login = "sa" },
            f.Identity() with { OriginalLogin = "operator" }, f.Identity() with { IsSysadmin = true },
            f.Identity() with { IsSysadmin = null }, f.Identity() with { ControlServer = true },
            f.Identity() with { AlterLogins = true }, f.Identity() with { CreateDatabases = true },
            f.Identity() with { CanAccessProtectedMap = true }, f.Identity() with { CanAccessProtectedAuth = true } })
            Assert.Throws<InvalidOperationException>(() => profile.ValidateIdentity(identity));
    }

    [Fact]
    public async Task OpenConnectionIsActuallyReadAndRejectedBeforeBusinessCommands()
    {
        using var f = new Fixture(); var profile = f.Profile(); var interceptor = new E2EConnectionInterceptor(profile);
        using var connection = new MetadataConnection(profile.ConnectionString, f.Identity());
        connection.Open();
        await interceptor.VerifyOpenAsync(connection, default);
        Assert.Equal(E2EConnectionInterceptor.IdentityQuery, connection.LastCommand);
        Assert.Equal(ConnectionState.Open, connection.State);
        connection.Identity = f.Identity() with { Database = "WayMarkDatabase" };
        await Assert.ThrowsAsync<InvalidOperationException>(() => interceptor.VerifyOpenAsync(connection, default));
        Assert.Equal(ConnectionState.Closed, connection.State);
        Assert.Equal(2, connection.Commands); // metadata SELECTs only; no business operation
        Assert.DoesNotContain("INSERT", connection.LastCommand!, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("UPDATE", connection.LastCommand!, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task ConnectionCanReopenWithPasswordHiddenButCannotChangeCatalog()
    {
        using var f = new Fixture(); var p = f.Profile(); var guard = new E2EConnectionInterceptor(p);
        using var c = new MetadataConnection(p.ConnectionString, f.Identity()); c.Open();
        await guard.VerifyOpenAsync(c, default); c.Close();
        var sql = new SqlConnectionStringBuilder(p.ConnectionString); sql.Remove("Password"); c.ConnectionString = sql.ConnectionString;
        await guard.ConnectionOpeningAsync(c, null!, default); c.Open();
        await guard.VerifyOpenAsync(c, default); c.Close();
        sql.InitialCatalog = "WayMarkAuthDatabase"; c.ConnectionString = sql.ConnectionString;
        await Assert.ThrowsAsync<InvalidOperationException>(async () => await guard.ConnectionOpeningAsync(c, null!, default));
        Assert.Equal(2, c.Commands);
    }

    [Fact]
    public void BothContextsHaveSameGuardedTargetAndSeparateHistories()
    {
        using var f = new Fixture(); var c = f.Config(); var p = E2ESafetyProfile.ReadAndApply(c, f.Environment)!;
        var services = new ServiceCollection(); services.AddLogging(); services.AddWayMarkDatabases(c, p);
        using var provider = services.BuildServiceProvider(); using var scope = provider.CreateScope();
        foreach (var type in new[] { typeof(WayMarkDbContext), typeof(AuthDbContext) })
        {
            var db = (DbContext)scope.ServiceProvider.GetRequiredService(type);
            var expected = new SqlConnectionStringBuilder(p.ConnectionString);
            var actual = new SqlConnectionStringBuilder(db.Database.GetConnectionString());
            var differentKeys = expected.Keys.Cast<string>().Where(key => !Equals(expected[key], actual[key])).ToArray();
            Assert.True(differentKeys.Length == 0, "Connection option differences: " + string.Join(", ", differentKeys));
        }
        var contexts = E2EStartupCheck.ValidateContexts(scope.ServiceProvider, [typeof(WayMarkDbContext), typeof(AuthDbContext)], p);
        Assert.All(contexts, db => Assert.Equal(p.ConnectionString, db.Database.GetConnectionString()));
        Assert.Contains("__EFMigrationsHistory", contexts[0].GetService<IHistoryRepository>().GetCreateScript());
        Assert.Contains("__AuthMigrationsHistory", contexts[1].GetService<IHistoryRepository>().GetCreateScript());
        Assert.False(contexts[0].Database.HasPendingModelChanges());
        var migrations = contexts[0].Database.GetMigrations().ToArray();
        Assert.Contains("20261023063955_AddPublishedMapProjects", migrations);
        Assert.Contains("20261025010000_AddNavigationHistory", migrations);
        Assert.Equal("20261026001522_ExtendNavigationHistoryLifecycle", migrations.Last());
    }

    [Fact]
    public void AdditionalUnguardedOrWrongIdentityContextStopsStartup()
    {
        using var f = new Fixture(); var c = f.Config(); var p = E2ESafetyProfile.ReadAndApply(c, f.Environment)!;
        var services = new ServiceCollection(); services.AddLogging(); services.AddWayMarkDatabases(c, p);
        services.AddDbContext<UnexpectedContext>(o => o.UseSqlServer("Server=.;Database=WayMarkAuthDatabase;Integrated Security=True"));
        using var provider = services.BuildServiceProvider(); using var scope = provider.CreateScope();
        Assert.Throws<InvalidOperationException>(() => E2EStartupCheck.ValidateContexts(scope.ServiceProvider,
            [typeof(WayMarkDbContext), typeof(AuthDbContext), typeof(UnexpectedContext)], p));
    }

    [Fact]
    public void SameTargetWithoutInterceptorIsStillRefused()
    {
        using var f = new Fixture(); var c = f.Config(); var p = E2ESafetyProfile.ReadAndApply(c, f.Environment)!;
        var services = new ServiceCollection(); services.AddLogging(); services.AddWayMarkDatabases(c, p);
        services.AddDbContext<UnexpectedContext>(o => o.UseSqlServer(p.ConnectionString));
        using var provider = services.BuildServiceProvider(); using var scope = provider.CreateScope();
        var error = Assert.Throws<InvalidOperationException>(() => E2EStartupCheck.ValidateContexts(scope.ServiceProvider,
            [typeof(WayMarkDbContext), typeof(AuthDbContext), typeof(UnexpectedContext)], p));
        Assert.Contains("unguarded DbContext", error.Message);
    }

    [Fact]
    public async Task ProtectedCatalogIsRejectedBeforeOpeningOrRunningMetadata()
    {
        using var f = new Fixture(); var p = f.Profile(); var guard = new E2EConnectionInterceptor(p);
        var sql = new SqlConnectionStringBuilder(p.ConnectionString) { InitialCatalog = "WayMarkDatabase" };
        using var connection = new MetadataConnection(sql.ConnectionString, f.Identity());
        Assert.Throws<InvalidOperationException>(() => guard.ConnectionOpening(connection, null!, default));
        await Assert.ThrowsAsync<InvalidOperationException>(async () => await guard.ConnectionOpeningAsync(connection, null!, default));
        Assert.Equal(ConnectionState.Closed, connection.State);
        Assert.Equal(0, connection.Commands);
    }

    [Fact]
    public void E2ETemplateMasksSharedDatabaseButCannotStartWithoutPrivateConfiguration()
    {
        // Locate source through the working directory, independent of test output/artifacts layout.
        var directory = new DirectoryInfo(Directory.GetCurrentDirectory());
        while (directory is not null && !File.Exists(Path.Combine(directory.FullName, "WayMark.Api", "WayMark.Api.csproj"))) directory = directory.Parent;
        Assert.NotNull(directory);
        var project = Path.Combine(directory!.FullName, "WayMark.Api");
        var c = new ConfigurationManager();
        c.AddJsonFile(Path.Combine(project, "appsettings.json"));
        c.AddJsonFile(Path.Combine(project, "appsettings.MapDraftE2E.json"));
        Assert.True(string.IsNullOrEmpty(c.GetConnectionString("WayMarkDatabase")));
        Assert.True(string.IsNullOrEmpty(c.GetConnectionString("WayMarkAuthDatabase")));
        using var f = new Fixture();
        Assert.Throws<InvalidOperationException>(() => E2ESafetyProfile.ReadAndApply(c, f.Environment));
        Assert.False(Directory.Exists(f.Images));
    }

    [Fact]
    public void StorageReadinessUsesExistingTemporaryDirectoryWithoutProbeFiles()
    {
        using var f = new Fixture(); var p = f.Profile();
        Assert.Throws<InvalidOperationException>(() => E2EStorageAccess.Verify(p, f.Environment.ContentRootPath));
        Assert.False(Directory.Exists(f.Images));
        Directory.CreateDirectory(f.Images);
        E2EStorageAccess.Verify(p, f.Environment.ContentRootPath);
        Assert.Empty(Directory.GetFileSystemEntries(f.Images));
    }

    [Fact]
    public void ProtectedRootsAndPinnedOptionsPreventStorageCrossEnvironment()
    {
        using var f = new Fixture(); var c = f.Config(); c["E2E:ProtectedImageRoots:0"] = f.Images;
        Assert.Throws<InvalidOperationException>(() => E2ESafetyProfile.ReadAndApply(c, f.Environment));
        c = f.Config(); var p = E2ESafetyProfile.ReadAndApply(c, f.Environment)!;
        var services = new ServiceCollection(); services.AddMapDraftFoundation(c); services.AddWayMarkDatabases(c, p);
        c["MapImages:RootPath"] = Path.Combine(f.Owner, "development");
        using var provider = services.BuildServiceProvider();
        Assert.Equal(f.Images, provider.GetRequiredService<IOptions<ManagedMapImageOptions>>().Value.RootPath);
        Assert.Equal(20, provider.GetRequiredService<IOptions<MapDraftLimitsOptions>>().Value.MaxRevisionsPerFloor);
    }

    [Fact]
    public async Task E2EEmailIsDisabledAndCannotSendResetTokens()
    {
        var email = new E2EDisabledEmail();
        await Assert.ThrowsAsync<SmtpEmailException>(() => email.SendTestEmailAsync(DateTimeOffset.UtcNow, default));
        await Assert.ThrowsAsync<SmtpEmailException>(() => email.SendPasswordResetEmailAsync("test@example.invalid", "test", "unused", "https://example.invalid", default));
    }

    public sealed class UnexpectedContext(DbContextOptions<UnexpectedContext> options) : DbContext(options);

    private sealed class Fixture : IDisposable
    {
        public string Owner { get; } = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "WayMarkGuardTests", Guid.NewGuid().ToString("N")));
        public string Images => Path.Combine(Owner, E2ESafetyProfile.DatabaseName, "images");
        public TestEnvironment Environment => new() { ContentRootPath = Path.Combine(Owner, "application") };
        public ConfigurationManager Config()
        {
            var sql = new SqlConnectionStringBuilder { DataSource = "unit-sql", InitialCatalog = E2ESafetyProfile.DatabaseName,
                UserID = "e2e-fixture", Password = Convert.ToBase64String(RandomNumberGenerator.GetBytes(24)),
                Encrypt = true, TrustServerCertificate = true, ConnectTimeout = 3 };
            var c = new ConfigurationManager();
            c.AddInMemoryCollection(new Dictionary<string, string?> {
                ["E2E:Enabled"] = "true", ["E2E:SqlConnectionString"] = sql.ConnectionString,
                ["E2E:SqlDataSource"] = "unit-sql", ["E2E:ExpectedServerName"] = "UNIT-SQL",
                ["E2E:JwtSecretKey"] = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)),
                ["E2E:ImageRoot"] = Images, ["E2E:StorageIsolationConfirmed"] = "true",
                ["E2E:ProtectedImageRoots:0"] = Path.Combine(Owner, "development"),
                ["E2E:AllowedOrigin"] = "http://localhost:5628",
                ["MapImages:Enabled"] = "true", ["MapImages:RootPath"] = Images,
                ["MapImages:MaxStorageBytes"] = "134217728", ["MapImages:MaxObjects"] = "50",
                ["MapDraftLimits:MaxRevisionsPerFloor"] = "20", ["MapDraftLimits:MaxImagesPerFloor"] = "8",
                ["MapDraftLimits:MaxImageBytesPerFloor"] = "33554432" });
            return c;
        }
        public E2ESafetyProfile Profile() => E2ESafetyProfile.ReadAndApply(Config(), Environment)!;
        public E2ESqlIdentity Identity() => new(E2ESafetyProfile.DatabaseName, "UNIT-SQL", "e2e-fixture", "e2e-fixture", false, false, false, false, false, false);
        public void Dispose()
        {
            var parent = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "WayMarkGuardTests"));
            var relative = Path.GetRelativePath(parent, Owner);
            if (relative.Length != 32 || relative.Contains(Path.DirectorySeparatorChar) || !Guid.TryParseExact(relative, "N", out _))
                throw new InvalidOperationException("Unsafe test cleanup refused");
            if (Directory.Exists(Owner)) Directory.Delete(Owner, true);
        }
    }
    private sealed class TestEnvironment : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = E2ESafetyProfile.EnvironmentName;
        public string ApplicationName { get; set; } = "WayMark.Api";
        public string ContentRootPath { get; set; } = "";
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }

    private sealed class MetadataConnection(string connection, E2ESqlIdentity identity) : DbConnection
    {
        [AllowNull] public override string ConnectionString { get; set; } = connection;
        public E2ESqlIdentity Identity { get; set; } = identity;
        public string? LastCommand { get; set; }
        public int Commands { get; set; }
        private ConnectionState state;
        public override string Database => Identity.Database;
        public override string DataSource => Identity.Server;
        public override string ServerVersion => "16.0";
        public override ConnectionState State => state;
        public override void Open() => state = ConnectionState.Open;
        public override void Close() => state = ConnectionState.Closed;
        public override void ChangeDatabase(string databaseName) => throw new NotSupportedException();
        protected override DbTransaction BeginDbTransaction(IsolationLevel isolationLevel) => throw new NotSupportedException();
        protected override DbCommand CreateDbCommand() => new MetadataCommand(this);
    }
    private sealed class MetadataCommand(MetadataConnection connection) : DbCommand
    {
        [AllowNull] public override string CommandText { get; set; } = "";
        public override int CommandTimeout { get; set; }
        public override CommandType CommandType { get; set; }
        public override bool DesignTimeVisible { get; set; }
        public override UpdateRowSource UpdatedRowSource { get; set; }
        protected override DbConnection? DbConnection { get; set; } = connection;
        protected override DbTransaction? DbTransaction { get; set; }
        protected override DbParameterCollection DbParameterCollection => throw new NotSupportedException();
        public override void Cancel() { }
        public override int ExecuteNonQuery() => throw new InvalidOperationException("Writes are forbidden in this fake");
        public override object ExecuteScalar() => throw new NotSupportedException();
        public override void Prepare() { }
        protected override DbParameter CreateDbParameter() => throw new NotSupportedException();
        protected override DbDataReader ExecuteDbDataReader(CommandBehavior behavior)
        {
            Assert.Equal(E2EConnectionInterceptor.IdentityQuery, CommandText);
            connection.LastCommand = CommandText; connection.Commands++;
            var row = connection.Identity; var table = new DataTable();
            for (var i = 0; i < 10; i++) table.Columns.Add($"column{i}", i < 4 ? typeof(string) : typeof(int));
            object Flag(bool? b) => b.HasValue ? (b.Value ? 1 : 0) : DBNull.Value;
            table.Rows.Add(row.Database, row.Server, row.Login, row.OriginalLogin, Flag(row.IsSysadmin), Flag(row.ControlServer),
                Flag(row.AlterLogins), Flag(row.CreateDatabases), Flag(row.CanAccessProtectedMap), Flag(row.CanAccessProtectedAuth));
            return table.CreateDataReader();
        }
    }
}
