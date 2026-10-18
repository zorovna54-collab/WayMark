using System.ComponentModel.DataAnnotations;

namespace WayMark.Api.Contracts;

public sealed class RouteRequest
{
    [Required, StringLength(100)]
    public string StartWayMarkCode { get; init; } = string.Empty;

    [Required, StringLength(100)]
    public string DestinationWayMarkCode { get; init; } = string.Empty;
}

public sealed record RoutePointDto(int Id, string Name, string Location, string WayMarkCode);

public sealed record RouteNodeDto(
    int Id, string NodeCode, string Name, string NodeType, FloorDto Floor);

public sealed record RouteEdgeDto(
    int Sequence, int Id, int FromNodeId, int ToNodeId, int FromFloorId, int ToFloorId,
    string EdgeType, decimal DistanceMeters, bool IsAccessible, string Movement);

public sealed record RouteResponseDto(
    RoutePointDto Start, RoutePointDto Destination, decimal TotalDistanceMeters,
    bool AccessibleOnly, IReadOnlyList<RouteNodeDto> Nodes, IReadOnlyList<RouteEdgeDto> Edges);
