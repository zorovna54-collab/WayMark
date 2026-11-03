namespace WayMark.Api.Models;

// Separate from Identity roles. Operator grants facility membership; self-service
// onboarding may grant membership ONLY to a newly created owned personal scope.
public sealed class SiteMapMembership
{
    public int Id { get; set; }
    public int SiteId { get; set; }
    public string UserId { get; set; } = string.Empty;
    public bool IsActive { get; set; }
    public bool CanEditDrafts { get; set; }
}

public sealed class FloorMapDraft
{
    public Guid Id { get; set; }
    public int FloorId { get; set; }
    public long Version { get; set; }
    public string Status { get; set; } = "Draft";
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    public string CreatedBy { get; set; } = string.Empty;
    public string UpdatedBy { get; set; } = string.Empty;
}

public sealed class FloorMapDraftRevision
{
    public Guid DraftId { get; set; }
    public long Version { get; set; }
    public string ContentJson { get; set; } = string.Empty;
    public Guid? ImageAssetId { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public string CreatedBy { get; set; } = string.Empty;
    public FloorMapDraft Draft { get; set; } = null!;
}

public sealed class FloorMapImageAsset
{
    public Guid Id { get; set; }
    public int FloorId { get; set; }
    public string StorageKey { get; set; } = string.Empty;
    public string MimeType { get; set; } = string.Empty;
    public int Width { get; set; }
    public int Height { get; set; }
    public long ByteLength { get; set; }
    public string Sha256 { get; set; } = string.Empty;
    public DateTimeOffset CreatedAt { get; set; }
    public string CreatedBy { get; set; } = string.Empty;
}
