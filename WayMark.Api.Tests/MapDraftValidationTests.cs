using WayMark.Api.Contracts;
using WayMark.Api.Models;
using WayMark.Api.Services.MapDrafts;
using Xunit;

namespace WayMark.Api.Tests;

public sealed class MapDraftValidationTests
{
    private readonly MapDraftValidator validator = new();

    internal static MapDraftContent Content()
    {
        var first = new DraftNodeDto { Id = Guid.NewGuid(), NodeCode = "DRAFT-A", Name = "Door A", NodeType = NavigationNodeType.Entrance, X = .1m, Y = .2m };
        var second = new DraftNodeDto { Id = Guid.NewGuid(), NodeCode = "DRAFT-B", Name = "Door B", NodeType = NavigationNodeType.Entrance, X = .8m, Y = .2m };
        return new MapDraftContent
        {
            Nodes = [first, second],
            Edges = [new DraftEdgeDto { Id = Guid.NewGuid(), FromNodeId = first.Id, ToNodeId = second.Id, DistanceMeters = 15.125m }],
            Places = [new DraftPlaceDto { Id = Guid.NewGuid(), PlaceCode = "EXAM", Name = "Phòng khám", Label = new(.5m, .7m), EntranceNodeIds = [first.Id, second.Id] }]
        };
    }

    [Fact]
    public void RoomHasMultipleEntrancesAndItsLabelIsNotAnImplicitNode()
    {
        var content = Content();
        var result = validator.Validate(content);
        Assert.True(result.IsValid);
        Assert.False(result.ReadyForProduction);
        Assert.Equal(2, content.Places![0].EntranceNodeIds!.Count);
        Assert.DoesNotContain(content.Nodes!, node => node.X == content.Places[0].Label!.X && node.Y == content.Places[0].Label!.Y);
        Assert.All(content.Edges!, edge => Assert.Equal("Unknown", edge.Accessibility));
    }

    [Fact]
    public void EmptyDraftIsStructurallyValidButNeverApprovedForProduction()
    {
        var result = validator.Validate(new());
        Assert.True(result.IsValid);
        Assert.False(result.ReadyForProduction);
        Assert.Contains(result.Warnings, x => x.Code == "image_missing");
    }

    public static IEnumerable<object[]> InvalidDocuments()
    {
        var valid = Content();
        var node = valid.Nodes![0];
        var edge = valid.Edges![0];
        var room = valid.Places![0];
        yield return [valid with { SchemaVersion = 2 }, "schema_version"];
        yield return [valid with { Nodes = null }, "collections_required"];
        yield return [valid with { Nodes = [null!] }, "null_item"];
        yield return [valid with { Nodes = [node, node] }, "duplicate_id"];
        yield return [valid with { Nodes = [node, node with { Id = Guid.NewGuid() }] }, "node_code"];
        yield return [valid with { Nodes = [node with { X = -.001m }] }, "invalid_node"];
        yield return [valid with { Nodes = [node with { Y = 1.001m }] }, "invalid_node"];
        yield return [valid with { Nodes = [node with { NodeType = (NavigationNodeType)99 }] }, "invalid_node"];
        yield return [valid with { Edges = [edge with { ToNodeId = Guid.NewGuid() }] }, "edge_reference"];
        yield return [valid with { Edges = [edge with { ToNodeId = edge.FromNodeId }] }, "edge_reference"];
        yield return [valid with { Edges = [edge, edge] }, "duplicate_id"];
        yield return [valid with { Edges = [edge with { DistanceMeters = 0 }] }, "invalid_edge"];
        yield return [valid with { Edges = [edge with { DistanceMeters = 1.0001m }] }, "invalid_edge"];
        yield return [valid with { Edges = [edge with { Accessibility = "Accessible" }] }, "unverified_claim"];
        yield return [valid with { Edges = [edge with { PassageVerification = "Verified" }] }, "unverified_claim"];
        yield return [valid with { Places = [room with { EntranceNodeIds = [] }] }, "place_entrance"];
        yield return [valid with { Places = [room with { EntranceNodeIds = [Guid.NewGuid()] }] }, "place_entrance"];
        yield return [valid with { Places = [room with { Label = new(2, 0) }] }, "place_label"];
        yield return [valid with { Places = [room, room] }, "duplicate_id"];
        yield return [valid with { Places = [room with { Polygon = [new(0, 0)] }] }, "place_polygon"];
        yield return [valid with { ImageAssetId = Guid.Empty }, "image_id"];
        yield return [valid with { Nodes = Enumerable.Repeat(node, MapDraftValidator.MaxNodes + 1).ToArray() }, "graph_limit"];
    }

    [Theory]
    [MemberData(nameof(InvalidDocuments))]
    public void RejectsInvalidReferencesDuplicatesCoordinatesAndSafetyClaims(MapDraftContent content, string code)
        => Assert.Contains(validator.Validate(content).Errors, issue => issue.Code == code);

    [Fact]
    public void DestinationNodeCannotSubstituteForAnEntrance()
    {
        var content = Content();
        Assert.Contains(validator.Validate(content with
        {
            Nodes = content.Nodes!.Select(n => n with { NodeType = NavigationNodeType.Destination }).ToArray()
        }).Errors, x => x.Code == "place_entrance");
    }

    [Fact]
    public void DirectedReverseEdgesAreIndependentAndMetersAreNotDerivedFromCoordinates()
    {
        var content = Content();
        var edge = content.Edges![0];
        var reverse = edge with { Id = Guid.NewGuid(), FromNodeId = edge.ToNodeId, ToNodeId = edge.FromNodeId, DistanceMeters = 100m };
        Assert.True(validator.Validate(content with { Edges = [edge, reverse] }).IsValid);
        Assert.Equal(15.125m, edge.DistanceMeters);
        Assert.Equal(100m, reverse.DistanceMeters);
    }

    [Theory]
    [InlineData("image/svg+xml", 900, 598, 100, false)]
    [InlineData("text/html", 900, 598, 100, false)]
    [InlineData("image/png", 0, 598, 100, false)]
    [InlineData("image/jpeg", 9000, 598, 100, false)]
    [InlineData("image/png", 8192, 8192, 100, false)]
    [InlineData("image/png", 900, 598, 10485761, false)]
    [InlineData("image/png", 900, 598, 100, true)]
    [InlineData("image/jpeg", 900, 598, 100, true)]
    public void StorageMetadataHasStrictMimeDimensionAndSizeLimits(string mime, int width, int height, long bytes, bool valid)
    {
        var id = Guid.NewGuid();
        Assert.Equal(valid, MapImageRules.Metadata(new(id.ToString("N"), mime, width, height, bytes, new string('a', 64)), id));
    }

    [Fact]
    public void StorageKeysCannotBePathsUrlsOrArbitraryImageReferences()
    {
        var id = Guid.NewGuid();
        foreach (var key in new[] { "../../appsettings.json", "C:\\temp\\file.png", "https://host/image.png", "file.png" })
            Assert.False(MapImageRules.Metadata(new(key, "image/png", 900, 598, 100, new string('a', 64)), id));
    }
}
