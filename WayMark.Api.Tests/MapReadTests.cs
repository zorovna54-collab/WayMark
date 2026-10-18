using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using WayMark.Api.Contracts;
using WayMark.Api.Controllers;
using WayMark.Api.Data;
using WayMark.Api.Models;
using Xunit;
using WayMarkEntity = WayMark.Api.Models.WayMark;

namespace WayMark.Api.Tests;

public sealed class MapReadTests : IDisposable
{
    private readonly WayMarkDbContext db = new(new DbContextOptionsBuilder<WayMarkDbContext>()
        .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);

    public MapReadTests()
    {
        db.Sites.AddRange(
            new Site { Id = 1, Code = "A", Name = "Site A" },
            new Site { Id = 2, Code = "B", Name = "Site B" },
            new Site { Id = 3, Code = "C", Name = "Empty site" });
        db.Buildings.AddRange(
            new Building { Id = 10, SiteId = 1, BuildingCode = "A", Name = "Building A" },
            new Building { Id = 11, SiteId = 1, BuildingCode = "B", Name = "Building B" },
            new Building { Id = 20, SiteId = 2, BuildingCode = "A", Name = "Other building" });
        db.Floors.AddRange(
            new Floor { Id = 101, BuildingId = 10, FloorCode = "L1", SortOrder = 1, Name = "Level 1" },
            new Floor { Id = 100, BuildingId = 10, FloorCode = "G", SortOrder = 0, Name = "Ground" },
            new Floor { Id = 102, BuildingId = 20, FloorCode = "G", Name = "Other floor" },
            new Floor { Id = 103, BuildingId = 11, FloorCode = "G", Name = "Empty floor" });
        db.NavigationNodes.AddRange(
            Node(1, 100, NavigationNodeType.Entrance), Node(2, 100, NavigationNodeType.Junction),
            Node(3, 101, NavigationNodeType.Elevator), Node(4, 102), Node(5, 102));
        db.NavigationEdges.AddRange(
            Edge(1, 1, 2), Edge(2, 2, 1, false), Edge(3, 2, 3), Edge(4, 3, 1), Edge(5, 4, 5));
        db.WayMarks.AddRange(
            new WayMarkEntity { Id = 1, Name = "Entrance", Location = "Ground", WayMarkCode = "QR-1", NavigationNodeId = 1 },
            new WayMarkEntity { Id = 2, Name = "Unmapped", Location = "Unknown", WayMarkCode = "QR-2" });
        db.SaveChanges();
        db.ChangeTracker.Clear();
    }

    [Fact]
    public async Task SitesReturnDtosInCodeOrder()
    {
        var sites = Value<IReadOnlyList<SiteDto>>((await Maps().GetSites(default)).Result);
        Assert.Equal(new[] { "A", "B", "C" }, sites.Select(site => site.Code));
    }

    [Fact]
    public async Task BuildingsAreScopedToSiteAndExistingEmptySiteReturnsEmptyList()
    {
        var buildings = Value<IReadOnlyList<BuildingDto>>((await Maps().GetBuildings(1, default)).Result);
        Assert.Equal(new[] { 10, 11 }, buildings.Select(building => building.Id));
        Assert.Empty(Value<IReadOnlyList<BuildingDto>>((await Maps().GetBuildings(3, default)).Result));
        Assert.IsType<NotFoundObjectResult>((await Maps().GetBuildings(999, default)).Result);
    }

    [Fact]
    public async Task FloorsAreScopedToBuildingAndSorted()
    {
        var floors = Value<IReadOnlyList<FloorDto>>((await Maps().GetFloors(10, default)).Result);
        Assert.Equal(new[] { 100, 101 }, floors.Select(floor => floor.Id));
        Assert.IsType<NotFoundObjectResult>((await Maps().GetFloors(999, default)).Result);
    }

