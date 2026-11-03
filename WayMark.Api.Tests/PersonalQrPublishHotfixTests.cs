using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using WayMark.Api.Contracts;
using WayMark.Api.Data;
using WayMark.Api.Models;
using WayMark.Api.Services.MapDrafts;
using Xunit;

namespace WayMark.Api.Tests;

public sealed class PersonalQrPublishHotfixTests
{
    private static async Task<string> Login(MapDraftTestHost h, string name)
    {
        var password = "Isolated1!" + Guid.NewGuid().ToString("N");
        (await h.Client.PostAsJsonAsync("/api/Auth/register", new { username = name, password })).EnsureSuccessStatusCode();
        var login = await h.Client.PostAsJsonAsync("/api/Auth/login", new { username = name, password });
        login.EnsureSuccessStatusCode();
        var token = (await login.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("accessToken").GetString()!;
        h.Client.DefaultRequestHeaders.Authorization = new("Bearer", token); return token;
    }
    private static async Task<MapProjectDto> Start(MapDraftTestHost h)
    {
        var r = await h.Client.PostAsJsonAsync("/api/me/map-workspaces", new StartPersonalMapRequest(Guid.NewGuid(), "3-node personal map", "PersonalDemo", "Isolated test", null, "Floor G", "G"));
        r.EnsureSuccessStatusCode(); return (await r.Content.ReadFromJsonAsync<MapProjectDto>())!;
    }
    [Fact]
    public async Task Empty_workspace_then_real_upload_save_reload_QR_publish_guest_snapshot_and_owner_isolation()
    {
        using var disk = new ManagedImageTestStorage();
        await using var h = new MapDraftTestHost(disk.Provider(), withIdentity: true); await h.StartAsync();
        var a = await Login(h, "hotfix-owner-a"); var map = await Start(h);
        var path = $"/api/admin/map-projects/{map.Id}";
        var empty = (await h.Client.GetFromJsonAsync<PublishReadinessDto>(path + "/publish-readiness"))!;
        Assert.Equal(0, empty.SavedNodes); Assert.False(empty.Checks.Single(c => c.Code == "saved_nodes").Passed);
        using (var scope = h.Scope()) {
            Assert.Empty(await scope.ServiceProvider.GetRequiredService<WayMarkDbContext>().MapNodeQrs.ToListAsync());
            Assert.Empty(await scope.ServiceProvider.GetRequiredService<WayMarkDbContext>().FloorMapImageAssets.ToListAsync());
        }
        var floor = map.Content.Floors.Single(); var images = $"/api/admin/floors/{floor.FloorId}/map-drafts";
        (await h.Client.PostAsJsonAsync(images, new MapDraftContent())).EnsureSuccessStatusCode();
        using var file = new ByteArrayContent(ManagedImageTestStorage.Image()); file.Headers.ContentType = new("image/png");
        var uploaded = await h.Client.PostAsync(images + "/images", file); uploaded.EnsureSuccessStatusCode();
        var asset = (await uploaded.Content.ReadFromJsonAsync<MapImageMetadataDto>())!;
        var start = Guid.NewGuid(); var middle = Guid.NewGuid(); var end = Guid.NewGuid();
        var content = map.Content with { Floors = [floor with { Content = new() { ImageAssetId = asset.Id,
            Nodes = [new() { Id = start, NodeCode = "JUNCTION-QR", Name = "Start junction", NodeType = NavigationNodeType.Junction, X = .1m, Y = .5m },
                new() { Id = middle, NodeCode = "MIDDLE", Name = "Corridor", NodeType = NavigationNodeType.Junction, X = .5m, Y = .5m },
                new() { Id = end, NodeCode = "DEST", Name = "Destination", NodeType = NavigationNodeType.Destination, X = .9m, Y = .5m, SearchableAsDestination = true }],
            Edges = [new() { Id = Guid.NewGuid(), FromNodeId = start, ToNodeId = middle, DistanceMeters = 5m },
                new() { Id = Guid.NewGuid(), FromNodeId = middle, ToNodeId = end, DistanceMeters = 7m }] } }] };
        (await h.Client.PutAsJsonAsync(path, new SaveMapProjectRequest(1, map.Name, content))).EnsureSuccessStatusCode();
        var saved = (await h.Client.GetFromJsonAsync<MapProjectDto>(path))!;
        Assert.Equal(2, saved.Version); Assert.Equal(3, saved.Content.Floors[0].Content.Nodes!.Count); Assert.True(saved.CanPublish);
        var request = new CreateNodeQrRequest(saved.Version, floor.Id, start);
        var qrResponse = await h.Client.PostAsJsonAsync(path + "/qrs", request); qrResponse.EnsureSuccessStatusCode();
        var qr = (await qrResponse.Content.ReadFromJsonAsync<NodeQrDto>())!;
        Assert.Equal(start, qr.NodeId); Assert.Null(qr.PublishedVersion);
        var checks = (await h.Client.GetFromJsonAsync<PublishReadinessDto>(path + "/publish-readiness"))!;
        Assert.All(checks.Checks, check => Assert.True(check.Passed, check.Code));
        (await h.Client.PostAsJsonAsync(path + "/publish", new PublishMapRequest(2, true))).EnsureSuccessStatusCode();
        using var guest = h.NewClient();
        Assert.Equal(HttpStatusCode.Unauthorized, (await guest.GetAsync(path)).StatusCode);
        var resolved = (await guest.GetFromJsonAsync<ResolveMapQrDto>("/api/public/qr/" + qr.Payload[6..]))!;
        Assert.Equal(map.Id, resolved.MapId); Assert.Equal(floor.Id, resolved.FloorKey); Assert.Equal(start, resolved.NodeId); Assert.Equal(2, resolved.Version);
        var published = (await guest.GetFromJsonAsync<PublicMapDto>($"/api/public/maps/{map.Id}/versions/2"))!;
        var graph = published.Content.Floors.Single().Content;
        Assert.Equal(asset.Id, graph.ImageAssetId); Assert.Equal(3, graph.Nodes!.Count); Assert.Equal(2, graph.Edges!.Count);
        Assert.Equal(12m, graph.Edges.Sum(e => e.DistanceMeters));
        Assert.Equal((start, middle), (graph.Edges[0].FromNodeId, graph.Edges[0].ToNodeId));
        Assert.Equal((middle, end), (graph.Edges[1].FromNodeId, graph.Edges[1].ToNodeId));
        var downloaded = await guest.GetAsync($"/api/public/maps/{map.Id}/versions/2/images/{asset.Id}");
        Assert.Equal(HttpStatusCode.OK, downloaded.StatusCode);
        (await h.Client.PutAsJsonAsync(path, new SaveMapProjectRequest(2, "Unpublished rename", content))).EnsureSuccessStatusCode();
        Assert.Equal(map.Name, (await guest.GetFromJsonAsync<PublicMapDto>($"/api/public/maps/{map.Id}/versions/2"))!.Name);
        await Login(h, "hotfix-owner-b"); await Start(h);
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.GetAsync(path + "/publish-readiness")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.PostAsJsonAsync(path + "/publish", new PublishMapRequest(3, true))).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.PostAsync(path + $"/qrs/{qr.Id}/revoke", null)).StatusCode);
        h.Client.DefaultRequestHeaders.Authorization = new("Bearer", a);
        (await h.Client.PostAsync(path + $"/qrs/{qr.Id}/revoke", null)).EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Gone, (await guest.GetAsync("/api/public/qr/" + qr.Payload[6..])).StatusCode);
    }
    [Fact]
    public async Task Readiness_reports_disabled_storage_without_creating_files_or_changing_draft()
    {
        using var disk = new ManagedImageTestStorage(); disk.Settings.Enabled = false;
        await using var h = new MapDraftTestHost(disk.Provider(), withIdentity: true); await h.StartAsync();
        await Login(h, "hotfix-storage"); var map = await Start(h);
        var state = (await h.Client.GetFromJsonAsync<PublishReadinessDto>($"/api/admin/map-projects/{map.Id}/publish-readiness"))!;
        Assert.Contains(state.Checks, c => c.Code == "image_storage_unavailable" && !c.Passed);
        Assert.False(Directory.Exists(disk.Settings.RootPath));
        using var scope = h.Scope(); var db = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
        Assert.Empty(await db.FloorMapDrafts.ToListAsync()); Assert.Empty(await db.MapNodeQrs.ToListAsync());
        Assert.Equal(1, (await db.MapProjects.SingleAsync(p => p.Id == map.Id)).Version);
    }
}
