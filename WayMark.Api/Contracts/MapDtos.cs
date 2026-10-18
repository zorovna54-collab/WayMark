namespace WayMark.Api.Contracts;

public sealed record SiteDto(int Id, string Name, string Code, string? Address);

public sealed record BuildingDto(int Id, int SiteId, string Name, string BuildingCode);

public sealed record FloorDto(
    int Id, int BuildingId, string Name, string FloorCode, int SortOrder,
    string? FloorPlanImageUrl);

public sealed record NavigationNodeDto(
    int Id, int FloorId, string NodeCode, string Name, decimal X, decimal Y,
    string NodeType);

public sealed record NavigationEdgeDto(
    int Id, int FromNodeId, int ToNodeId, string EdgeType, decimal DistanceMeters,
    bool IsActive, bool IsAccessible);

public sealed record FloorGraphDto(
    FloorDto Floor, IReadOnlyList<NavigationNodeDto> Nodes,
    IReadOnlyList<NavigationEdgeDto> Edges);

public sealed record WayMarkMapDto(
    int Id, string Name, string Location, string WayMarkCode,
    NavigationNodeDto? Node);
