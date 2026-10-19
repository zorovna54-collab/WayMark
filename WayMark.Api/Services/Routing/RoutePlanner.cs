using Microsoft.EntityFrameworkCore;
using WayMark.Api.Contracts;
using WayMark.Api.Data;

namespace WayMark.Api.Services.Routing;

public enum RoutePlanStatus
{
    Success,
    StartWayMarkNotFound,
    DestinationWayMarkNotFound,
    StartNotMapped,
    DestinationNotMapped,
    StartNodeNotFound,
    DestinationNodeNotFound,
    NoRoute,
    AccessibilityNotVerified,
    InvalidGraph
}

public sealed record RoutePlanResult(RoutePlanStatus Status, RouteResponseDto? Route = null);

public interface IRoutePlanner
{
    Task<RoutePlanResult> PlanAsync(string startCode, string destinationCode,
        bool accessibleOnly, CancellationToken cancellationToken, RoutingOptions? options = null);
}

public sealed class RoutePlanner(WayMarkDbContext dbContext, DijkstraRouter router) : IRoutePlanner
{
    public async Task<RoutePlanResult> PlanAsync(string startCode, string destinationCode,
        bool accessibleOnly, CancellationToken cancellationToken, RoutingOptions? options = null)
    {
        // Separate server-side lookups preserve SQL Server's WayMarkCode collation semantics.
        var start = await dbContext.WayMarks.AsNoTracking()
            .SingleOrDefaultAsync(item => item.WayMarkCode == startCode, cancellationToken);
        if (start is null) return new(RoutePlanStatus.StartWayMarkNotFound);
        var destination = await dbContext.WayMarks.AsNoTracking()
            .SingleOrDefaultAsync(item => item.WayMarkCode == destinationCode, cancellationToken);
        if (destination is null) return new(RoutePlanStatus.DestinationWayMarkNotFound);
        if (start.NavigationNodeId is not int startNodeId) return new(RoutePlanStatus.StartNotMapped);
        if (destination.NavigationNodeId is not int destinationNodeId) return new(RoutePlanStatus.DestinationNotMapped);

        // Load all floors, not a single-floor graph: transitions between floors are essential.
        var nodes = await (
            from node in dbContext.NavigationNodes.AsNoTracking()
            join floor in dbContext.Floors.AsNoTracking() on node.FloorId equals floor.Id
            select new RouteNodeDto(node.Id, node.NodeCode, node.Name, node.NodeType.ToString(),
                new FloorDto(floor.Id, floor.BuildingId, floor.Name, floor.FloorCode,
                    floor.SortOrder, floor.FloorPlanImageUrl)))
            .ToListAsync(cancellationToken);
        var nodeById = nodes.ToDictionary(node => node.Id);
        if (!nodeById.ContainsKey(startNodeId)) return new(RoutePlanStatus.StartNodeNotFound);
        if (!nodeById.ContainsKey(destinationNodeId)) return new(RoutePlanStatus.DestinationNodeNotFound);

        var edges = await dbContext.NavigationEdges.AsNoTracking()
            .Where(edge => edge.IsActive && (!accessibleOnly || edge.IsAccessible))
            .ToListAsync(cancellationToken);
        var path = router.FindPath(nodes.Select(node => node.Id).ToArray(),
            edges.Select(edge => new RoutingEdge(edge.Id, edge.FromNodeId, edge.ToNodeId,
                edge.DistanceMeters, edge.IsActive, edge.IsAccessible, edge.EdgeType)).ToArray(),
            startNodeId, destinationNodeId, accessibleOnly, cancellationToken, options);
        if (path.Status != PathStatus.Success)
            return new(path.Status switch
            {
                PathStatus.NoPath => RoutePlanStatus.NoRoute,
                PathStatus.AccessibilityNotVerified => RoutePlanStatus.AccessibilityNotVerified,
                _ => RoutePlanStatus.InvalidGraph
            });

        var edgeById = edges.ToDictionary(edge => edge.Id);
        var orderedEdges = path.Edges.Select((step, index) =>
        {
            var edge = edgeById[step.Id];
            var fromFloorId = nodeById[edge.FromNodeId].Floor.Id;
            var toFloorId = nodeById[edge.ToNodeId].Floor.Id;
            return new RouteEdgeDto(index + 1, edge.Id, edge.FromNodeId, edge.ToNodeId,
                fromFloorId, toFloorId, edge.EdgeType.ToString(), edge.DistanceMeters,
                edge.IsAccessible, fromFloorId == toFloorId ? "SameFloor" : "ChangeFloor");
        }).ToArray();
        return new(RoutePlanStatus.Success, new RouteResponseDto(
            new RoutePointDto(start.Id, start.Name, start.Location, start.WayMarkCode),
            new RoutePointDto(destination.Id, destination.Name, destination.Location, destination.WayMarkCode),
            path.TotalDistanceMeters, accessibleOnly,
            path.NodeIds.Select(id => nodeById[id]).ToArray(), orderedEdges, options ?? new()));
    }
}
