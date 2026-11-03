using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Identity;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Configuration;
using WayMark.Api.Data;
using WayMark.CoreSqlReadiness;

try { await Run(args); }
catch (SqlException ex) { Console.Error.WriteLine($"Stopped: SQL error {ex.Number}; credentials and SQL details withheld. No automatic retry/cleanup."); Environment.ExitCode = 1; }
catch (Exception ex) {
    Console.Error.WriteLine(ex is InvalidOperationException && ex.Message.StartsWith("WAITING FOR USER APPROVAL", StringComparison.Ordinal)
        ? "WAITING FOR USER APPROVAL: explicit execution and reviewed write/Creator scope required"
        : "Stopped: setup/E2E failed; check reviewed target, approval and configuration. No exception bodies, credentials, automatic retry or cleanup.");
    Environment.ExitCode = 1;
}

static async Task Run(string[] args)
{
    if (args.Length < 2) throw new InvalidOperationException("Usage: preview <repo> OR bootstrap|grant|e2e <repo> <private-plan.json> --execute-approved");
    var root = Path.GetFullPath(args[1]);
    if (!File.Exists(Path.Combine(root, "WayMark.Api", "Program.cs"))) throw new InvalidOperationException("Invalid repository root");
    var json = new JsonSerializerOptions(JsonSerializerDefaults.Web) { WriteIndented = true };
    if (args[0] == "preview") {
        var output = Path.Combine(root, "docs", "database", "core-sprint3"); Directory.CreateDirectory(output);
        foreach (var idem in new[] { false, true }) File.WriteAllText(Path.Combine(output, idem ? "PendingMapMigrations.idempotent.review.sql" : "PendingMapMigrations.review.sql"), MigrationPreview.Generate(idem));
        File.WriteAllText(Path.Combine(output, "approval-plan.sample.json"), JsonSerializer.Serialize(new ReadinessPlan(Guid.Empty, "", 0, [0, 0], new("", ""), new("", ""), ""), json) + "\n");
        var artifacts = new[] { "PendingMapMigrations.review.sql", "PendingMapMigrations.idempotent.review.sql" };
        File.WriteAllText(Path.Combine(output, "review-manifest.json"), JsonSerializer.Serialize(new {
            database = ReadinessPlan.Database, context = nameof(WayMarkDbContext), history = "__EFMigrationsHistory",
            from = MigrationPreview.From, to = MigrationPreview.To,
            sha256 = artifacts.ToDictionary(x => x, x => Convert.ToHexStringLower(SHA256.HashData(File.ReadAllBytes(Path.Combine(output, x)))))
        }, json) + "\n");
        Console.WriteLine("Generated review artifacts only; no SQL connection, user grant or runtime storage directory created."); return;
    }
    if (args.Length != 4 || args[0] is not ("bootstrap" or "grant" or "e2e")) throw new InvalidOperationException("Unknown command or incomplete approval");
    var plan = JsonSerializer.Deserialize<ReadinessPlan>(File.ReadAllText(args[2]), json) ?? throw new InvalidOperationException("Missing private approval plan");
    var bootstrap = args[0] == "bootstrap";
    plan.RequireApproval(args[3] == "--execute-approved", bootstrap); // Before opening SQL or starting an API.
    VerifyMigrationArtifacts(root);
    if (bootstrap && !string.Equals(Path.GetDirectoryName(Path.GetFullPath(args[2])), Path.GetDirectoryName(Path.GetFullPath(plan.ImageRoot)), StringComparison.OrdinalIgnoreCase))
        throw new InvalidOperationException("Bootstrap plan must be inside the approved private run directory beside images");
    plan.ValidateImageRoot(root);
    var connection = plan.Connection(Environment.GetEnvironmentVariable(args[0] != "e2e" ? "WAYMARK_CORE3_SETUP_SQL" : "WAYMARK_CORE3_RUNTIME_SQL"), args[0] == "e2e", bootstrap);
    using var sql = new SqlConnection(connection.ConnectionString);
    await sql.OpenAsync(); await VerifySql(sql, plan, args[0] == "e2e", bootstrap);
    if (args[0] != "e2e") {
        var services = new ServiceCollection().AddLogging();
        services.AddDbContext<AuthDbContext>(o => o.UseSqlServer(sql, s => s.MigrationsHistoryTable("__AuthMigrationsHistory")));
        services.AddDbContext<WayMarkDbContext>(o => o.UseSqlServer(sql, s => s.MigrationsHistoryTable("__EFMigrationsHistory")));
        services.AddIdentityCore<IdentityUser>().AddRoles<IdentityRole>().AddEntityFrameworkStores<AuthDbContext>();
        using var provider = services.BuildServiceProvider(); using var scope = provider.CreateScope();
        if (bootstrap) {
            var completed = await TestCreatorBootstrap.CreateAsync(plan, true, scope.ServiceProvider.GetRequiredService<UserManager<IdentityUser>>(),
                scope.ServiceProvider.GetRequiredService<AuthDbContext>(), scope.ServiceProvider.GetRequiredService<WayMarkDbContext>(),
                Password("WAYMARK_CORE3_A_PASSWORD"), Password("WAYMARK_CORE3_B_PASSWORD"));
            var stagedPlan = Path.GetFullPath(args[2]) + ".completed.new";
            using (var output = new FileStream(stagedPlan, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                await JsonSerializer.SerializeAsync(output, completed, json);
            File.Move(stagedPlan, args[2], overwrite: true);
            Console.WriteLine("Approved new test accounts created; IDs saved only in private plan. No roles granted yet. No credentials printed."); return;
        }
        await TestCreatorAccess.GrantAsync(plan, true, scope.ServiceProvider.GetRequiredService<UserManager<IdentityUser>>(),
            scope.ServiceProvider.GetRequiredService<RoleManager<IdentityRole>>(), scope.ServiceProvider.GetRequiredService<AuthDbContext>(), scope.ServiceProvider.GetRequiredService<WayMarkDbContext>());
        Console.WriteLine("Approved A/B granted Creator + active Site membership; only A receives Site publication. No Admin grant or account/password change."); return;
    }
    plan.ValidateImageRoot(root);
    foreach (var floor in plan.FloorIds) {
        using var cmd = sql.CreateCommand(); cmd.CommandText = "SELECT COUNT(*) FROM dbo.FloorMapDrafts WHERE FloorId=@id"; cmd.Parameters.AddWithValue("@id", floor);
        if (Convert.ToInt32(await cmd.ExecuteScalarAsync()) != 0) throw new InvalidOperationException("Test floor already has a draft. Stop and review; no overwrite/cleanup/resume is automatic");
    }
    var before = await Fingerprint(sql);
    var evidenceDir = Path.Combine(root, "waymark", "build", "core-sql-evidence", plan.RunId.ToString("N")); Directory.CreateDirectory(evidenceDir);
    void Evidence(string line) { File.AppendAllText(Path.Combine(evidenceDir, "steps.log"), line + "\n"); Console.WriteLine(line); }
    var passwordA = Password("WAYMARK_CORE3_A_PASSWORD"); var passwordB = Password("WAYMARK_CORE3_B_PASSWORD");
    var listener = new TcpListener(IPAddress.Loopback, 0); listener.Start(); var port = ((IPEndPoint)listener.LocalEndpoint).Port; listener.Stop();
    using var a = Client(port); using var b = Client(port); using var guest = Client(port);
    Process? api = null;
    try {
        api = await StartApi(root, connection.ConnectionString, plan.ImageRoot, port);
        await SqlE2eWorkflow.Login(a, plan.CreatorA, passwordA); await SqlE2eWorkflow.Login(b, plan.CreatorB, passwordB);
        var result = await SqlE2eWorkflow.Create(a, b, guest, plan, Evidence);
        // Evidence contains resource IDs/checksums/public QR only, no bearer tokens.
        File.WriteAllText(Path.Combine(evidenceDir, "resources.json"), JsonSerializer.Serialize(result, json));
        Stop(api); api = null;
        api = await StartApi(root, connection.ConnectionString, plan.ImageRoot, port);
        await SqlE2eWorkflow.Verify(guest, result); Evidence("PASS: process restart, SQL snapshot and both image checksums");
        await SqlE2eWorkflow.Login(a, plan.CreatorA, passwordA);
        await SqlE2eWorkflow.VerifyPrivateAfterRestart(a, result); Evidence("PASS: private project and floor revisions survive restart");
        await SqlE2eWorkflow.Revoke(a, guest, result); Evidence("PASS: QR revoke -> 410");
        if (before != await Fingerprint(sql)) throw new InvalidOperationException("Legacy graph or Identity changed. Stop and investigate; no automatic rollback/delete");
        Evidence("PASS: legacy graph and Identity SHA256 unchanged; test objects retained for review; no SQL cleanup performed");
    } finally {
        if (api is not null) Stop(api);
        // Even after a failure, preserve evidence and verify old graph. No destructive cleanup.
        Evidence(before == await Fingerprint(sql) ? "FINAL: legacy graph and Identity SHA256 unchanged" : "FINAL: legacy graph or Identity differs; investigate before further writes");
    }
}
static string Password(string key) => Environment.GetEnvironmentVariable(key) is { Length: >= 8 } p ? p : throw new InvalidOperationException("Supply private test password environment variables; none are stored in the plan");
static HttpClient Client(int port) => new(new HttpClientHandler { AllowAutoRedirect = false }) { BaseAddress = new Uri($"http://127.0.0.1:{port}/"), Timeout = TimeSpan.FromSeconds(30) };
static void VerifyMigrationArtifacts(string root)
{
    var dir = Path.Combine(root, "docs", "database", "core-sprint3");
    using var manifest = JsonDocument.Parse(File.ReadAllText(Path.Combine(dir, "review-manifest.json")));
    if (manifest.RootElement.GetProperty("database").GetString() != ReadinessPlan.Database
        || manifest.RootElement.GetProperty("from").GetString() != MigrationPreview.From
        || manifest.RootElement.GetProperty("to").GetString() != MigrationPreview.To)
        throw new InvalidOperationException("Reviewed migration artifact target mismatch");
    foreach (var name in new[] { "PendingMapMigrations.review.sql", "PendingMapMigrations.idempotent.review.sql" })
        if (Convert.ToHexStringLower(SHA256.HashData(File.ReadAllBytes(Path.Combine(dir, name)))) != manifest.RootElement.GetProperty("sha256").GetProperty(name).GetString())
            throw new InvalidOperationException("Reviewed migration artifact checksum mismatch");
}
static async Task VerifySql(SqlConnection sql, ReadinessPlan p, bool runtime, bool bootstrap = false)
{
    using var cmd = sql.CreateCommand(); cmd.CommandTimeout = 5;
    cmd.CommandText = ReadinessPlan.SessionVerificationSql;
    using (var r = await cmd.ExecuteReaderAsync()) {
        await r.ReadAsync();
        p.ValidateActualTarget(r.GetString(0), r.GetString(1), r.GetInt32(2), r.GetInt32(3),
            Enumerable.Range(4, 15).Select(i => r.IsDBNull(i) ? (int?)null : Convert.ToInt32(r.GetValue(i))).ToArray(), runtime,
            r.GetString(19), r.IsDBNull(20) ? null : r.GetString(20), r.IsDBNull(21) ? null : r.GetString(21),
            r.IsDBNull(22) ? null : r.GetString(22) == "TRUE", bootstrap);
        Console.WriteLine(JsonSerializer.Serialize(new {
            VerifiedDatabase = r.GetString(0), VerifiedServer = r.GetString(1), WindowsIdentity = r.GetString(19),
            AuthScheme = r.IsDBNull(20) ? null : r.GetString(20), Transport = r.IsDBNull(21) ? null : r.GetString(21),
            EncryptionReported = r.IsDBNull(22) ? null : r.GetString(22),
            LocalDevelopmentSysadminException = p.LocalDevelopmentSysadminRuntimeExceptionApproved
        })); // Safe session metadata only; no connection string, credential or user content.
    }
    if (runtime && !p.LocalDevelopmentSysadminRuntimeExceptionApproved) {
        // db_datawriter is insufficient isolation on the shared database. The
        // approved test runtime must not mutate old graph, roles or membership.
        cmd.CommandText = """
SELECT COUNT(*) FROM (VALUES(N'dbo.Sites'),(N'dbo.Buildings'),(N'dbo.Floors'),(N'dbo.NavigationNodes'),
 (N'dbo.NavigationEdges'),(N'dbo.WayMarks'),(N'dbo.AspNetRoles'),(N'dbo.AspNetUserRoles'),(N'dbo.SiteMapMemberships')) o(n)
CROSS JOIN (VALUES(N'INSERT'),(N'UPDATE'),(N'DELETE')) p(n)
WHERE ISNULL(HAS_PERMS_BY_NAME(o.n,'OBJECT',p.n),1)<>0
""";
        if (Convert.ToInt32(await cmd.ExecuteScalarAsync()) != 0)
            throw new InvalidOperationException("Runtime may modify legacy graph/roles/membership. Refused before API startup");
    }
    cmd.CommandText = "SELECT COUNT(*) FROM dbo.__EFMigrationsHistory WHERE MigrationId IN ('20261018022742_CreateWayMarkSchema','20261018053754_AddNavigationSchema','20261020094848_AddMapDraftFoundation','20261020101304_BindMapImagesToDrafts','20261023063955_AddPublishedMapProjects')";
    if (Convert.ToInt32(await cmd.ExecuteScalarAsync()) != 5) throw new InvalidOperationException("Reviewed map migration chain is not fully applied; this tool never applies migrations");
    cmd.CommandText = "SELECT COUNT(*) FROM dbo.__EFMigrationsHistory";
    if (Convert.ToInt32(await cmd.ExecuteScalarAsync()) != 5) throw new InvalidOperationException("Unexpected map migration history requires another review");
    cmd.CommandText = "SELECT COUNT(*) FROM dbo.__AuthMigrationsHistory WHERE MigrationId='20261010032404_CreateAuthSchema'";
    if (Convert.ToInt32(await cmd.ExecuteScalarAsync()) != 1) throw new InvalidOperationException("Expected independent Identity history missing");
    cmd.CommandText = "SELECT COUNT(*) FROM dbo.__AuthMigrationsHistory";
    if (Convert.ToInt32(await cmd.ExecuteScalarAsync()) != 1) throw new InvalidOperationException("Unexpected Identity migration history requires another review");
}
static async Task<string> Fingerprint(SqlConnection sql)
{
    using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
    foreach (var (table, order) in new[] { ("Sites", "Id"), ("Buildings", "Id"), ("Floors", "Id"),
        ("NavigationNodes", "Id"), ("NavigationEdges", "Id"), ("WayMarks", "Id"),
        ("AspNetUsers", "Id"), ("AspNetRoles", "Id"), ("AspNetRoleClaims", "Id"), ("AspNetUserClaims", "Id"),
        ("AspNetUserRoles", "UserId,RoleId"), ("AspNetUserLogins", "LoginProvider,ProviderKey"),
        ("AspNetUserTokens", "UserId,LoginProvider,Name"), ("SiteMapMemberships", "Id"),
        ("__AuthMigrationsHistory", "MigrationId"), ("__EFMigrationsHistory", "MigrationId") }) {
        using var cmd = sql.CreateCommand(); cmd.CommandTimeout = 5; cmd.CommandText = $"SELECT * FROM dbo.[{table}] ORDER BY {order} FOR JSON PATH,INCLUDE_NULL_VALUES";
        using var reader = await cmd.ExecuteReaderAsync();
        var text = new StringBuilder();
        while (await reader.ReadAsync()) text.Append(reader.GetString(0));
        // Preserve Unicode even if SQL splits a surrogate pair across JSON chunks.
        hash.AppendData(Encoding.UTF8.GetBytes(table + "\0"));
        hash.AppendData(Encoding.UTF8.GetBytes(text.ToString()));
    }
    return Convert.ToHexString(hash.GetHashAndReset()); // No Identity/legacy row content is output, only a digest.
}
static async Task<Process> StartApi(string root, string connection, string imageRoot, int port)
{
    var apiDir = Path.Combine(root, "WayMark.Api"); var assembly = Path.Combine(apiDir, "bin", "Debug", "net10.0", "WayMark.Api.dll");
    if (!File.Exists(assembly)) throw new InvalidOperationException("Build the reviewed API first");
    var configuration = WebApplication.CreateBuilder(new WebApplicationOptions { Args = [], ContentRootPath = apiDir,
        EnvironmentName = "Development", ApplicationName = typeof(WayMarkDbContext).Assembly.GetName().Name }).Configuration;
    if (configuration.GetSection("Kestrel:Endpoints").GetChildren().Any())
        throw new InvalidOperationException("Explicit Kestrel endpoints require separate review; no API child started");
    var protectedImageRoot = configuration["MapImages:RootPath"];
    if (!string.IsNullOrWhiteSpace(protectedImageRoot)) {
        if (!Path.IsPathFullyQualified(protectedImageRoot)) throw new InvalidOperationException("Unreviewed current storage configuration");
        var existing = Path.TrimEndingDirectorySeparator(Path.GetFullPath(protectedImageRoot));
        var planned = Path.TrimEndingDirectorySeparator(Path.GetFullPath(imageRoot));
        if (existing.Equals(planned, StringComparison.OrdinalIgnoreCase) || existing.StartsWith(planned + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)
            || planned.StartsWith(existing + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Test storage overlaps configured development storage");
    }
    var start = new ProcessStartInfo("dotnet") { WorkingDirectory = apiDir, UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
    start.ArgumentList.Add(assembly); start.ArgumentList.Add("--urls"); start.ArgumentList.Add($"http://127.0.0.1:{port}");
    start.Environment["DOTNET_ENVIRONMENT"] = "Development"; start.Environment["ASPNETCORE_ENVIRONMENT"] = "Development";
    start.Environment["E2E__Enabled"] = "false"; start.Environment["E2E__SqlConnectionString"] = "";
    start.Environment["ConnectionStrings__WayMarkDatabase"] = connection;
    start.Environment["MapImages__Enabled"] = "true"; start.Environment["MapImages__RootPath"] = imageRoot;
    start.Environment["MapImages__MaxStorageBytes"] = "134217728"; start.Environment["MapImages__MaxObjects"] = "20";
    start.Environment["MapDraftLimits__MaxImagesPerFloor"] = "4"; start.Environment["MapDraftLimits__MaxRevisionsPerFloor"] = "20";
    // No password env vars or setup credentials are forwarded to the API child.
    foreach (var name in start.Environment.Keys.Where(x => x.StartsWith("WAYMARK_CORE3_", StringComparison.OrdinalIgnoreCase)).ToArray()) start.Environment.Remove(name);
    var ready = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
    var process = new Process { StartInfo = start };
    process.OutputDataReceived += (_, e) => { if (e.Data?.Contains("Application started.", StringComparison.Ordinal) == true) ready.TrySetResult(); };
    process.ErrorDataReceived += (_, _) => { }; // Do not spill connection/log/credential content into evidence.
    process.Start(); process.BeginOutputReadLine(); process.BeginErrorReadLine();
    try { await ready.Task.WaitAsync(TimeSpan.FromSeconds(20)); if (process.HasExited) throw new InvalidOperationException("API child exited"); return process; }
    catch { Stop(process); throw new InvalidOperationException("Owned API did not confirm startup; no HTTP writes sent"); }
}
static void Stop(Process process)
{
    // Only the child returned by StartApi is stopped; never enumerate/kill other APIs.
    if (!process.HasExited) { process.Kill(entireProcessTree: true); process.WaitForExit(5000); }
    process.Dispose();
}
