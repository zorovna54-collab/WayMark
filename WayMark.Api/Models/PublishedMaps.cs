namespace WayMark.Api.Models;

// Project aggregate reuses floor hierarchy, private image assets and draft DTOs.
// It never replaces the live NavigationNodes/Edges tables.
public sealed class MapProject
{
    public Guid Id { get; set; }
    public Guid LocalProjectId { get; set; }
    public int SiteId { get; set; }
    public int BuildingId { get; set; }
    public string OwnerId { get; set; } = "";
    public string Name { get; set; } = "";
    public long Version { get; set; }
    public string ContentJson { get; set; } = "";
    public DateTimeOffset UpdatedAt { get; set; }
}

public sealed class MapPublication
{
    public Guid MapId { get; set; }
    public long Version { get; set; }
    public string Name { get; set; } = "";
    public string ContentJson { get; set; } = "";
    public string PublishedBy { get; set; } = "";
    public DateTimeOffset PublishedAt { get; set; }
}

public sealed class MapPublicationImage
{
    public Guid MapId { get; set; }
    public long Version { get; set; }
    public Guid AssetId { get; set; }
}

public sealed class MapNodeQr
{
    public Guid Id { get; set; }
    public Guid MapId { get; set; }
    public Guid FloorKey { get; set; }
    public Guid NodeId { get; set; }
    public long DraftVersion { get; set; }
    public long? PublishedVersion { get; set; }
    public string Token { get; set; } = "";
    public bool IsActive { get; set; } = true;
    public string CreatedBy { get; set; } = "";
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset? RevokedAt { get; set; }
}
