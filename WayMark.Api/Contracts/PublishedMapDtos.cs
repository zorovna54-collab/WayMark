using System.Text.Json.Serialization;

namespace WayMark.Api.Contracts;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record ProjectFloorDto(Guid Id, int FloorId, string Name, string Code, MapDraftContent Content);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record ProjectLinkDto(Guid Id, Guid FromFloor, Guid FromNode, Guid ToFloor, Guid ToNode,
    decimal DistanceMeters, string Type, bool Active = true, string Accessibility = "Unknown");
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record ProjectContentDto(Guid Id, IReadOnlyList<ProjectFloorDto> Floors, IReadOnlyList<ProjectLinkDto> Links,
    ProjectInfoDto? Info = null);
public sealed record ProjectInfoDto(string Purpose, string PlaceName, string? Description, string Kind = "PersonalDemo");
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record CreateMapProjectRequest(string Name, ProjectContentDto Content);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record SaveMapProjectRequest(long ExpectedVersion, string Name, ProjectContentDto Content);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record PublishMapRequest(long ExpectedVersion, bool ConfirmPublic);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record CreateNodeQrRequest(long ExpectedVersion, Guid FloorKey, Guid NodeId);
public sealed record MapProjectDto(Guid Id, string Name, long Version, int SiteId, int BuildingId,
    ProjectContentDto Content, DateTimeOffset UpdatedAt, bool CanPublish = false, string PublicationKind = "FacilityScoped");
public sealed record MapProjectSummaryDto(Guid Id, string Name, long Version, Guid LocalProjectId,
    long? PublishedVersion = null, string PublicationKind = "FacilityScoped");
public sealed record PublicMapDto(Guid MapId, long Version, string Name, ProjectContentDto Content,
    DateTimeOffset PublishedAt, bool VerifiedForPatientUse = false);
public sealed record NodeQrDto(Guid Id, Guid MapId, Guid FloorKey, Guid NodeId, long DraftVersion,
    long? PublishedVersion, string Payload, bool IsActive);
public sealed record ResolveMapQrDto(Guid MapId, long Version, Guid FloorKey, Guid NodeId, string MapName, string NodeName);
public sealed record PublishCheckDto(string Code, bool Passed, string Message);
public sealed record PublishReadinessDto(Guid MapId, long Version, int SavedNodes, int SavedEdges,
    IReadOnlyList<PublishCheckDto> Checks);
