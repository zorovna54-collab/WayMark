namespace WayMark.Api.Services.MapDrafts;

public sealed class ManagedMapImageOptions
{
    public const string Section = "MapImages";
    public bool Enabled { get; set; }
    public string? RootPath { get; set; }
    public long MaxStorageBytes { get; set; } = 1024L * 1024 * 1024;
    public int MaxObjects { get; set; } = 5000;
}

public sealed class MapDraftLimitsOptions
{
    public const string Section = "MapDraftLimits";
    public int MaxRevisionsPerFloor { get; set; } = 500;
    public int MaxImagesPerFloor { get; set; } = 100;
    public long MaxImageBytesPerFloor { get; set; } = 250L * 1024 * 1024;
}
