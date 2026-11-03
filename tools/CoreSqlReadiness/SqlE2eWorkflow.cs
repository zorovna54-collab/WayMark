using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json;
using SkiaSharp;
using WayMark.Api.Contracts;
using WayMark.Api.Models;
using WayMark.Api.Services.Routing;

namespace WayMark.CoreSqlReadiness;

public sealed record E2eEvidence(MapProjectDto Project, NodeQrDto Qr, MapImageMetadataDto[] Images);

// The SAME HTTP workflow runs in SQLite tests and, only after separate approval,
// against the explicitly pinned SQL-backed child API. No direct SQL writes here.
public static class SqlE2eWorkflow
{
    public static async Task Login(HttpClient c, TestAccount account, string password)
    {
        var r = await c.PostAsJsonAsync("api/Auth/login", new { username = account.UserName, password });
        Status(r, 200, "Identity login");
        using var json = JsonDocument.Parse(await r.Content.ReadAsStringAsync());
        c.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", json.RootElement.GetProperty("accessToken").GetString());
    }
    public static async Task<E2eEvidence> Create(HttpClient a, HttpClient b, HttpClient guest, ReadinessPlan plan,
        Action<string> evidence)
    {
        var floors = new List<ProjectFloorDto>(); var images = new List<MapImageMetadataDto>();
        foreach (var (floorId, i) in plan.FloorIds.Select((id, i) => (id, i))) {
            var prefix = $"api/admin/floors/{floorId}/map-drafts";
            var draft = await Read<MapDraftMetadataDto>(await a.PostAsJsonAsync(prefix, new MapDraftContent()), 201, "Create unused floor draft");
            evidence($"draft={draft.Id};floor={floorId}"); // Identifiers only; never tokens/passwords.
            using var body = new ByteArrayContent(Image(i)); body.Headers.ContentType = new(i == 0 ? "image/png" : "image/jpeg");
            var asset = await Read<MapImageMetadataDto>(await a.PostAsync(prefix + "/images", body), 201, "Upload floor image");
            evidence($"asset={asset.Id};floor={floorId}"); images.Add(asset);
            Status(await guest.GetAsync(prefix + $"/images/{asset.Id}"), 401, "Guest private image denied");
            var start = new DraftNodeDto { Id = Guid.NewGuid(), NodeCode = i == 0 ? "START" : "STAIR", Name = i == 0 ? "Test entrance" : "Test stair L1",
                X = .2m, Y = .5m, NodeType = i == 0 ? NavigationNodeType.Entrance : NavigationNodeType.Stairs };
            var end = new DraftNodeDto { Id = Guid.NewGuid(), NodeCode = i == 0 ? "STAIR" : "DEST", Name = i == 0 ? "Test stair G" : "Test destination",
                X = .8m, Y = .5m, NodeType = i == 0 ? NavigationNodeType.Stairs : NavigationNodeType.Destination,
                SearchableAsDestination = i == 1, LandmarkNote = "Test fixture sign" };
            var content = new MapDraftContent { ImageAssetId = asset.Id, Nodes = [start, end],
                Edges = [new() { Id = Guid.NewGuid(), FromNodeId = start.Id, ToNodeId = end.Id, DistanceMeters = 5, EdgeType = NavigationEdgeType.Corridor }] };
            await Read<MapDraftMetadataDto>(await a.PutAsJsonAsync(prefix + $"/{draft.Id}", new SaveMapDraftRequest(1, content)), 200, "Save floor revision");
            var reload = await a.GetFromJsonAsync<MapDraftGraphDto>(prefix + $"/{draft.Id}/graph");
            Require(reload!.Content.ImageAssetId == asset.Id && reload.Content.Nodes!.Select(x => x.Id).SequenceEqual(content.Nodes.Select(x => x.Id)), "Floor image/node roundtrip");
            floors.Add(new(Guid.NewGuid(), floorId, i == 0 ? "Fixture G" : "Fixture L1", i == 0 ? "G" : "L1", content));
        }
        var doc = new ProjectContentDto(plan.RunId, floors, [new(Guid.NewGuid(), floors[0].Id, floors[0].Content.Nodes![1].Id,
            floors[1].Id, floors[1].Content.Nodes![0].Id, 3m, "Stairs")]);
        var project = await Read<MapProjectDto>(await a.PostAsJsonAsync("api/admin/map-projects", new CreateMapProjectRequest("wm-core3-" + plan.RunId.ToString("N"), doc)), 201, "Create project");
        evidence($"map={project.Id};version={project.Version}");
        var path = $"api/admin/map-projects/{project.Id}";
        Status(await guest.GetAsync(path), 401, "Guest private project denied");
        Status(await guest.GetAsync($"api/public/maps/{project.Id}/versions/1"), 404, "Unpublished snapshot hidden");
        var loaded = await a.GetFromJsonAsync<MapProjectDto>(path);
        Require(JsonSerializer.Serialize(loaded!.Content) == JsonSerializer.Serialize(doc), "Project reload graph/metadata");
        var qr = await Read<NodeQrDto>(await a.PostAsJsonAsync(path + "/qrs", new CreateNodeQrRequest(1, floors[0].Id, floors[0].Content.Nodes![0].Id)), 200, "Create stable node QR");
        Status(await b.PutAsJsonAsync(path, new SaveMapProjectRequest(1, "must-not-change-owner", doc)), 403, "Creator B save denied");
        Status(await b.PostAsJsonAsync(path + "/publish", new PublishMapRequest(1, true)), 403, "Creator B publish denied");
        Status(await b.PostAsync(path + $"/qrs/{qr.Id}/revoke", null), 403, "Creator B revoke denied");
        Status(await a.PostAsJsonAsync(path + "/publish", new PublishMapRequest(1, true)), 200, "Publish");
        var result = new E2eEvidence(project, qr, images.ToArray());
        Require(images[0].Sha256 != images[1].Sha256, "Distinct floor images");
        await Verify(guest, result);
        Status(await guest.PostAsJsonAsync(path + "/publish", new PublishMapRequest(1, true)), 401, "Public QR does not grant publishing");
        Status(await guest.PutAsJsonAsync(path, new SaveMapProjectRequest(1, "guest-write", doc)), 401, "Public QR does not grant editing");
        var modified = await Read<MapProjectDto>(await a.PutAsJsonAsync(path, new SaveMapProjectRequest(1, project.Name + "-private-edit", doc)), 200, "Edit after publish");
        Require(modified.Version == 2, "Private version increment");
        Status(await a.PutAsJsonAsync(path, new SaveMapProjectRequest(1, "stale", doc)), 409, "Concurrency conflict");
        await Verify(guest, result);
        evidence("PASS: private/owner/public/image checksum/directed multi-floor route/concurrency/immutable publication");
        return result;
    }
    public static async Task Verify(HttpClient guest, E2eEvidence result)
    {
        var p = result.Project;
        var resolve = await guest.GetFromJsonAsync<ResolveMapQrDto>("api/public/qr/" + result.Qr.Payload[6..]);
        Require(resolve!.MapId == p.Id && resolve.Version == 1 && resolve.FloorKey == p.Content.Floors[0].Id
            && resolve.NodeId == p.Content.Floors[0].Content.Nodes![0].Id, "QR stable identity");
        var snapshot = await guest.GetFromJsonAsync<PublicMapDto>($"api/public/maps/{p.Id}/versions/1");
        Require(snapshot!.Name == p.Name && !snapshot.VerifiedForPatientUse, "Immutable publication, not patient safety certification");
        foreach (var (f, i) in snapshot.Content.Floors.Select((f, i) => (f, i))) {
            var image = await guest.GetAsync($"api/public/maps/{p.Id}/versions/1/images/{f.Content.ImageAssetId}");
            Status(image, 200, "Published image read");
            var bytes = await image.Content.ReadAsByteArrayAsync();
            Require(Convert.ToHexStringLower(SHA256.HashData(bytes)) == result.Images[i].Sha256
                && image.Content.Headers.ContentType!.MediaType == result.Images[i].MimeType, "Per-floor image checksum/MIME");
        }
        // Reuse the existing router on the downloaded snapshot, not SQL demo graph.
        var nodes = snapshot.Content.Floors.SelectMany(x => x.Content.Nodes!).Select((n, i) => (n, id: i + 1)).ToDictionary(x => x.n.Id, x => x.id);
        var edges = snapshot.Content.Floors.SelectMany(x => x.Content.Edges!).Select((e, i) => new RoutingEdge(i + 1, nodes[e.FromNodeId], nodes[e.ToNodeId], e.DistanceMeters!.Value, e.IsActive)).ToList();
        foreach (var link in snapshot.Content.Links) edges.Add(new(edges.Count + 1, nodes[link.FromNode], nodes[link.ToNode], link.DistanceMeters, link.Active, EdgeType: NavigationEdgeType.Stairs));
        var end = snapshot.Content.Floors.SelectMany(x => x.Content.Nodes!).Single(x => x.SearchableAsDestination);
        var route = new DijkstraRouter().FindPath(nodes.Values.ToArray(), edges, nodes[resolve.NodeId], nodes[end.Id]);
        Require(route.Status == PathStatus.Success && route.TotalDistanceMeters == 13m && route.NodeIds.Count == 4, "Downloaded snapshot route to searchable node");
        Require(new DijkstraRouter().FindPath(nodes.Values.ToArray(), edges, nodes[end.Id], nodes[resolve.NodeId]).Status == PathStatus.NoPath, "No implicit reverse edges");
    }
    public static async Task Revoke(HttpClient a, HttpClient guest, E2eEvidence result)
    {
        Status(await a.PostAsync($"api/admin/map-projects/{result.Project.Id}/qrs/{result.Qr.Id}/revoke", null), 200, "Revoke fixture QR");
        Status(await guest.GetAsync("api/public/qr/" + result.Qr.Payload[6..]), 410, "Revoked QR refused");
    }
    public static async Task VerifyPrivateAfterRestart(HttpClient a, E2eEvidence result)
    {
        var loaded = await a.GetFromJsonAsync<MapProjectDto>($"api/admin/map-projects/{result.Project.Id}");
        Require(loaded!.Version == 2 && loaded.Name == result.Project.Name + "-private-edit"
            && JsonSerializer.Serialize(loaded.Content) == JsonSerializer.Serialize(result.Project.Content), "Private edited draft survives restart");
        foreach (var f in loaded.Content.Floors) {
            var prefix = $"api/admin/floors/{f.FloorId}/map-drafts";
            var metadata = await a.GetFromJsonAsync<MapDraftMetadataDto>(prefix);
            var graph = await a.GetFromJsonAsync<MapDraftGraphDto>(prefix + $"/{metadata!.Id}/graph");
            Require(graph!.Version == 2 && graph.Content.ImageAssetId == f.Content.ImageAssetId, "Floor revision image survives restart");
        }
    }
    public static byte[] Image(int floor)
    {
        using var bitmap = new SKBitmap(120, 80);
        using var canvas = new SKCanvas(bitmap); canvas.Clear(floor == 0 ? SKColors.LightBlue : SKColors.LightGoldenrodYellow);
        using var paint = new SKPaint { Color = SKColors.Black, StrokeWidth = 2 };
        canvas.DrawLine(24, 40, 96, 40, paint);
        using var image = SKImage.FromBitmap(bitmap);
        using var data = image.Encode(floor == 0 ? SKEncodedImageFormat.Png : SKEncodedImageFormat.Jpeg, 90);
        return data.ToArray();
    }
    private static void Require(bool condition, string label) { if (!condition) throw new InvalidOperationException("E2E failed: " + label); }
    private static void Status(HttpResponseMessage r, int status, string label) => Require((int)r.StatusCode == status, label + $" expected {status}, received {(int)r.StatusCode}");
    private static async Task<T> Read<T>(HttpResponseMessage r, int status, string label) { Status(r, status, label); return (await r.Content.ReadFromJsonAsync<T>())!; }
}
