namespace WayMark.Api.Models;

// Private per-user activity. No cascade from maps and no Identity snapshot/roles.
public sealed class NavigationHistory
{
    public Guid Id { get; set; }
    public string UserId { get; set; } = "";
    public Guid MapId { get; set; }
    public long PublishedVersion { get; set; }
    public Guid StartQrId { get; set; }
    public Guid StartNodeId { get; set; }
    public Guid? DestinationNodeId { get; set; }
    public Guid? DestinationFloorKey { get; set; }
    public Guid? StartFloorKey { get; set; }
    public DateTime? ScannedAtUtc { get; set; }
    public DateTime? NavigationStartedAtUtc { get; set; }
    public decimal? DistanceMeters { get; set; }
    public string MapName { get; set; } = "";
    public string StartName { get; set; } = "";
    public string DestinationName { get; set; } = "";
    public DateTime StartedAtUtc { get; set; }
    public DateTime? EndedAtUtc { get; set; }
    public string Status { get; set; } = "Scanned";
}
