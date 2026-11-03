using System.Diagnostics;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using SkiaSharp;
using WayMark.Api.Contracts;
using WayMark.Api.Models;
using WayMark.Api.Services.MapDrafts;

var resumePath = args.Length == 2 && args[0] == "--resume-readonly" ? Path.GetFullPath(args[1]) : null;
if (resumePath is null && (args.Length != 1 || args[0] != "--execute-approved-personal-fixture"))
    throw new InvalidOperationException("Requires explicit approval for 2 test users / 1 personal fixture only.");
var repo = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../../../"));
if (!File.Exists(Path.Combine(repo, "WayMark.Api/WayMark.Api.csproj"))) throw new Exception("Unexpected repository root");
var run = resumePath is null ? Guid.NewGuid().ToString("N")[..12] : JsonDocument.Parse(File.ReadAllText(resumePath)).RootElement.GetProperty("runId").GetString()!;
if (!System.Text.RegularExpressions.Regex.IsMatch(run, "^[a-f0-9]{12}$")) throw new Exception("Invalid fixture RunId");
var evidence = Path.Combine(repo, "waymark/build", "p0-runtime-" + run); Directory.CreateDirectory(evidence);
if (resumePath is not null && !string.Equals(resumePath, Path.GetFullPath(Path.Combine(evidence, "results.json")), StringComparison.OrdinalIgnoreCase)) throw new Exception("Resume only the approved fixture evidence");
var checks = new List<object>();
const string sqlConnection = "Server=.;Database=WayMarkDatabase;Integrated Security=True;Encrypt=True;TrustServerCertificate=True";
await using var sql = new SqlConnection(sqlConnection); await sql.OpenAsync();
async Task<string> ReadSql(string text) {
    if (!text.TrimStart().StartsWith("SELECT", StringComparison.OrdinalIgnoreCase)) throw new Exception("SELECT only");
    await using var command = new SqlCommand(text, sql); command.CommandTimeout = 10;
    await using var reader = await command.ExecuteReaderAsync(); var rows = new List<string>();
    while (await reader.ReadAsync()) rows.Add(reader.GetString(0)); return string.Join('\n', rows);
}
var target = await ReadSql("SELECT CONVERT(nvarchar(128),SERVERPROPERTY('ServerName'))+'|'+DB_NAME()+'|'+ORIGINAL_LOGIN()");
if (target != @"LAPTOP-PFRPMR3O|WayMarkDatabase|LAPTOP-PFRPMR3O\pc") throw new Exception("Unexpected server/database/session");
const string historyQuery = "SELECT MigrationId FROM dbo.__EFMigrationsHistory ORDER BY MigrationId";
var history = await ReadSql(historyQuery);
foreach (var id in new[] { "20261020094848_AddMapDraftFoundation", "20261020101304_BindMapImagesToDrafts", "20261023063955_AddPublishedMapProjects" })
    if (!history.Contains(id)) throw new Exception("Required migration missing; will not migrate");
