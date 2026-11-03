using System.Text.Json.Serialization;
using WayMark.Api.Models;

namespace WayMark.Api.Contracts;

// Not the local Flutter JSON v2 import format. No embedded image bytes or caller ownership fields.
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record MapDraftContent
{
    public int SchemaVersion { get; init; } = 1;
    public Guid? ImageAssetId { get; init; }
    public IReadOnlyList<DraftNodeDto>? Nodes { get; init; } = [];
    public IReadOnlyList<DraftEdgeDto>? Edges { get; init; } = [];
    public IReadOnlyList<DraftPlaceDto>? Places { get; init; } = [];
    public IReadOnlyList<DraftTransitionDto>? Transitions { get; init; } = [];
}

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record DraftNodeDto
{
    [JsonRequired]
    public Guid Id { get; init; }
    [JsonRequired]
    public string NodeCode { get; init; } = string.Empty;
    [JsonRequired]
    public string Name { get; init; } = string.Empty;
    [JsonRequired]
    public decimal X { get; init; }
    [JsonRequired]
    public decimal Y { get; init; }
    [JsonRequired]
    [JsonConverter(typeof(JsonStringEnumConverter<NavigationNodeType>))]
    public NavigationNodeType NodeType { get; init; }
    public int? SourceNodeId { get; init; }
    public string? ExistingWayMarkCode { get; init; }
    public string? DisplayName { get; init; }
    public bool SearchableAsDestination { get; init; }
    public string? LandmarkNote { get; init; }
}

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record DraftEdgeDto
{
    [JsonRequired]
    public Guid Id { get; init; }
    [JsonRequired]
    public Guid FromNodeId { get; init; }
    [JsonRequired]
    public Guid ToNodeId { get; init; }
    [JsonRequired]
    [JsonConverter(typeof(JsonStringEnumConverter<NavigationEdgeType>))]
    public NavigationEdgeType EdgeType { get; init; }
    public decimal? DistanceMeters { get; init; }
    public bool IsActive { get; init; } = true;
    public string Accessibility { get; init; } = "Unknown";
    public string PassageVerification { get; init; } = "Unknown";
}

public sealed record DraftPointDto(decimal X, decimal Y);

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record DraftPlaceDto
{
    [JsonRequired]
    public Guid Id { get; init; }
    [JsonRequired]
    public string PlaceCode { get; init; } = string.Empty;
    [JsonRequired]
    public string Name { get; init; } = string.Empty;
    // Label/polygon coordinates are for drawing only. They are NOT route targets.
    public DraftPointDto? Label { get; init; }
    public IReadOnlyList<DraftPointDto>? Polygon { get; init; } = [];
    public IReadOnlyList<Guid>? EntranceNodeIds { get; init; } = [];
    public string Accessibility { get; init; } = "Unknown";
}

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record DraftTransitionDto
{
    [JsonRequired]
    public Guid Id { get; init; }
    [JsonRequired]
    public Guid FromNodeId { get; init; }
    [JsonRequired]
    public Guid TargetDraftId { get; init; }
    [JsonRequired]
    public long TargetVersion { get; init; }
    [JsonRequired]
    public Guid TargetNodeId { get; init; }
    [JsonRequired]
    [JsonConverter(typeof(JsonStringEnumConverter<NavigationEdgeType>))]
    public NavigationEdgeType EdgeType { get; init; }
    public decimal? DistanceMeters { get; init; }
    public string Accessibility { get; init; } = "Unknown";
    public string PassageVerification { get; init; } = "Unknown";
}

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record SaveMapDraftRequest(long ExpectedVersion, MapDraftContent? Content);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record RestoreMapDraftRequest(long ExpectedVersion, long SourceVersion);

public sealed record MapDraftMetadataDto(Guid Id, int SiteId, int BuildingId, int FloorId,
    long Version, string Status, DateTimeOffset CreatedAt, DateTimeOffset UpdatedAt,
    string CreatedBy, string UpdatedBy);
public sealed record MapDraftRevisionDto(long Version, DateTimeOffset CreatedAt, string CreatedBy);
public sealed record MapDraftGraphDto(Guid DraftId, int FloorId, long Version,
    string Status, MapDraftContent Content);
public sealed record MapImageMetadataDto(Guid Id, int FloorId, string MimeType, int Width,
    int Height, long ByteLength, string Sha256);
public sealed record DraftIssueDto(string Code, string Path, string Message);
public sealed record DraftValidationDto(IReadOnlyList<DraftIssueDto> Errors,
    IReadOnlyList<DraftIssueDto> Warnings)
{
    public bool IsValid => Errors.Count == 0;
    // Structural validity is never publication or accessibility approval.
    public bool ReadyForProduction => false;
}
