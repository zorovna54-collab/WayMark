namespace WayMark.Api.Services.Routing;

public sealed record RoutingEdge(
    int Id, int FromNodeId, int ToNodeId, decimal DistanceMeters,
    bool IsActive = true, bool IsAccessible = false);

public enum PathStatus
{
    Success,
    StartNodeNotFound,
    DestinationNodeNotFound,
    NoPath,
    InvalidGraph
}

public sealed record PathResult(
    PathStatus Status, decimal TotalDistanceMeters,
    IReadOnlyList<int> NodeIds, IReadOnlyList<RoutingEdge> Edges);

/// <summary>Directed shortest path using stored distances only; no EF or coordinates.</summary>
public sealed class DijkstraRouter
{
    public PathResult FindPath(
        IReadOnlyCollection<int> nodeIds, IReadOnlyCollection<RoutingEdge> edges,
        int startNodeId, int destinationNodeId, bool accessibleOnly = false,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var nodes = nodeIds.ToHashSet();
        if (!nodes.Contains(startNodeId)) return Failure(PathStatus.StartNodeNotFound);
        if (!nodes.Contains(destinationNodeId)) return Failure(PathStatus.DestinationNodeNotFound);
        if (nodes.Count != nodeIds.Count) return Failure(PathStatus.InvalidGraph);
        if (startNodeId == destinationNodeId)
            return new(PathStatus.Success, 0m, [startNodeId], []);

        var outgoing = new Dictionary<int, List<RoutingEdge>>();
        var edgeIds = new HashSet<int>();
        // IsAccessible means an explicitly marked, accessible passage in map data.
        // It is not a complete wheelchair suitability assessment.
        foreach (var edge in edges.OrderBy(edge => edge.Id))
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!edge.IsActive || (accessibleOnly && !edge.IsAccessible)) continue;
            if (edge.DistanceMeters <= 0 || edge.FromNodeId == edge.ToNodeId
                || !nodes.Contains(edge.FromNodeId) || !nodes.Contains(edge.ToNodeId)
                || !edgeIds.Add(edge.Id))
                return Failure(PathStatus.InvalidGraph);
            if (!outgoing.TryGetValue(edge.FromNodeId, out var adjacent))
                outgoing[edge.FromNodeId] = adjacent = [];
            adjacent.Add(edge);
        }

        var distances = new Dictionary<int, decimal> { [startNodeId] = 0m };
        var previous = new Dictionary<int, RoutingEdge>();
        var settled = new HashSet<int>();
        // Node ID breaks distance ties deterministically; edge ID orders parallel edges.
        var queue = new PriorityQueue<int, (decimal Distance, int NodeId)>();
        queue.Enqueue(startNodeId, (0m, startNodeId));
        while (queue.TryDequeue(out var current, out var priority))
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (priority.Distance != distances[current] || !settled.Add(current)) continue;
            if (current == destinationNodeId)
            {
                var pathNodes = new List<int> { current };
                var pathEdges = new List<RoutingEdge>();
                while (current != startNodeId)
                {
                    if (pathEdges.Count >= nodes.Count || !previous.TryGetValue(current, out var edge))
                        return Failure(PathStatus.InvalidGraph);
                    pathEdges.Add(edge);
                    current = edge.FromNodeId;
                    pathNodes.Add(current);
                }
                pathNodes.Reverse();
                pathEdges.Reverse();
                return new(PathStatus.Success, priority.Distance, pathNodes, pathEdges);
            }
            if (!outgoing.TryGetValue(current, out var adjacent)) continue;
            foreach (var edge in adjacent)
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (settled.Contains(edge.ToNodeId)) continue;
                decimal candidate;
                try { candidate = checked(priority.Distance + edge.DistanceMeters); }
                catch (OverflowException) { return Failure(PathStatus.InvalidGraph); }
                if (distances.TryGetValue(edge.ToNodeId, out var known) && candidate >= known) continue;
                distances[edge.ToNodeId] = candidate;
                previous[edge.ToNodeId] = edge;
                queue.Enqueue(edge.ToNodeId, (candidate, edge.ToNodeId));
            }
        }
        return Failure(PathStatus.NoPath);
    }

    private static PathResult Failure(PathStatus status) => new(status, 0m, [], []);
}
