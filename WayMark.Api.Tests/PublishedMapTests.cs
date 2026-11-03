using System.Net;
using System.Net.Http.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using WayMark.Api.Contracts;
using WayMark.Api.Data;
using WayMark.Api.Models;
using Xunit;

namespace WayMark.Api.Tests;

public sealed class PublishedMapTests
{
    [Fact]
    public async Task Renamed_node_keeps_stable_qr_identity_and_only_selected_nodes_need_qr()
    {
        using var disk = new ManagedImageTestStorage();
        await using var h = new MapDraftTestHost(disk.Provider()); await h.StartAsync();
        var p = await Create(h, await Fixture(h)); var oldQr = await Qr(h, p);
        (await h.Client.PostAsJsonAsync($"/api/admin/map-projects/{p.Id}/publish", new PublishMapRequest(1, true))).EnsureSuccessStatusCode();
        var first = p.Content.Floors[0]; var node = first.Content.Nodes![0];
        var renamed = p.Content with { Floors = p.Content.Floors.Select(f => f.Id == first.Id
            ? f with { Content = f.Content with { Nodes = f.Content.Nodes!.Select(n => n.Id == node.Id
                ? n with { Name = "Renamed entrance", NodeCode = "LABEL-CHANGED" } : n).Reverse().ToArray() } } : f).ToArray() };
        var response = await h.Client.PutAsJsonAsync($"/api/admin/map-projects/{p.Id}", new SaveMapProjectRequest(1, p.Name, renamed));
        response.EnsureSuccessStatusCode();
        var saved = (await response.Content.ReadFromJsonAsync<MapProjectDto>())!;
        var newQr = await (await h.Client.PostAsJsonAsync($"/api/admin/map-projects/{p.Id}/qrs",
            new CreateNodeQrRequest(saved.Version, first.Id, node.Id))).Content.ReadFromJsonAsync<NodeQrDto>();
        (await h.Client.PostAsJsonAsync($"/api/admin/map-projects/{p.Id}/publish", new PublishMapRequest(saved.Version, true))).EnsureSuccessStatusCode();
        Assert.NotEqual(oldQr.Payload, newQr!.Payload);
        h.Token("missing");
        var oldResolve = await h.Client.GetFromJsonAsync<ResolveMapQrDto>("/api/public/qr/" + oldQr.Payload[6..]);
        var newResolve = await h.Client.GetFromJsonAsync<ResolveMapQrDto>("/api/public/qr/" + newQr.Payload[6..]);
        Assert.Equal(node.Id, oldResolve!.NodeId); Assert.Equal(node.Id, newResolve!.NodeId);
        Assert.Equal(first.Id, newResolve.FloorKey);
        Assert.Equal(1, oldResolve.Version); Assert.Equal(2, newResolve.Version);
        using var scope = h.Scope();
        var qrs = await scope.ServiceProvider.GetRequiredService<WayMarkDbContext>().MapNodeQrs.ToListAsync();
        Assert.Equal(2, qrs.Count); // Four nodes per version, only this selected node has QR.
    }

    [Fact]
    public async Task Identical_create_and_save_are_idempotent_and_sqlite_file_survives_restart()
    {
        using var disk = new ManagedImageTestStorage();
        Guid mapId; string payload;
        await using (var h = new MapDraftTestHost(disk.Provider(), sqlitePath: disk.DatabasePath))
        {
            await h.StartAsync(); var c = await Fixture(h); var p = await Create(h, c);
            Assert.Equal(p.Id, (await Create(h, c)).Id);
            var same = await (await h.Client.PutAsJsonAsync($"/api/admin/map-projects/{p.Id}", new SaveMapProjectRequest(1, p.Name, c))).Content.ReadFromJsonAsync<MapProjectDto>();
            Assert.Equal(1, same!.Version);
            var qr = await Qr(h, p); payload = qr.Payload; mapId = p.Id;
            (await h.Client.PostAsJsonAsync($"/api/admin/map-projects/{p.Id}/publish", new PublishMapRequest(1, true))).EnsureSuccessStatusCode();
        }
        await using (var reopened = new MapDraftTestHost(disk.Provider(), sqlitePath: disk.DatabasePath))
        {
            await reopened.StartAsync(); reopened.Token("missing");
            var q = await reopened.Client.GetFromJsonAsync<ResolveMapQrDto>("/api/public/qr/" + payload[6..]);
            Assert.Equal(mapId, q!.MapId);
            var doc = await reopened.Client.GetFromJsonAsync<PublicMapDto>($"/api/public/maps/{mapId}/versions/1");
            var asset = doc!.Content.Floors[0].Content.ImageAssetId;
            var image = await reopened.Client.GetAsync($"/api/public/maps/{mapId}/versions/1/images/{asset}");
            Assert.Equal(HttpStatusCode.OK, image.StatusCode); Assert.Equal(ManagedImageTestStorage.Image(), await image.Content.ReadAsByteArrayAsync());
        }
    }

