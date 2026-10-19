using WayMark.Api.Models;
using WayMark.Api.Services.Routing;
using Xunit;

namespace WayMark.Api.Tests;

public sealed class RoutingOptionsTests
{
    private readonly DijkstraRouter router = new();
    private static RoutingEdge[] Edges => [
        new(1, 1, 2, 2m, EdgeType: NavigationEdgeType.Stairs),
        new(2, 1, 3, 1m), new(3, 3, 2, 8m, EdgeType: NavigationEdgeType.Elevator)];

    [Fact]
    public void AvoidStairsIsAHardRestrictionAndDoesNotFallBack()
    {
        Assert.Equal(2m, router.FindPath([1, 2, 3], Edges, 1, 2).TotalDistanceMeters);
        var route = router.FindPath([1, 2, 3], Edges, 1, 2, options: new() { AvoidStairs = true });
        Assert.Equal(new[] { 2, 3 }, route.Edges.Select(e => e.Id));
        Assert.Equal(9m, route.TotalDistanceMeters);
        Assert.Equal(PathStatus.NoPath, router.FindPath([1, 2], [Edges[0]], 1, 2,
            options: new() { AvoidStairs = true }).Status);
    }

    [Theory]
    [InlineData("PreferElevators")]
    [InlineData("LessWalking")]
    public void PreferenceUsesSameDijkstraAndReportsActualMeters(string preference)
    {
        var result = router.FindPath([1, 2, 3], Edges, 1, 2, options: new() { Preference = preference });
        Assert.Equal(new[] { 2, 3 }, result.Edges.Select(e => e.Id));
        Assert.Equal(9m, result.TotalDistanceMeters);
        Assert.Equal(PathStatus.NoPath, router.FindPath([1, 2, 3], Edges, 2, 1,
            options: new() { Preference = preference }).Status);
    }

    [Fact]
    public void AccessibleBooleanCannotCertifyWheelchairRouteEvenAtSameNode()
    {
        Assert.Equal(PathStatus.AccessibilityNotVerified, router.FindPath([1, 2],
            [new(1, 1, 2, 1m, IsAccessible: true)], 1, 2, options: new() { Wheelchair = true }).Status);
        Assert.Equal(PathStatus.AccessibilityNotVerified, router.FindPath([1], [], 1, 1,
            options: new() { Wheelchair = true }).Status);
    }
}