const string fingerprintQuery = """
SELECT CONVERT(varchar(64),HASHBYTES('SHA2_256',(SELECT * FROM dbo.WayMarks ORDER BY Id FOR JSON PATH)),2)+'|'+
CONVERT(varchar(64),HASHBYTES('SHA2_256',(SELECT * FROM dbo.NavigationNodes ORDER BY Id FOR JSON PATH)),2)+'|'+
CONVERT(varchar(64),HASHBYTES('SHA2_256',(SELECT * FROM dbo.NavigationEdges ORDER BY Id FOR JSON PATH)),2)+'|'+
CONVERT(varchar(64),HASHBYTES('SHA2_256',(SELECT * FROM WayMarkAuthDatabase.dbo.AspNetUsers ORDER BY Id FOR JSON PATH)),2)
""";
var before = await ReadSql(fingerprintQuery);
var root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WayMark/CoreSprint6/2e5448b27c064a93a438f0d22a2edca6/images");
using (var local = JsonDocument.Parse(await File.ReadAllTextAsync(Path.Combine(repo, "WayMark.Api/appsettings.Development.json")))) {
    var storage = local.RootElement.GetProperty("MapImages");
    if (!storage.GetProperty("Enabled").GetBoolean() || !string.Equals(Path.GetFullPath(storage.GetProperty("RootPath").GetString()!), Path.GetFullPath(root), StringComparison.OrdinalIgnoreCase) || !Directory.Exists(root)) throw new Exception("Local image configuration mismatch");
}
using var http = new HttpClient { BaseAddress = new("http://127.0.0.1:5121"), Timeout = TimeSpan.FromSeconds(30) };
Process? api = null; int starts = 0; MapProjectDto? map = null; MapImageMetadataDto? asset = null; NodeQrDto? qr = null;
void Verify(bool condition, string name) { checks.Add(new { check = name, pass = condition }); if (!condition) throw new Exception("Assertion failed: " + name); }
async Task<JsonElement> Call(string method, string path, object? body, string? token, HttpStatusCode expected, string name, byte[]? image = null) {
    using var request = new HttpRequestMessage(new HttpMethod(method), path);
    if (token is not null) request.Headers.Authorization = new("Bearer", token);
    if (image is not null) { request.Content = new ByteArrayContent(image); request.Content.Headers.ContentType = new("image/png"); }
    else if (body is not null) request.Content = JsonContent.Create(body);
    using var response = await http.SendAsync(request);
    checks.Add(new { check = name, status = (int)response.StatusCode, pass = response.StatusCode == expected });
    if (response.StatusCode != expected) throw new Exception($"Step {name}: HTTP {(int)response.StatusCode}, expected {(int)expected}. Body omitted.");
    if (response.Content.Headers.ContentType?.MediaType == "application/json") return (await response.Content.ReadFromJsonAsync<JsonElement>()).Clone();
    var bytes = await response.Content.ReadAsByteArrayAsync();
    if (expected == HttpStatusCode.OK && name.Contains("image")) Verify(bytes.Length > 100 && bytes[0] == 137, name + "-PNG-pixels");
    return default;
}
T Decode<T>(JsonElement json) => json.Deserialize<T>(new JsonSerializerOptions(JsonSerializerDefaults.Web))!;
async Task StopApi() {
    if (api is { HasExited: false }) { api.Kill(); await api.WaitForExitAsync(); }
    api?.Dispose(); api = null;
    await Task.Delay(500); // Let the task-owned listener close before probing restart.
}
async Task StartApi() {
    // Never stop or replace another process. Only this Process instance is stopped.
    using (var probe = new System.Net.Sockets.TcpClient()) {
        try { await probe.ConnectAsync("127.0.0.1", 5121); throw new InvalidOperationException("Port already owned by another process"); }
        catch (System.Net.Sockets.SocketException) { }
    }
    var info = new ProcessStartInfo("dotnet") { WorkingDirectory = Path.Combine(repo, "WayMark.Api"), UseShellExecute = false, CreateNoWindow = true,
        RedirectStandardOutput = true, RedirectStandardError = true };
    info.ArgumentList.Add("bin/Debug/net10.0/WayMark.Api.dll"); info.ArgumentList.Add("--urls"); info.ArgumentList.Add("http://127.0.0.1:5121");
    info.Environment["ASPNETCORE_ENVIRONMENT"] = "Development";
    info.Environment["ConnectionStrings__WayMarkDatabase"] = sqlConnection;
    // No secret override. Startup uses existing User Secrets and persisted local
    // MapImages config. Never call migrations, seeders or registration with email.
    api = Process.Start(info) ?? throw new Exception("Cannot launch API");
    var log = Path.Combine(evidence, $"api-{++starts}.log");
    var stdout = api.StandardOutput.ReadToEndAsync(); var stderr = api.StandardError.ReadToEndAsync();
    var current = api;
    _ = Task.Run(async () => { await current.WaitForExitAsync(); await File.WriteAllTextAsync(log, await stdout + await stderr); });
    for (var n = 0; n < 40; n++) {
        if (api.HasExited) throw new Exception("API exited; inspect ignored logs. No Application Control bypass.");
        try { using var response = await http.GetAsync("/swagger/v1/swagger.json"); if (response.IsSuccessStatusCode) return; } catch (HttpRequestException) { }
        await Task.Delay(250);
    }
    throw new Exception("API startup timeout");
}
try {
    if (resumePath is not null) {
        var prior = JsonDocument.Parse(await File.ReadAllTextAsync(resumePath)).RootElement;
        var mapId = prior.GetProperty("mapId").GetGuid();
        var stored = JsonDocument.Parse(await ReadSql($"SELECT Id,Name,Version,SiteId,BuildingId,JSON_QUERY(ContentJson) AS Content,UpdatedAt FROM dbo.MapProjects WHERE Id='{mapId:D}' AND Name='P0Runtime-{run}' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER")).RootElement;
        map = Decode<MapProjectDto>(stored);
        var qrJson = JsonDocument.Parse(await ReadSql($"SELECT Id,MapId,FloorKey,NodeId,DraftVersion,PublishedVersion,'WMQR1:'+Token AS Payload,IsActive FROM dbo.MapNodeQrs WHERE MapId='{mapId:D}' AND IsActive=1 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER")).RootElement;
        qr = Decode<NodeQrDto>(qrJson);
        var resumedcontent = map.Content.Floors.Single().Content;
        Verify(resumedcontent.Nodes!.Count == 3 && resumedcontent.Edges!.Count == 2 && resumedcontent.ImageAssetId.HasValue, "SQL-persisted-3-nodes-2-edges-image");
        Verify(resumedcontent.Nodes.Count(n => n.SearchableAsDestination) == 1 && resumedcontent.Edges!.Sum(e => e.DistanceMeters) == 12, "SQL-searchable-and-metres");
        await StartApi();
        var resumedpath = $"/api/public/maps/{map.Id}/versions/{map.Version}";
        var resumedsnapshot = Decode<PublicMapDto>(await Call("GET", resumedpath, null, null, HttpStatusCode.OK, "restart-Guest-resumedsnapshot"));
        Verify(JsonSerializer.Serialize(resumedsnapshot.Content) == JsonSerializer.Serialize(map.Content), "restart-resumedsnapshot-exact-persisted-graph");
        var resumedposition = Decode<ResolveMapQrDto>(await Call("GET", "/api/public/qr/" + qr.Payload[6..], null, null, HttpStatusCode.OK, "restart-Guest-QR"));
        Verify(resumedposition.NodeId == qr.NodeId && resumedposition.FloorKey == qr.FloorKey, "restart-QR-identity");
        await Call("GET", resumedpath + "/images/" + resumedcontent.ImageAssetId, null, null, HttpStatusCode.OK, "restart-Guest-image");
        await Call("GET", $"/api/admin/map-projects/{map.Id}", null, null, HttpStatusCode.Unauthorized, "restart-private-JWT-required");
        var scopedRoles = await ReadSql($"SELECT CONVERT(varchar(10),COUNT(*)) FROM dbo.AspNetUserRoles ur JOIN dbo.AspNetUsers u ON u.Id=ur.UserId JOIN dbo.AspNetRoles r ON r.Id=ur.RoleId WHERE u.UserName IN ('p0-{run}-a','p0-{run}-b') AND r.Name='Admin'");
        Verify(scopedRoles == "0", "fixture-no-Admin-role");
        await RunGuest();
        Verify(await ReadSql(fingerprintQuery) == before, "resume-readonly-no-legacy-change");
        Verify(await ReadSql(historyQuery) == history, "migration-history-unchanged");
        return;
    }
    await StartApi(); var tokens = new List<string>();
    foreach (var suffix in new[] { "a", "b" }) {
        var username = $"p0-{run}-{suffix}"; var password = "T3st!" + Guid.NewGuid().ToString("N");
        await Call("POST", "/api/Auth/register", new { username, password }, null, HttpStatusCode.OK, "register-" + suffix + "-no-email");
        var login = await Call("POST", "/api/Auth/login", new { username, password }, null, HttpStatusCode.OK, "login-" + suffix);
        tokens.Add(login.GetProperty("accessToken").GetString()!);
    }
    map = Decode<MapProjectDto>(await Call("POST", "/api/me/map-workspaces", new StartPersonalMapRequest(Guid.NewGuid(), "P0Runtime-" + run,
        "PersonalDemo", "Approved runtime fixture", "Not a real hospital map", "P0 Ground", "G"), tokens[0], HttpStatusCode.Created, "personal-workspace"));
    var path = $"/api/admin/map-projects/{map.Id}"; var floor = map.Content.Floors.Single();
    var imagePath = $"/api/admin/floors/{floor.FloorId}/map-drafts";
    await Call("POST", imagePath, new MapDraftContent(), tokens[0], HttpStatusCode.Created, "create-image-draft");
    using var bitmap = new SKBitmap(900, 598); using var canvas = new SKCanvas(bitmap); canvas.Clear(SKColors.White);
    using var paint = new SKPaint { Color = SKColors.Black, Style = SKPaintStyle.Stroke, StrokeWidth = 4 };
    canvas.DrawRect(30, 30, 840, 538, paint); foreach (var x in new[] { 40, 320, 600 }) canvas.DrawRect(x, 45, 240, 180, paint);
    using var font = new SKFont(SKTypeface.Default, 22); paint.Style = SKPaintStyle.Fill;
    canvas.DrawText("EXAM (TEST)", 50, 120, SKTextAlign.Left, font, paint); canvas.DrawText("TRIAGE", 335, 120, SKTextAlign.Left, font, paint); canvas.DrawText("WAITING", 610, 120, SKTextAlign.Left, font, paint);
    canvas.DrawText("P0 FIXTURE CORRIDOR", 160, 320, SKTextAlign.Left, font, paint);
    using var rendered = SKImage.FromBitmap(bitmap); using var encoded = rendered.Encode(SKEncodedImageFormat.Png, 100);
    var image = encoded.ToArray(); await File.WriteAllBytesAsync(Path.Combine(evidence, "fixture-floor.png"), image);
    asset = Decode<MapImageMetadataDto>(await Call("POST", imagePath + "/images", null, tokens[0], HttpStatusCode.Created, "upload-image", image));
    var ids = new[] { Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid() };
    var content = map.Content with { Floors = [floor with { Content = new() { ImageAssetId = asset.Id,
        Nodes = [new() { Id = ids[0], NodeCode = "QR-JUNCTION", Name = "P0 Start", X = .1m, Y = .5m, NodeType = NavigationNodeType.Junction },
            new() { Id = ids[1], NodeCode = "MID", Name = "P0 Corridor", X = .5m, Y = .5m, NodeType = NavigationNodeType.Junction },
            new() { Id = ids[2], NodeCode = "DEST", Name = "P0 Destination", X = .9m, Y = .5m, NodeType = NavigationNodeType.Destination, SearchableAsDestination = true }],
        Edges = [new() { Id = Guid.NewGuid(), FromNodeId = ids[0], ToNodeId = ids[1], DistanceMeters = 5m },
            new() { Id = Guid.NewGuid(), FromNodeId = ids[1], ToNodeId = ids[2], DistanceMeters = 7m }] } }] };
    await Call("PUT", path, new SaveMapProjectRequest(map.Version, map.Name, content), tokens[0], HttpStatusCode.OK, "save-project");
    var saved = Decode<MapProjectDto>(await Call("GET", path, null, tokens[0], HttpStatusCode.OK, "GET-project"));
    Verify(saved.Content.Id == content.Id && saved.Content.Floors.Single().Id == floor.Id && JsonSerializer.Serialize(saved.Content) == JsonSerializer.Serialize(content), "GET-exact-identity-graph-image-direction-metres");
    qr = Decode<NodeQrDto>(await Call("POST", path + "/qrs", new CreateNodeQrRequest(saved.Version, floor.Id, ids[0]), tokens[0], HttpStatusCode.OK, "create-junction-QR"));
    var ready = Decode<PublishReadinessDto>(await Call("GET", path + "/publish-readiness", null, tokens[0], HttpStatusCode.OK, "readiness"));
    Verify(ready.Checks.All(c => c.Passed), "all-readiness-checks");
    await Call("POST", path + "/publish", new PublishMapRequest(saved.Version, true), tokens[0], HttpStatusCode.OK, "personal-publish");
    await Call("GET", path, null, null, HttpStatusCode.Unauthorized, "Guest-private-denied");
    // B has no personal entitlement and is rejected at MapAuthor policy. No second workspace is created.
    await Call("GET", path, null, tokens[1], HttpStatusCode.Forbidden, "B-private-denied");
    await Call("POST", path + "/publish", new PublishMapRequest(saved.Version, true), tokens[1], HttpStatusCode.Forbidden, "B-publish-denied");
    var publicPath = $"/api/public/maps/{map.Id}/versions/{saved.Version}";
    var position = Decode<ResolveMapQrDto>(await Call("GET", "/api/public/qr/" + qr.Payload[6..], null, null, HttpStatusCode.OK, "Guest-QR-resolve"));
    Verify(position.NodeId == ids[0] && position.FloorKey == floor.Id, "Guest-QR-position");
    var snapshot = Decode<PublicMapDto>(await Call("GET", publicPath, null, null, HttpStatusCode.OK, "Guest-snapshot"));
    Verify(JsonSerializer.Serialize(snapshot.Content) == JsonSerializer.Serialize(content), "snapshot-exact-builder-content");
    await Call("GET", publicPath + "/images/" + asset.Id, null, null, HttpStatusCode.OK, "Guest-image");
    await Call("GET", imagePath + "/images/" + asset.Id, null, tokens[0], HttpStatusCode.OK, "private-image");
    await StopApi(); await StartApi();
    var persisted = Decode<MapProjectDto>(await Call("GET", path, null, tokens[0], HttpStatusCode.OK, "restart-draft"));
    Verify(JsonSerializer.Serialize(persisted.Content) == JsonSerializer.Serialize(content), "restart-exact-content");
    await Call("GET", publicPath + "/images/" + asset.Id, null, null, HttpStatusCode.OK, "restart-Guest-image");
    await Call("GET", imagePath + "/images/" + asset.Id, null, tokens[0], HttpStatusCode.OK, "restart-private-image");
    Verify(await ReadSql(fingerprintQuery) == before, "legacy-graph-and-auth-db-unchanged");
    Verify(await ReadSql(historyQuery) == history, "migration-history-unchanged");
    await RunGuest();
} finally {
    await StopApi();
    await File.WriteAllTextAsync(Path.Combine(evidence, resumePath is null ? "results.json" : "resume-results.json"), JsonSerializer.Serialize(new { runId = run, target = "LAPTOP-PFRPMR3O/WayMarkDatabase", checks, mapId = map?.Id, floorId = map?.Content.Floors.Single().FloorId, imageId = asset?.Id, camera = "MANUAL PENDING" }, new JsonSerializerOptions { WriteIndented = true }));
    Console.WriteLine("Evidence: " + evidence);
    Console.WriteLine("Completed checks: " + checks.Count);
}
async Task RunGuest() {
    var statePath = Path.Combine(evidence, "public-state.json");
    await File.WriteAllTextAsync(statePath, JsonSerializer.Serialize(new { port = 5121, project = new { id = map!.Id }, qr }, new JsonSerializerOptions(JsonSerializerDefaults.Web)));
    var test = new ProcessStartInfo("cmd.exe") { WorkingDirectory = Path.Combine(repo, "waymark"), UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
    test.ArgumentList.Add("/c"); test.ArgumentList.Add("flutter"); test.ArgumentList.Add("test"); test.ArgumentList.Add("--reporter"); test.ArgumentList.Add("expanded");
    test.ArgumentList.Add("test/p0_live_sql_navigation_test.dart"); test.ArgumentList.Add("--dart-define=WAYMARK_LIVE_SQL_STATE=" + statePath);
    using var child = Process.Start(test)!; var output = child.StandardOutput.ReadToEndAsync(); var errors = child.StandardError.ReadToEndAsync();
    await child.WaitForExitAsync().WaitAsync(TimeSpan.FromMinutes(3)); await File.WriteAllTextAsync(Path.Combine(evidence, "flutter-live.log"), await output + await errors);
    Verify(child.ExitCode == 0, "live-Flutter-Guest-GET-navigation");
}