    [Fact]
    public async Task GraphIncludesOnlyEdgesWithBothEndpointsOnFloor()
    {
        var graph = Value<FloorGraphDto>((await Maps().GetFloorGraph(100, default)).Result);
        Assert.Equal(100, graph.Floor.Id);
        Assert.Equal(new[] { 1, 2 }, graph.Nodes.Select(node => node.Id));
        // Excludes outgoing/incoming cross-floor transitions and unrelated-floor edges.
        Assert.Equal(new[] { 1, 2 }, graph.Edges.Select(edge => edge.Id));
        Assert.All(graph.Edges, edge =>
        {
            Assert.Contains(graph.Nodes, node => node.Id == edge.FromNodeId);
            Assert.Contains(graph.Nodes, node => node.Id == edge.ToNodeId);
        });
        Assert.False(graph.Edges.Single(edge => edge.Id == 2).IsActive);
        Assert.Equal("Entrance", graph.Nodes.Single(node => node.Id == 1).NodeType);
    }

    [Fact]
    public async Task MissingFloorReturns404AndExistingEmptyFloorReturns200()
    {
        Assert.IsType<NotFoundObjectResult>((await Maps().GetFloorGraph(999, default)).Result);
        var graph = Value<FloorGraphDto>((await Maps().GetFloorGraph(103, default)).Result);
        Assert.Empty(graph.Nodes);
        Assert.Empty(graph.Edges);
    }

    [Fact]
    public async Task WayMarkReturnsLinkedNodeOrNullWithoutChangingExistingEndpoint()
    {
        var controller = new WayMarksController(db);
        var linked = Value<WayMarkMapDto>((await controller.GetMapLocation("QR-1", default)).Result);
        Assert.Equal(1, linked.Node!.Id);
        Assert.Equal(100, linked.Node.FloorId);
        var unlinked = Value<WayMarkMapDto>((await controller.GetMapLocation("QR-2", default)).Result);
        Assert.Null(unlinked.Node);
        Assert.IsType<NotFoundObjectResult>((await controller.GetMapLocation("unknown", default)).Result);
        var original = Value<WayMarkEntity>((await controller.GetByCode("QR-1")).Result);
        Assert.Equal(linked.WayMarkCode, original.WayMarkCode);
    }

    [Fact]
    public async Task DtoSerializesWithWebPropertyNamesAndReadsDoNotTrackEntities()
    {
        var graph = Value<FloorGraphDto>((await Maps().GetFloorGraph(100, default)).Result);
        using var json = JsonDocument.Parse(JsonSerializer.Serialize(graph, new JsonSerializerOptions(JsonSerializerDefaults.Web)));
        Assert.Equal("Entrance", json.RootElement.GetProperty("nodes")[0].GetProperty("nodeType").GetString());
        await new WayMarksController(db).GetMapLocation("QR-1", default);
        Assert.Empty(db.ChangeTracker.Entries());
    }

    [Theory]
    [InlineData(typeof(MapsController))]
    [InlineData(typeof(WayMarksController))]
    public void MapEndpointsRequireAuthentication(Type controller)
    {
        Assert.NotNull(Attribute.GetCustomAttribute(controller, typeof(AuthorizeAttribute)));
        Assert.DoesNotContain(controller.GetMethods(), method => Attribute.IsDefined(method, typeof(AllowAnonymousAttribute)));
    }

    private MapsController Maps() => new(db);
    private static T Value<T>(IActionResult? result) => Assert.IsAssignableFrom<T>(Assert.IsType<OkObjectResult>(result).Value);
    private static NavigationNode Node(int id, int floorId, NavigationNodeType type = NavigationNodeType.Junction) =>
        new() { Id = id, FloorId = floorId, NodeCode = $"NODE-{id}", Name = $"Node {id}", X = .25m, Y = .75m, NodeType = type };
    private static NavigationEdge Edge(int id, int from, int to, bool active = true) =>
        new() { Id = id, FromNodeId = from, ToNodeId = to, DistanceMeters = 5m, EdgeType = NavigationEdgeType.Corridor, IsActive = active, IsAccessible = true };
    public void Dispose() => db.Dispose();
}
