using WayMark.Api.Services.Routing;
using Xunit;

namespace WayMark.Api.Tests;

public sealed class DijkstraRouterTests
{
    private readonly DijkstraRouter router = new();

    [Fact]
    public void DirectedEdgeDoesNotImplyReverseEdge()
    {
        RoutingEdge[] edges = [new(1, 1, 2, 5m)];
        Assert.Equal(PathStatus.Success, router.FindPath([1, 2], edges, 1, 2).Status);
        Assert.Equal(PathStatus.NoPath, router.FindPath([1, 2], edges, 2, 1).Status);
    }

    [Fact]
    public void ShortestRouteMayHaveMoreEdgesThanAlternative()
    {
        var path = router.FindPath([1, 2, 3, 4],
            [new(1, 1, 4, 20m), new(2, 1, 2, 2m), new(3, 2, 3, 2m), new(4, 3, 4, 2m)], 1, 4);
        Assert.Equal(PathStatus.Success, path.Status);
        Assert.Equal(6m, path.TotalDistanceMeters);
        Assert.Equal(new[] { 1, 2, 3, 4 }, path.NodeIds);
        Assert.Equal(new[] { 2, 3, 4 }, path.Edges.Select(edge => edge.Id));
    }

    [Fact]
    public void CyclesAndStaleQueueEntriesDoNotPreventShortestPath()
    {
        var path = router.FindPath([1, 2, 3, 4],
            [new(1, 1, 2, 10m), new(2, 1, 3, 1m), new(3, 3, 2, 1m),
             new(4, 2, 4, 1m), new(5, 3, 4, 5m), new(6, 2, 1, 1m)], 1, 4);
        Assert.Equal(3m, path.TotalDistanceMeters);
        Assert.Equal(new[] { 1, 3, 2, 4 }, path.NodeIds);
    }

    [Fact]
    public void PathCanCrossBetweenFloorsWithoutInventingExtraConnections()
    {
        var floors = new Dictionary<int, int> { [1] = 10, [2] = 10, [3] = 20, [4] = 20 };
        var path = router.FindPath(floors.Keys.ToArray(),
            [new(1, 1, 2, 8m), new(2, 2, 3, 4m), new(3, 3, 4, 6m)], 1, 4);
        Assert.Equal(PathStatus.Success, path.Status);
        Assert.Equal(18m, path.TotalDistanceMeters);
        var transition = path.Edges.Single(edge => floors[edge.FromNodeId] != floors[edge.ToNodeId]);
        Assert.Equal(2, transition.Id);
        Assert.Equal(PathStatus.NoPath, router.FindPath(floors.Keys.ToArray(),
            [new(1, 1, 2, 8m), new(3, 3, 4, 6m)], 1, 4).Status);
    }

    [Fact]
    public void InactiveShortcutIsNotUsed()
    {
        var path = router.FindPath([1, 2, 3],
            [new(1, 1, 3, 1m, IsActive: false), new(2, 1, 2, 3m), new(3, 2, 3, 4m)], 1, 3);
        Assert.Equal(7m, path.TotalDistanceMeters);
        Assert.Equal(new[] { 2, 3 }, path.Edges.Select(edge => edge.Id));
    }

    [Fact]
    public void IsolatedNodeHasNoRoute()
    {
        Assert.Equal(PathStatus.NoPath, router.FindPath([1, 2, 3], [new(1, 1, 2, 1m)], 1, 3).Status);
        Assert.Equal(PathStatus.NoPath, router.FindPath([1, 2], [], 1, 2).Status);
    }

    [Fact]
    public void SameExistingNodeHasZeroDistanceAndNoEdges()
    {
        var path = router.FindPath([1], [], 1, 1);
        Assert.Equal(PathStatus.Success, path.Status);
        Assert.Equal(0m, path.TotalDistanceMeters);
        Assert.Equal(new[] { 1 }, path.NodeIds);
        Assert.Empty(path.Edges);
    }

    [Fact]
    public void EmptyGraphAndMissingEndpointsAreDistinguished()
    {
        Assert.Equal(PathStatus.StartNodeNotFound, router.FindPath([], [], 1, 1).Status);
        Assert.Equal(PathStatus.StartNodeNotFound, router.FindPath([2], [], 1, 2).Status);
        Assert.Equal(PathStatus.DestinationNodeNotFound, router.FindPath([1], [], 1, 2).Status);
    }

    [Fact]
    public void DecimalDistancesAreSummedExactly()
    {
        var path = router.FindPath([1, 2, 3],
            [new(1, 1, 2, .1m), new(2, 2, 3, .2m), new(3, 1, 3, .301m)], 1, 3);
        Assert.Equal(.3m, path.TotalDistanceMeters);
        Assert.Equal(new[] { 1, 2 }, path.Edges.Select(edge => edge.Id));
    }

    [Fact]
    public void ParallelEdgesChooseTheCheapestAndPreserveItsId()
    {
        var path = router.FindPath([1, 2], [new(1, 1, 2, 10m), new(2, 1, 2, 2m)], 1, 2);
        Assert.Equal(2, Assert.Single(path.Edges).Id);
    }

    [Fact]
    public void AccessibilityIsOnlyFilteredWhenExplicitlyRequested()
    {
        RoutingEdge[] edges = [new(1, 1, 2, 1m, IsAccessible: false), new(2, 1, 2, 5m, IsAccessible: true)];
        Assert.Equal(1m, router.FindPath([1, 2], edges, 1, 2).TotalDistanceMeters);
        Assert.Equal(5m, router.FindPath([1, 2], edges, 1, 2, accessibleOnly: true).TotalDistanceMeters);
        Assert.Equal(PathStatus.NoPath, router.FindPath([1, 2], [edges[0]], 1, 2, accessibleOnly: true).Status);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    public void InvalidActiveWeightsAreRejected(int distance)
    {
        Assert.Equal(PathStatus.InvalidGraph, router.FindPath([1, 2], [new(1, 1, 2, distance)], 1, 2).Status);
    }

    [Fact]
    public void DanglingEdgesAndDecimalOverflowAreRejected()
    {
        Assert.Equal(PathStatus.InvalidGraph, router.FindPath([1, 2], [new(1, 1, 99, 1m)], 1, 2).Status);
        Assert.Equal(PathStatus.InvalidGraph, router.FindPath([1, 2, 3],
            [new(1, 1, 2, decimal.MaxValue), new(2, 2, 3, 1m)], 1, 3).Status);
    }

    [Fact]
    public void CancellationStopsCalculation()
    {
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        Assert.Throws<OperationCanceledException>(() => router.FindPath([1, 2],
            [new(1, 1, 2, 1m)], 1, 2, cancellationToken: cancellation.Token));
    }
}
