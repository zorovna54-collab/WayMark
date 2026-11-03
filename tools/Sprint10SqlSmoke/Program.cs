using System.Diagnostics;
using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;
using WayMark.Api.Contracts;

// Explicit, user-approved local Development operation. No general migration,
// provisioning, graph writing, role grants, SMTP or database restore facility.
if (args.Length != 1 || args[0] != "--execute-approved-history")
    throw new InvalidOperationException("Requires the approved Sprint 10 History scope.");
var repo = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../../../"));
if (!File.Exists(Path.Combine(repo, "WayMark.Api/WayMark.Api.csproj"))) throw new Exception("Repository gate");
var run = Guid.NewGuid().ToString("N")[..12];
var evidence = Path.Combine(repo, "waymark/build/sprint10-sql-" + run);
Directory.CreateDirectory(evidence);
var checks = new List<object>();
var stage = "target";
string? backup = null;
Process? api = null;
var apiStarts = 0;
const string connection = "Server=.;Database=WayMarkDatabase;Integrated Security=True;Encrypt=True;TrustServerCertificate=True";
await using var sql = new SqlConnection(connection);
using var http = new HttpClient { BaseAddress = new("http://127.0.0.1:5121"), Timeout = TimeSpan.FromSeconds(25) };
void Check(bool ok, string name) { checks.Add(new { check = name, pass = ok }); Console.WriteLine(name + ": " + (ok ? "PASS" : "FAIL")); if (!ok) throw new Exception("Gate: " + name); }
async Task<string> Read(string query) {
    if (!query.TrimStart().StartsWith("SELECT", StringComparison.OrdinalIgnoreCase)) throw new Exception("Read helper accepts SELECT only");
    await using var cmd = new SqlCommand(query, sql) { CommandTimeout = 15 };
    return Convert.ToString(await cmd.ExecuteScalarAsync()) ?? "";
}
async Task Exec(string query, int timeout = 120, params SqlParameter[] parameters) {
    await using var cmd = new SqlCommand(query, sql) { CommandTimeout = timeout };
    cmd.Parameters.AddRange(parameters); await cmd.ExecuteNonQueryAsync();
}
async Task Target() => Check(await Read("SELECT CONVERT(nvarchar(128),SERVERPROPERTY('ServerName'))+'|'+DB_NAME()+'|'+ORIGINAL_LOGIN()") == @"LAPTOP-PFRPMR3O|WayMarkDatabase|LAPTOP-PFRPMR3O\pc", "exact-server-database-session");
async Task<string> Fingerprint() {
    // Hash only; never emit data, user identities, hashes or tokens from protected tables.
    var pieces = new List<string>();
    foreach (var table in new[] { "Sites", "Buildings", "Floors", "NavigationNodes", "NavigationEdges", "WayMarks", "MapProjects", "MapPublications", "MapPublicationImages", "MapNodeQrs", "FloorMapDrafts", "FloorMapDraftRevisions", "FloorMapImageAssets", "SiteMapMemberships" }) {
        // Only known tables, deterministic column ordering; no user-provided SQL identifiers.
        if (await Read($"SELECT CONVERT(varchar(10),COUNT(*)) FROM sys.tables WHERE name='{table}'") == "0") continue;
        var order = await Read($"SELECT STRING_AGG(CONVERT(nvarchar(max),QUOTENAME(c.name)),',') WITHIN GROUP (ORDER BY ic.key_ordinal) FROM sys.indexes i JOIN sys.index_columns ic ON i.object_id=ic.object_id AND i.index_id=ic.index_id JOIN sys.columns c ON ic.object_id=c.object_id AND ic.column_id=c.column_id WHERE i.is_primary_key=1 AND i.object_id=OBJECT_ID('dbo.{table}')");
        if (string.IsNullOrWhiteSpace(order)) throw new Exception("Fingerprint requires a deterministic primary key");
        pieces.Add(await Read($"SELECT CONVERT(varchar(64),HASHBYTES('SHA2_256',(SELECT * FROM dbo.[{table}] ORDER BY {order} FOR JSON PATH)),2)"));
    }
    pieces.Add(await Read("SELECT CONVERT(varchar(64),HASHBYTES('SHA2_256',(SELECT * FROM WayMarkAuthDatabase.dbo.AspNetUsers ORDER BY Id FOR JSON PATH)),2)"));
    pieces.Add(await Read("SELECT STRING_AGG(CONVERT(nvarchar(max),MigrationId),'|') WITHIN GROUP (ORDER BY MigrationId) FROM dbo.__AuthMigrationsHistory"));
    return string.Join('|', pieces);
}
async Task<JsonElement> Call(string method, string path, object? body, string? token, HttpStatusCode expected, string name) {
    using var req = new HttpRequestMessage(new HttpMethod(method), path);
    if (token is not null) req.Headers.Authorization = new("Bearer", token);
    if (body is not null) req.Content = JsonContent.Create(body);
    using var res = await http.SendAsync(req);
    checks.Add(new { check = name, status = (int)res.StatusCode, pass = res.StatusCode == expected });
    Console.WriteLine(name + ": HTTP " + (int)res.StatusCode);
    if (res.StatusCode != expected) throw new Exception("Unexpected HTTP at " + name + "; body omitted");
    return res.Content.Headers.ContentType?.MediaType == "application/json" ? (await res.Content.ReadFromJsonAsync<JsonElement>()).Clone() : default;
}
async Task Stop() {
    if (api is { HasExited: false }) { api.Kill(); await api.WaitForExitAsync(); }
    api?.Dispose(); api = null; await Task.Delay(500);
}
async Task Start() {
    using (var probe = new System.Net.Sockets.TcpClient()) {
        try { await probe.ConnectAsync("127.0.0.1", 5121); throw new Exception("Port owned by another process; no intervention"); }
        catch (System.Net.Sockets.SocketException) { }
    }
    var info = new ProcessStartInfo("dotnet") { WorkingDirectory = Path.Combine(repo, "WayMark.Api"), UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
    foreach (var arg in new[] { "bin/Debug/net10.0/WayMark.Api.dll", "--urls", "http://127.0.0.1:5121" }) info.ArgumentList.Add(arg);
    info.Environment["ASPNETCORE_ENVIRONMENT"] = "Development";
    info.Environment["ConnectionStrings__WayMarkDatabase"] = connection;
    // Existing User Secrets consumed by host; never copied, printed or overridden.
    api = Process.Start(info) ?? throw new Exception("API launch failed");
    var current = api; var log = Path.Combine(evidence, $"api-{++apiStarts}.log");
    var output = current.StandardOutput.ReadToEndAsync(); var error = current.StandardError.ReadToEndAsync();
    _ = Task.Run(async () => { await current.WaitForExitAsync(); await File.WriteAllTextAsync(log, await output + await error); });
    for (var i = 0; i < 60; i++) {
        if (current.HasExited) throw new Exception("API exited; no policy bypass");
        try { using var res = await http.GetAsync("/swagger/v1/swagger.json"); if (res.IsSuccessStatusCode) return; } catch (HttpRequestException) { }
        await Task.Delay(250);
    }
    throw new Exception("API startup timeout");
}
try {
    await sql.OpenAsync(); await Target();
    Check(await Read("SELECT encrypt_option FROM sys.dm_exec_connections WHERE session_id=@@SPID") == "TRUE", "SQL-encryption-enabled");
    var before = await Fingerprint();
    var expected = new[] { "20261018022742_CreateWayMarkSchema", "20261018053754_AddNavigationSchema", "20261020094848_AddMapDraftFoundation", "20261020101304_BindMapImagesToDrafts", "20261023063955_AddPublishedMapProjects" };
    const string historyQuery = "SELECT STRING_AGG(CONVERT(nvarchar(max),MigrationId),'|') WITHIN GROUP (ORDER BY MigrationId) FROM dbo.__EFMigrationsHistory";
    Check(await Read(historyQuery) == string.Join('|', expected), "exact-five-applied-migrations-before-write");
    Check(await Read("SELECT CONVERT(varchar(10),COUNT(*)) FROM sys.tables WHERE name='NavigationHistory'") == "0", "History-absent-before-migration");
    var scriptPath = Path.Combine(repo, "docs/database/sprint10/NavigationHistory.review.sql");
    var bytes = await File.ReadAllBytesAsync(scriptPath);
    Check(Convert.ToHexString(SHA256.HashData(bytes)) == "D0C84FBF8EC4129B1DB47B72F370210DD9EC32A2FFFBF24401158B1BCF1AAAA6", "reviewed-SQL-SHA256");
    stage = "backup";
    var directory = await Read("SELECT CONVERT(nvarchar(4000),SERVERPROPERTY('InstanceDefaultBackupPath'))");
    Check(Path.IsPathFullyQualified(directory) && Directory.Exists(directory), "server-backup-directory-exists");
    backup = Path.Combine(directory, $"WayMarkDatabase_Sprint10_{run}_copyonly.bak");
    Check(!File.Exists(backup), "new-backup-never-overwrite");
    await Target();
    await Exec("BACKUP DATABASE [WayMarkDatabase] TO DISK=@path WITH COPY_ONLY,CHECKSUM", 180, new SqlParameter("@path", backup));
    await Exec("RESTORE VERIFYONLY FROM DISK=@path WITH CHECKSUM", 180, new SqlParameter("@path", backup));
    await using (var cmd = new SqlCommand("SELECT COUNT(*) FROM msdb.dbo.backupset b JOIN msdb.dbo.backupmediafamily f ON b.media_set_id=f.media_set_id WHERE b.database_name='WayMarkDatabase' AND b.type='D' AND b.is_copy_only=1 AND b.has_backup_checksums=1 AND b.backup_finish_date IS NOT NULL AND f.physical_device_name=@path", sql)) {
        cmd.Parameters.AddWithValue("@path", backup); Check(Convert.ToInt32(await cmd.ExecuteScalarAsync()) == 1, "full-COPY_ONLY-checksum-metadata-VERIFYONLY");
    }
    await using (var stream = File.OpenRead(backup)) await File.WriteAllTextAsync(Path.Combine(evidence, "backup-sha256.txt"), Convert.ToHexString(await SHA256.HashDataAsync(stream)));
    await File.WriteAllTextAsync(Path.Combine(evidence,"backup-verified.json"), JsonSerializer.Serialize(new { backup, verified=true }));
    stage = "migration"; await Target();
    Check(await Read(historyQuery) == string.Join('|', expected), "migration-baseline-still-matches");
    await Exec("SET XACT_ABORT ON"); // Own fresh connection; never affects a caller transaction/session.
    foreach (var batch in Regex.Split(System.Text.Encoding.UTF8.GetString(bytes).TrimStart('\uFEFF'), @"^GO\s*$", RegexOptions.Multiline | RegexOptions.IgnoreCase))
        if (!string.IsNullOrWhiteSpace(batch)) await Exec(batch);
    Check(await Read(historyQuery) == string.Join('|', expected.Concat(new[] { "20261025010000_AddNavigationHistory", "20261026001522_ExtendNavigationHistoryLifecycle" })), "exact-two-History-migrations-applied");
    await File.WriteAllTextAsync(Path.Combine(evidence,"migration-applied.json"), "{\"approvedHistoryMigrationsApplied\":true}");
    stage = "HTTP-history";
    var state = JsonDocument.Parse(await File.ReadAllTextAsync(Path.Combine(repo, "waymark/build/p0-runtime-1e116efce42c/public-state.json"))).RootElement;
    var qr = state.GetProperty("qr").Deserialize<NodeQrDto>(new JsonSerializerOptions(JsonSerializerDefaults.Web))!;
    Check(qr.MapId == Guid.Parse("b86cbcbb-786e-4baf-8b33-29800ed6e417") && qr.IsActive, "existing-approved-P0-fixture-only");
    await Start();
    var tokens = new List<string>(); var names = new List<string>();
    foreach (var suffix in new[] { "a", "b" }) {
        var username = $"s10-{run}-{suffix}"; names.Add(username);
        var password = "S10!aA" + Guid.NewGuid().ToString("N");
        await Call("POST", "/api/Auth/register", new { username, password }, null, HttpStatusCode.OK, "register-"+suffix+"-no-email-no-role-grant");
        var login = await Call("POST", "/api/Auth/login", new { username, password }, null, HttpStatusCode.OK, "login-"+suffix);
        tokens.Add(login.GetProperty("accessToken").GetString()!);
    }
    var a=tokens[0]; var b=tokens[1]; const string path="/api/me/navigation-history";
    var pos = await Call("GET", "/api/public/qr/"+qr.Payload[6..], null, null, HttpStatusCode.OK, "Guest-resolve-existing-QR");
    Check(pos.GetProperty("nodeId").GetGuid()==qr.NodeId, "stable-QR-start-node");
    var publicPath=$"/api/public/maps/{qr.MapId}/versions/{qr.PublishedVersion}";
    var snapshot=(await Call("GET", publicPath,null,null,HttpStatusCode.OK,"Guest-existing-snapshot")).Deserialize<PublicMapDto>(new JsonSerializerOptions(JsonSerializerDefaults.Web))!;
    var floor=snapshot.Content.Floors.Single(); var destination=floor.Content.Nodes!.Single(n=>n.SearchableAsDestination);
    await Call("GET",path,null,null,HttpStatusCode.Unauthorized,"Guest-private-history-401");
    var id=Guid.NewGuid(); var body=new {sessionId=id,qrToken=qr.Payload[6..]};
    var scanned=await Call("POST",path,body,a,HttpStatusCode.Created,"QR-resolved-creates-Scanned");
    Check(scanned.GetProperty("status").GetString()=="Scanned" && scanned.GetProperty("destinationNodeId").ValueKind==JsonValueKind.Null,"scan-without-destination-persisted");
    for(var i=0;i<8;i++) await Call("POST",path,body,a,HttpStatusCode.OK,"duplicate-frame-idempotent-"+i);
    var list=await Call("GET",path,null,a,HttpStatusCode.OK,"A-list-after-scan"); Check(list.GetArrayLength()==1,"one-session-for-eight-duplicate-frames");
    await Call("PUT",$"{path}/{id}/destination",new {destinationFloorKey=floor.Id,destinationNodeId=destination.Id},a,HttpStatusCode.OK,"select-destination-same-session");
    await Call("PUT",$"{path}/{id}/start",null,a,HttpStatusCode.OK,"navigation-start");
    await Call("PUT",$"{path}/{id}/start",null,a,HttpStatusCode.OK,"start-idempotent");
    var done=await Call("PUT",$"{path}/{id}",new {status="Completed"},a,HttpStatusCode.OK,"explicit-Finish-Completed");
    Check(done.GetProperty("status").GetString()=="Completed" && done.GetProperty("distanceMeters").GetDecimal()==12 && done.GetProperty("navigationStartedAtUtc").ValueKind==JsonValueKind.String,"Completed-timestamps-and-real-12m");
    var cancelled=Guid.NewGuid();
    await Call("POST",path,new {sessionId=cancelled,qrToken=qr.Payload[6..]},a,HttpStatusCode.Created,"second-scan");
    await Call("PUT",$"{path}/{cancelled}",new {status="Cancelled"},a,HttpStatusCode.OK,"cancel-Scanned-no-destination");
    foreach(var method in new[]{"GET","PUT","DELETE"}) await Call(method,$"{path}/{id}",method=="PUT"?new {status="Cancelled"}:null,b,HttpStatusCode.NotFound,"B-cannot-"+method+"-A-history");
    Check((await Call("GET",path,null,b,HttpStatusCode.OK,"B-list-isolated")).GetArrayLength()==0,"B-no-A-records");
    await Call("POST",path,new {sessionId=Guid.NewGuid(),qrToken=new string('0',64)},a,HttpStatusCode.NotFound,"unknown-QR-no-history");
    await Stop(); await Start();
    var persisted=await Call("GET",path,null,a,HttpStatusCode.OK,"API-restart-History");
    Check(persisted.GetArrayLength()==2 && persisted.EnumerateArray().Any(x=>x.GetProperty("id").GetGuid()==id && x.GetProperty("status").GetString()=="Completed"),"SQL-restart-persistence-Completed-and-Cancelled");
    await Call("GET",$"{path}/{id}/resume",null,a,HttpStatusCode.OK,"resume-pinned-published-map");
    foreach(var fixtureId in new[]{id,cancelled}) await Call("DELETE",$"{path}/{fixtureId}",null,a,HttpStatusCode.NoContent,"delete-only-own-fixture-"+fixtureId);
    Check((await Call("GET",path,null,a,HttpStatusCode.OK,"reload-after-delete")).GetArrayLength()==0,"fixture-History-actually-deleted");
    Check(await Fingerprint()==before,"map-QR-graph-and-legacy-auth-unchanged");
    await using(var cmd=new SqlCommand("SELECT COUNT(*) FROM dbo.AspNetUsers u LEFT JOIN dbo.AspNetUserRoles r ON r.UserId=u.Id WHERE u.UserName IN (@a,@b) AND (u.Email IS NOT NULL OR r.UserId IS NOT NULL)",sql)) {
        cmd.Parameters.AddWithValue("@a",names[0]); cmd.Parameters.AddWithValue("@b",names[1]); Check(Convert.ToInt32(await cmd.ExecuteScalarAsync())==0,"two-test-users-no-email-no-roles");
    }
    stage="complete";
} catch(Exception e) {
    if (stage == "migration" && sql.State == System.Data.ConnectionState.Open) {
        // Only a still-open transaction created by this runner's reviewed batches.
        // Earlier committed batches remain; never run Down or restore automatically.
        try { await Exec("IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION"); } catch { }
    }
    // Deliberately omit exception detail/inner SQL messages/configuration/HTTP bodies.
    Console.WriteLine("STOP at "+stage+" ("+e.GetType().Name+"). No automatic restore or rollback of applied migrations.");
    Environment.ExitCode=1;
} finally {
    await Stop();
    await File.WriteAllTextAsync(Path.Combine(evidence,"results.json"),JsonSerializer.Serialize(new {runId=run,stage,backup,target="LAPTOP-PFRPMR3O/WayMarkDatabase",checks},new JsonSerializerOptions{WriteIndented=true}));
    Console.WriteLine("Evidence: "+evidence);
}