    internal static async Task<ProjectContentDto> Fixture(MapDraftTestHost h)
    {
        var floors = new List<ProjectFloorDto>();
        foreach (var floorId in new[] { 10, 11 })
        {
            var prefix = $"/api/admin/floors/{floorId}/map-drafts";
            (await h.Client.PostAsJsonAsync(prefix, new MapDraftContent())).EnsureSuccessStatusCode();
            using var body = new ByteArrayContent(ManagedImageTestStorage.Image());
            body.Headers.ContentType = new("image/png");
            var image = await (await h.Client.PostAsync(prefix + "/images", body)).Content.ReadFromJsonAsync<MapImageMetadataDto>();
            Assert.NotNull(image);
            var stair = Guid.NewGuid(); var end = Guid.NewGuid();
            var nodes = new[] {
                new DraftNodeDto { Id = end, NodeCode = floorId == 10 ? "START" : "DEST", Name = floorId == 10 ? "Entrance G" : "Clinic 1",
                    X = .1m, Y = .5m, NodeType = NavigationNodeType.Entrance, SearchableAsDestination = floorId == 11,
                    DisplayName = floorId == 11 ? "Clinic destination" : null, LandmarkNote = "Test blue sign" },
                new DraftNodeDto { Id = stair, NodeCode = "STAIR", Name = "Stair", X = .8m, Y = .5m, NodeType = NavigationNodeType.Stairs } };
            var edge = floorId == 10 ? (end, stair) : (stair, end);
            floors.Add(new(Guid.NewGuid(), floorId, floorId == 10 ? "Ground" : "Level 1", floorId == 10 ? "G" : "L1",
                new() { ImageAssetId = image.Id, Nodes = nodes,
                    Edges = [new() { Id = Guid.NewGuid(), FromNodeId = edge.Item1, ToNodeId = edge.Item2,
                        DistanceMeters = 5, EdgeType = NavigationEdgeType.Corridor }] }));
        }
        return new(Guid.NewGuid(), floors, [new(Guid.NewGuid(), floors[0].Id, floors[0].Content.Nodes![1].Id,
            floors[1].Id, floors[1].Content.Nodes![1].Id, 3m, "Stairs")]);
    }
    internal static async Task<MapProjectDto> Create(MapDraftTestHost h, ProjectContentDto content)
    {
        var response = await h.Client.PostAsJsonAsync("/api/admin/map-projects", new CreateMapProjectRequest("Fixture map", content));
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return (await response.Content.ReadFromJsonAsync<MapProjectDto>())!;
    }
    internal static async Task<NodeQrDto> Qr(MapDraftTestHost h, MapProjectDto p) =>
        (await (await h.Client.PostAsJsonAsync($"/api/admin/map-projects/{p.Id}/qrs",
            new CreateNodeQrRequest(p.Version, p.Content.Floors[0].Id, p.Content.Floors[0].Content.Nodes![0].Id)))
            .Content.ReadFromJsonAsync<NodeQrDto>())!;

