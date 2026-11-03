using System.Text.RegularExpressions;

namespace WayMark.Api.Services.MapDrafts;

public sealed record StoredMapImage(string StorageKey, string MimeType, int Width, int Height,
    long ByteLength, string Sha256);

/// <summary>
/// Private storage boundary, never a path or URL supplied by a caller. A provider must
/// bound stream reads, verify actual PNG/JPEG decoding and dimensions, remove metadata,
/// calculate the stored SHA-256 and keep immutable objects outside public/static storage.
/// </summary>
public interface IMapImageStorage
{
    Task<IAsyncDisposable> AcquireUploadLeaseAsync(int floorId, CancellationToken cancellationToken)
        => Task.FromResult<IAsyncDisposable>(new NoopImageLease());
    Task<StoredMapImage> StoreValidatedAsync(Guid assetId, Stream untrustedContent,
        string declaredMimeType, CancellationToken cancellationToken);
    Task<StoredMapImage> StoreValidatedAsync(Guid assetId, Stream untrustedContent,
        string declaredMimeType, long maxStoredBytes, CancellationToken cancellationToken)
        => StoreValidatedAsync(assetId, untrustedContent, declaredMimeType, cancellationToken);
    // Return a bounded, seekable immutable read snapshot; callers verify SQL checksum too.
    Task<Stream> OpenReadAsync(string storageKey, CancellationToken cancellationToken);
    // Legacy name: managed storage flags for reconciliation and never physically purges an asset.
    Task DeleteUnreferencedAsync(string storageKey, CancellationToken cancellationToken);
    Task ConfirmMetadataAsync(string storageKey, CancellationToken cancellationToken) => Task.CompletedTask;
}

internal sealed class NoopImageLease : IAsyncDisposable
{
    public ValueTask DisposeAsync() => ValueTask.CompletedTask;
}

// No provider, filesystem paths or implicit disk writes are enabled by default.
public sealed class UnavailableMapImageStorage : IMapImageStorage
{
    public Task<StoredMapImage> StoreValidatedAsync(Guid assetId, Stream untrustedContent,
        string declaredMimeType, CancellationToken cancellationToken) => throw Unavailable();
    public Task<Stream> OpenReadAsync(string storageKey, CancellationToken cancellationToken) => throw Unavailable();
    public Task DeleteUnreferencedAsync(string storageKey, CancellationToken cancellationToken) => throw Unavailable();
    private static DraftOperationException Unavailable() => new(503, "image_storage_unavailable", "Private validated image storage is not configured");
}

public static partial class MapImageRules
{
    public const long MaxBytes = 10 * 1024 * 1024;
    public static bool Mime(string? value) => value is "image/png" or "image/jpeg";
    // Defense at the storage/SQL boundary; not a substitute for a real image decoder.
    public static bool Metadata(StoredMapImage image, Guid assetId) => image.StorageKey == assetId.ToString("N")
        && Mime(image.MimeType) && image.Width is > 0 and <= 8192 && image.Height is > 0 and <= 8192
        && (long)image.Width * image.Height <= 32000000 && image.ByteLength is > 0 and <= MaxBytes
        && image.Sha256 is not null && Sha256Pattern().IsMatch(image.Sha256);
    [GeneratedRegex("^[a-f0-9]{64}$", RegexOptions.CultureInvariant)]
    private static partial Regex Sha256Pattern();
}
