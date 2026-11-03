using WayMark.Api.Contracts;
using WayMark.Api.Models;

namespace WayMark.Api.Services.MapDrafts;

public sealed class MapDraftValidator
{
    public const int MaxDocumentBytes = 2 * 1024 * 1024;
    public const int MaxNodes = 2000, MaxEdges = 10000, MaxPlaces = 2000, MaxTransitions = 1000;

    public DraftValidationDto Validate(MapDraftContent? content)
    {
        var errors = new List<DraftIssueDto>();
        var warnings = new List<DraftIssueDto>();
        void Error(string code, string path, string message) => errors.Add(new(code, path, message));
        if (content is null)
            return new([new("content_required", "content", "Draft content is required")], []);
        if (content.SchemaVersion != 1) Error("schema_version", "schemaVersion", "Only schemaVersion 1 is supported");
        if (content.Nodes is null || content.Edges is null || content.Places is null || content.Transitions is null)
            return new([new("collections_required", "content", "Collections cannot be null")], []);
        if (content.Nodes.Count > MaxNodes || content.Edges.Count > MaxEdges || content.Places.Count > MaxPlaces
            || content.Transitions.Count > MaxTransitions)
            return new([new("graph_limit", "content", "Draft exceeds graph item limits")], []);
        if (content.ImageAssetId == Guid.Empty) Error("image_id", "imageAssetId", "Image ID cannot be empty");

        var nodes = new Dictionary<Guid, DraftNodeDto>();
        var nodeCodes = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var qrCodes = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var node in content.Nodes)
        {
            if (node is null) { Error("null_item", "nodes", "Node cannot be null"); continue; }
            if (node.Id == Guid.Empty || !nodes.TryAdd(node.Id, node)) Error("duplicate_id", "nodes", "Node IDs must be nonempty and unique");
            if (!Text(node.NodeCode, 100) || !nodeCodes.Add(node.NodeCode)) Error("node_code", "nodes", "Invalid or duplicate NodeCode");
            if (!Text(node.Name, 200) || !Point(node.X, node.Y) || !Enum.IsDefined(node.NodeType))
                Error("invalid_node", "nodes", "Node requires a name, known type and coordinates in 0–1");
            if (node.SourceNodeId <= 0) Error("source_node", "nodes", "Source node ID must be positive");
            if (node.DisplayName is { } display && !Text(display, 200)
                || node.LandmarkNote is { } note && !Text(note, 1000))
                Error("node_metadata", "nodes", "Invalid display name or landmark note");
            if (node.ExistingWayMarkCode is { } qr && (!Text(qr, 100) || !qrCodes.Add(qr)))
                Error("qr_reference", "nodes", "Invalid or duplicate WayMark reference");
        }
        var edgeIds = new HashSet<Guid>();
        var pairs = new HashSet<(Guid, Guid)>();
        foreach (var edge in content.Edges)
        {
            if (edge is null) { Error("null_item", "edges", "Edge cannot be null"); continue; }
            if (edge.Id == Guid.Empty || !edgeIds.Add(edge.Id)) Error("duplicate_id", "edges", "Edge IDs must be nonempty and unique");
            if (!nodes.ContainsKey(edge.FromNodeId) || !nodes.ContainsKey(edge.ToNodeId) || edge.FromNodeId == edge.ToNodeId
                || !pairs.Add((edge.FromNodeId, edge.ToNodeId)))
                Error("edge_reference", "edges", "Edge endpoints must exist, differ and have a unique direction");
            if (!Enum.IsDefined(edge.EdgeType) || !Distance(edge.DistanceMeters)) Error("invalid_edge", "edges", "Invalid edge type or meter distance");
            if (edge.Accessibility != "Unknown" || edge.PassageVerification != "Unknown")
                Error("unverified_claim", "edges", "Unverified accessibility and passage must stay Unknown");
            if (edge.DistanceMeters is null) warnings.Add(new("distance_unknown", "edges", "Distance must be measured before routing/publication"));
        }
        var places = new HashSet<Guid>();
        var placeCodes = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var place in content.Places)
        {
            if (place is null) { Error("null_item", "places", "Place cannot be null"); continue; }
            if (place.Id == Guid.Empty || !places.Add(place.Id)) Error("duplicate_id", "places", "Place IDs must be nonempty and unique");
            if (!Text(place.PlaceCode, 100) || !placeCodes.Add(place.PlaceCode) || !Text(place.Name, 200))
                Error("invalid_place", "places", "Place requires a unique code and name");
            if (place.Label is null || !Point(place.Label.X, place.Label.Y)) Error("place_label", "places", "Place label requires normalized coordinates");
            if (place.Polygon is null || place.Polygon.Count > 100 || (place.Polygon.Count is 1 or 2)
                || place.Polygon.Any(p => p is null || !Point(p.X, p.Y)))
                Error("place_polygon", "places", "Polygon must be empty or have 3–100 normalized points");
            if (place.EntranceNodeIds is null || place.EntranceNodeIds.Count == 0 || place.EntranceNodeIds.Count > 100
                || place.EntranceNodeIds.Distinct().Count() != place.EntranceNodeIds.Count
                || place.EntranceNodeIds.Any(id => !nodes.TryGetValue(id, out var node) || node.NodeType != NavigationNodeType.Entrance))
                Error("place_entrance", "places", "Place requires one or more distinct existing Entrance nodes, never its label center");
            if (place.Accessibility != "Unknown") Error("unverified_claim", "places", "Unverified place accessibility must stay Unknown");
        }
        var transitions = new HashSet<Guid>();
        var transitionPairs = new HashSet<(Guid, Guid, long, Guid)>();
        foreach (var link in content.Transitions)
        {
            if (link is null) { Error("null_item", "transitions", "Transition cannot be null"); continue; }
            if (link.Id == Guid.Empty || !transitions.Add(link.Id)) Error("duplicate_id", "transitions", "Transition IDs must be nonempty and unique");
            if (!nodes.TryGetValue(link.FromNodeId, out var from) || !Connector(from.NodeType, link.EdgeType)
                || link.TargetDraftId == Guid.Empty || link.TargetNodeId == Guid.Empty || link.TargetVersion <= 0
                || !transitionPairs.Add((link.FromNodeId, link.TargetDraftId, link.TargetVersion, link.TargetNodeId)))
                Error("transition_reference", "transitions", "Transition requires a compatible connector and pinned target revision/node");
            if (!Distance(link.DistanceMeters)) Error("invalid_distance", "transitions", "Invalid transition meter distance");
            if (link.Accessibility != "Unknown" || link.PassageVerification != "Unknown")
                Error("unverified_claim", "transitions", "Unverified transition safety must stay Unknown");
        }
        if (content.ImageAssetId is null) warnings.Add(new("image_missing", "imageAssetId", "No floor plan image is attached"));
        warnings.Add(new("review_required", "content", "Geometry does not prove walkability, wall clearance or wheelchair safety; draft is not published"));
        return new(errors, warnings);
    }

    public static bool Connector(NavigationNodeType node, NavigationEdgeType edge) => edge switch
    {
        NavigationEdgeType.Elevator => node == NavigationNodeType.Elevator,
        NavigationEdgeType.Stairs => node == NavigationNodeType.Stairs,
        NavigationEdgeType.Ramp => node is NavigationNodeType.Entrance or NavigationNodeType.Junction,
        _ => false
    };
    private static bool Text(string? value, int max) => !string.IsNullOrWhiteSpace(value)
        && value.Length <= max && value == value.Trim() && !value.Any(char.IsControl);
    private static bool Point(decimal x, decimal y) => x is >= 0 and <= 1 && y is >= 0 and <= 1;
    private static bool Distance(decimal? meters) => meters is null || (meters > 0m && meters <= 999999999.999m
        && decimal.Round(meters.Value, 3) == meters.Value);
}