    [Fact]
    public async Task Zero_room_multifloor_save_publish_guest_resolve_download_and_revoke()
    {
        using var disk = new ManagedImageTestStorage();
        await using var h = new MapDraftTestHost(disk.Provider()); await h.StartAsync();
        var p = await Create(h, await Fixture(h));
        var qr = await Qr(h, p);
        Assert.Matches("^WMQR1:[a-f0-9]{64}$", qr.Payload);
        Assert.Equal(qr.Id, (await Qr(h, p)).Id); // Idempotent per saved version/node.
        h.Token("missing");
        Assert.Equal(HttpStatusCode.Unauthorized, (await h.Client.GetAsync($"/api/admin/map-projects/{p.Id}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await h.Client.GetAsync($"/api/public/maps/{p.Id}/versions/1")).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await h.Client.GetAsync("/api/public/qr/" + qr.Payload[6..])).StatusCode);
        h.Token();
        var pub = await h.Client.PostAsJsonAsync($"/api/admin/map-projects/{p.Id}/publish", new PublishMapRequest(1, true));
        Assert.Equal(HttpStatusCode.OK, pub.StatusCode);
        h.Token("missing");
        var resolved = await h.Client.GetFromJsonAsync<ResolveMapQrDto>("/api/public/qr/" + qr.Payload[6..]);
        Assert.Equal(p.Id, resolved!.MapId); Assert.Equal(p.Content.Floors[0].Content.Nodes![0].Id, resolved.NodeId);
        var snapshot = await h.Client.GetFromJsonAsync<PublicMapDto>($"/api/public/maps/{p.Id}/versions/1");
        Assert.False(snapshot!.VerifiedForPatientUse);
        Assert.Equal(2, snapshot.Content.Floors.Count); Assert.Single(snapshot.Content.Links);
        Assert.All(snapshot.Content.Floors, f => Assert.Empty(f.Content.Places!));
        Assert.Equal("Clinic destination", snapshot.Content.Floors[1].Content.Nodes![0].DisplayName);
        Assert.True(snapshot.Content.Floors[1].Content.Nodes![0].SearchableAsDestination);
        var asset = p.Content.Floors[0].Content.ImageAssetId;
        var image = await h.Client.GetAsync($"/api/public/maps/{p.Id}/versions/1/images/{asset}");
        Assert.Equal(HttpStatusCode.OK, image.StatusCode);
        Assert.Equal("image/png", image.Content.Headers.ContentType!.MediaType);
        Assert.Equal(ManagedImageTestStorage.Image(), await image.Content.ReadAsByteArrayAsync());
        Assert.Equal(HttpStatusCode.NotFound, (await h.Client.GetAsync($"/api/public/maps/{p.Id}/versions/1/images/{Guid.NewGuid()}")).StatusCode);
        h.Token();
        (await h.Client.PostAsync($"/api/admin/map-projects/{p.Id}/qrs/{qr.Id}/revoke", null)).EnsureSuccessStatusCode();
        h.Token("missing");
        Assert.Equal(HttpStatusCode.Gone, (await h.Client.GetAsync("/api/public/qr/" + qr.Payload[6..])).StatusCode);
        using var scope = h.Scope(); var db = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
        Assert.Equal(2, await db.NavigationNodes.CountAsync()); Assert.Equal(1, await db.NavigationEdges.CountAsync()); // Production fixture untouched.
    }

    [Theory]
    [InlineData("missing", "admin-a", HttpStatusCode.Unauthorized)]
    [InlineData("user", "admin-a", HttpStatusCode.Forbidden)]
    [InlineData("forged-role", "admin-a", HttpStatusCode.Unauthorized)]
    [InlineData("expired", "admin-a", HttpStatusCode.Unauthorized)]
    [InlineData("bad-signature", "admin-a", HttpStatusCode.Unauthorized)]
    [InlineData("admin", "admin-b", HttpStatusCode.Forbidden)]
    [InlineData("admin", "inactive", HttpStatusCode.Forbidden)]
    public async Task Unauthorized_requests_cannot_modify_publish_or_create_qr(string kind, string user, HttpStatusCode status)
    {
        using var disk = new ManagedImageTestStorage(); await using var h = new MapDraftTestHost(disk.Provider()); await h.StartAsync();
        var p = await Create(h, await Fixture(h)); var qr = await Qr(h, p);
        h.Token(kind, user);
        Assert.Equal(status, (await h.Client.GetAsync($"/api/admin/map-projects/{p.Id}")).StatusCode);
        Assert.Equal(status, (await h.Client.PutAsJsonAsync($"/api/admin/map-projects/{p.Id}", new SaveMapProjectRequest(1, "hacked", p.Content))).StatusCode);
        Assert.Equal(status, (await h.Client.PostAsJsonAsync($"/api/admin/map-projects/{p.Id}/publish", new PublishMapRequest(1, true))).StatusCode);
        Assert.Equal(status, (await h.Client.PostAsJsonAsync($"/api/admin/map-projects/{p.Id}/qrs", new CreateNodeQrRequest(1, p.Content.Floors[0].Id, p.Content.Floors[0].Content.Nodes![0].Id))).StatusCode);
        Assert.Equal(status, (await h.Client.PostAsync($"/api/admin/map-projects/{p.Id}/qrs/{qr.Id}/revoke", null)).StatusCode);
        using var scope = h.Scope(); var db = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
        Assert.Equal("Fixture map", (await db.MapProjects.SingleAsync()).Name); Assert.Empty(await db.MapPublications.ToListAsync());
        Assert.True((await db.MapNodeQrs.SingleAsync()).IsActive);
    }
    [Fact]
    public async Task Same_site_membership_is_not_ownership_and_revocation_removes_owner_access()
    {
        using var disk = new ManagedImageTestStorage(); await using var h = new MapDraftTestHost(disk.Provider()); await h.StartAsync();
        var p = await Create(h, await Fixture(h));
        using (var scope = h.Scope()) {
            var db = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
            db.SiteMapMemberships.Add(new() { SiteId = 1, UserId = "other-owner", IsActive = true, CanEditDrafts = true }); await db.SaveChangesAsync();
        }
        h.Token("admin", "other-owner");
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.GetAsync($"/api/admin/map-projects/{p.Id}")).StatusCode);
        Assert.Empty((await h.Client.GetFromJsonAsync<List<MapProjectDto>>("/api/admin/map-projects"))!);
        h.Token("admin", "no-edit");
        Assert.Equal(HttpStatusCode.Forbidden, (await h.Client.PostAsJsonAsync("/api/admin/map-projects", new CreateMapProjectRequest("Denied", p.Content))).StatusCode);
    }
    [Fact]
    public async Task New_draft_version_never_changes_publication_or_old_qr_binding()
    {
        using var disk = new ManagedImageTestStorage(); await using var h = new MapDraftTestHost(disk.Provider()); await h.StartAsync();
        var p = await Create(h, await Fixture(h)); var qr = await Qr(h, p);
        (await h.Client.PostAsJsonAsync($"/api/admin/map-projects/{p.Id}/publish", new PublishMapRequest(1, true))).EnsureSuccessStatusCode();
        var update = await h.Client.PutAsJsonAsync($"/api/admin/map-projects/{p.Id}", new SaveMapProjectRequest(1, "New private name", p.Content));
        Assert.Equal(2, (await update.Content.ReadFromJsonAsync<MapProjectDto>())!.Version);
        Assert.Equal(HttpStatusCode.Conflict, (await h.Client.PutAsJsonAsync($"/api/admin/map-projects/{p.Id}", new SaveMapProjectRequest(1, "stale", p.Content))).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await h.Client.PostAsJsonAsync($"/api/admin/map-projects/{p.Id}/publish", new PublishMapRequest(2, true))).StatusCode); // Need a QR pinned to v2.
        h.Token("missing");
        var old = await h.Client.GetFromJsonAsync<PublicMapDto>($"/api/public/maps/{p.Id}/versions/1");
        Assert.Equal("Fixture map", old!.Name);
        Assert.Equal(1, (await h.Client.GetFromJsonAsync<ResolveMapQrDto>("/api/public/qr/" + qr.Payload[6..]))!.Version);
    }
    [Theory]
    [InlineData("no-qr")]
    [InlineData("no-path")]
    [InlineData("missing-meters")]
    [InlineData("no-destination")]
    [InlineData("no-public-consent")]
    public async Task Publication_requires_valid_directed_graph_qr_and_explicit_consent(string fault)
    {
        using var disk = new ManagedImageTestStorage(); await using var h = new MapDraftTestHost(disk.Provider()); await h.StartAsync();
        var c = await Fixture(h);
        if (fault == "no-path") c = c with { Links = [] };
        if (fault == "missing-meters") c = c with { Floors = c.Floors.Select(f => f with { Content = f.Content with { Edges = f.Content.Edges!.Select(e => e with { DistanceMeters = null }).ToArray() } }).ToArray() };
        if (fault == "no-destination") c = c with { Floors = c.Floors.Select(f => f with { Content = f.Content with { Nodes = f.Content.Nodes!.Select(n => n with { SearchableAsDestination = false }).ToArray() } }).ToArray() };
        var p = await Create(h, c);
        if (fault != "no-qr") await Qr(h, p);
        Assert.Equal(HttpStatusCode.BadRequest, (await h.Client.PostAsJsonAsync($"/api/admin/map-projects/{p.Id}/publish", new PublishMapRequest(1, fault != "no-public-consent"))).StatusCode);
        using var scope = h.Scope(); Assert.Empty(await scope.ServiceProvider.GetRequiredService<WayMarkDbContext>().MapPublications.ToListAsync());
    }
    [Fact]
    public async Task Cross_site_assets_nodes_and_transitions_rejected_before_project_write()
    {
        using var disk = new ManagedImageTestStorage(); await using var h = new MapDraftTestHost(disk.Provider()); await h.StartAsync();
        var c = await Fixture(h);
        foreach (var invalid in new[] {
            c with { Floors = [c.Floors[0] with { FloorId = 20 }] },
            c with { Links = [c.Links[0] with { ToFloor = c.Floors[0].Id }] },
            c with { Floors = [c.Floors[0] with { Content = c.Floors[0].Content with { ImageAssetId = c.Floors[1].Content.ImageAssetId } }] }
        }) {
            var response = await h.Client.PostAsJsonAsync("/api/admin/map-projects", new CreateMapProjectRequest("Denied", invalid));
            Assert.Contains(response.StatusCode, new[] { HttpStatusCode.BadRequest, HttpStatusCode.Forbidden });
        }
        using var scope = h.Scope(); Assert.Empty(await scope.ServiceProvider.GetRequiredService<WayMarkDbContext>().MapProjects.ToListAsync());
    }
}
