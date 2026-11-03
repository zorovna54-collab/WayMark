using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.Extensions.Options;

namespace WayMark.Api.Services.MapDrafts;

public sealed record ManagedImageManifest(int SchemaVersion, string StorageKey, StoredMapImage Image,
    string State, DateTimeOffset CreatedAt);
public sealed record ManagedImageInventory(string StorageKey, string State, bool ObjectPresent, long ByteLength);

/// <summary>Private local-disk adapter. No background purge; durable manifests survive SQL/process failures.</summary>
public sealed class ManagedFileMapImageStorage(IOptions<ManagedMapImageOptions> options,
    IWebHostEnvironment environment, MapImageCodec codec, TimeProvider clock) : IMapImageStorage
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    // Read-only diagnostic: validates configuration/path, never creates folders,
    // writes a probe file, acquires a lease or discloses the physical root.
    public void ValidateConfiguration() => _ = Paths();
    private ManagedStoragePaths Paths()
    {
        var config = options.Value;
        if (!config.Enabled) throw new DraftOperationException(503, "image_storage_unavailable", "Managed image storage is not enabled");
        if (config.MaxStorageBytes < MapImageRules.MaxBytes || config.MaxObjects < 1) throw new DraftOperationException(503, "image_storage_configuration", "Invalid image storage quota configuration");
        return new(config.RootPath, environment.ContentRootPath, environment.WebRootPath);
    }
    public async Task<IAsyncDisposable> AcquireUploadLeaseAsync(int floorId, CancellationToken ct)
    {
        if (floorId <= 0) throw InvalidKey();
        var paths = Paths(); paths.Prepare();
        return await LockAsync(paths.File("leases", $"floor-{floorId}.lock"), ct);
    }

    public async Task<StoredMapImage> StoreValidatedAsync(Guid assetId, Stream input, string mime, CancellationToken ct)
        => await StoreValidatedAsync(assetId, input, mime, MapImageRules.MaxBytes, ct);

    public async Task<StoredMapImage> StoreValidatedAsync(Guid assetId, Stream input, string mime, long maxStoredBytes, CancellationToken ct)
    {
        if (assetId == Guid.Empty) throw InvalidKey();
        var paths = Paths(); paths.Prepare();
        var image = await codec.NormalizeAsync(input, mime, ct);
        if (image.Bytes.LongLength > maxStoredBytes) throw new DraftOperationException(409, "floor_image_quota", "Floor image byte quota reached");
        var key = assetId.ToString("N");
        var stored = new StoredMapImage(key, image.Mime, image.Width, image.Height, image.Bytes.LongLength, image.Sha256);
        await using var gate = await LockAsync(paths.File("leases", "storage.lock"), ct);
        var objectPath = paths.File("objects", key + ".bin");
        var manifestPath = paths.File("objects", key + ".json");
        if (File.Exists(manifestPath))
        {
            var existing = await ReadManifestAsync(paths, key, ct);
            if (existing.Image != stored) throw new DraftOperationException(409, "image_key_conflict", "Immutable image key already contains different content");
            if (File.Exists(objectPath))
            {
                await using var verified = await OpenReadAsync(key, ct);
                return stored; // Idempotent retry of an already durable object.
            }
        }
        else if (File.Exists(objectPath)) throw new DraftOperationException(503, "image_reconciliation_required", "Image object requires operator reconciliation");

        var manifest = new ManagedImageManifest(1, key, stored, "PendingMetadata", clock.GetUtcNow());
        CheckQuota(paths, image.Bytes.LongLength + JsonSerializer.SerializeToUtf8Bytes(manifest, Json).LongLength + 4096,
            !File.Exists(manifestPath));
        var temporary = paths.File("staging", Guid.NewGuid().ToString("N") + ".upload");
        try
        {
            await WriteNewAsync(temporary, image.Bytes, ct);
            // Manifest first: any final .bin has a durable inventory entry, even across a crash.
            await WriteManifestAsync(paths, manifest, ct);
            ct.ThrowIfCancellationRequested();
            File.Move(temporary, paths.File("objects", key + ".bin"), false);
            return stored;
        }
        finally
        {
            // Only this call's uncommitted temporary file can be removed automatically.
            ManagedStoragePaths.RejectLink(temporary);
            if (File.Exists(temporary)) File.Delete(temporary);
        }
    }

    public async Task<Stream> OpenReadAsync(string key, CancellationToken ct)
    {
        ValidateKey(key);
        var paths = Paths();
        var manifest = await ReadManifestAsync(paths, key, ct);
        var path = paths.File("objects", key + ".bin");
        if (!File.Exists(path)) throw new DraftOperationException(503, "image_object_unavailable", "Private image object is unavailable");
        var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 65536, FileOptions.Asynchronous | FileOptions.SequentialScan);
        try
        {
            if (stream.Length != manifest.Image.ByteLength || stream.Length > MapImageRules.MaxBytes) throw Integrity();
            var checksum = Convert.ToHexStringLower(await SHA256.HashDataAsync(stream, ct));
            if (checksum != manifest.Image.Sha256) throw Integrity();
            stream.Position = 0;
            return stream;
        }
        catch { await stream.DisposeAsync(); throw; }
    }

    public Task ConfirmMetadataAsync(string key, CancellationToken ct) => MarkAsync(key, "MetadataCommitted", ct);
    // Legacy interface name retained. A stable object is NEVER physically deleted here.
    // A caller that established absence of SQL metadata only flags the inventory for review.
    public Task DeleteUnreferencedAsync(string key, CancellationToken ct) => MarkAsync(key, "NeedsReconciliation", ct);

    public async Task<IReadOnlyList<ManagedImageInventory>> InspectAsync(CancellationToken ct)
    {
        var paths = Paths(); paths.Prepare();
        await using var gate = await LockAsync(paths.File("leases", "storage.lock"), ct);
        var records = new List<ManagedImageInventory>();
        foreach (var file in Directory.EnumerateFiles(Path.Combine(paths.Root, "objects"), "*.json"))
        {
            var key = Path.GetFileNameWithoutExtension(file);
            try
            {
                var manifest = await ReadManifestAsync(paths, key, ct);
                records.Add(new(key, manifest.State, File.Exists(paths.File("objects", key + ".bin")), manifest.Image.ByteLength));
            }
            catch (Exception error) when (error is DraftOperationException or IOException)
            {
                var objectPath = paths.File("objects", key + ".bin");
                var present = File.Exists(objectPath);
                records.Add(new(key, "InvalidManifest", present, present ? new FileInfo(objectPath).Length : 0));
            }
        }
        foreach (var file in Directory.EnumerateFiles(Path.Combine(paths.Root, "objects"), "*.bin"))
        {
            ManagedStoragePaths.RejectLink(file);
            var key = Path.GetFileNameWithoutExtension(file);
            if (!File.Exists(paths.File("objects", key + ".json"))) records.Add(new(key, "UnmanifestedObject", true, new FileInfo(file).Length));
        }
        foreach (var file in Directory.EnumerateFiles(Path.Combine(paths.Root, "staging")))
        {
            ManagedStoragePaths.RejectLink(file);
            records.Add(new(Path.GetFileName(file), "TemporaryNeedsReview", true, new FileInfo(file).Length));
        }
        return records; // Operator API in source only; not an HTTP endpoint or automatic purge.
    }

    private async Task MarkAsync(string key, string state, CancellationToken ct)
    {
        ValidateKey(key);
        var paths = Paths(); paths.Prepare();
        await using var gate = await LockAsync(paths.File("leases", "storage.lock"), ct);
        var record = await ReadManifestAsync(paths, key, ct);
        await WriteManifestAsync(paths, record with { State = state }, ct);
    }
    private static async Task<ManagedImageManifest> ReadManifestAsync(ManagedStoragePaths paths, string key, CancellationToken ct)
    {
        ValidateKey(key);
        var path = paths.File("objects", key + ".json");
        if (!File.Exists(path) || new FileInfo(path).Length > 8192) throw Integrity();
        var bytes = await File.ReadAllBytesAsync(path, ct);
        ManagedImageManifest? record;
        try { record = JsonSerializer.Deserialize<ManagedImageManifest>(bytes, Json); }
        catch (JsonException) { throw Integrity(); }
        if (record is null || record.SchemaVersion != 1 || record.StorageKey != key || record.Image is null
            || !MapImageRules.Metadata(record.Image, Guid.ParseExact(key, "N"))
            || record.State is not ("PendingMetadata" or "MetadataCommitted" or "NeedsReconciliation")) throw Integrity();
        return record;
    }
    private static async Task WriteManifestAsync(ManagedStoragePaths paths, ManagedImageManifest record, CancellationToken ct)
    {
        var temporary = paths.File("staging", Guid.NewGuid().ToString("N") + ".manifest");
        try
        {
            await WriteNewAsync(temporary, JsonSerializer.SerializeToUtf8Bytes(record, Json), ct);
            File.Move(temporary, paths.File("objects", record.StorageKey + ".json"), true);
        }
        finally { ManagedStoragePaths.RejectLink(temporary); if (File.Exists(temporary)) File.Delete(temporary); }
    }
    private void CheckQuota(ManagedStoragePaths paths, long extra, bool newObject)
    {
        var count = Directory.EnumerateFiles(Path.Combine(paths.Root, "objects"), "*.json").Count();
        long bytes = 0;
        foreach (var area in new[] { "objects", "staging" })
        foreach (var file in Directory.EnumerateFiles(Path.Combine(paths.Root, area)))
        {
            ManagedStoragePaths.RejectLink(file);
            bytes = checked(bytes + new FileInfo(file).Length);
        }
        if (count + (newObject ? 1 : 0) > options.Value.MaxObjects || bytes > options.Value.MaxStorageBytes - extra)
            throw new DraftOperationException(409, "image_storage_quota", "Private storage quota reached; operator review is required");
    }
    private static async Task WriteNewAsync(string path, byte[] bytes, CancellationToken ct)
    {
        await using var stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None, 65536,
            FileOptions.Asynchronous | FileOptions.WriteThrough);
        await stream.WriteAsync(bytes, ct);
        await stream.FlushAsync(ct);
        stream.Flush(true);
    }
    private static async Task<FileStream> LockAsync(string path, CancellationToken ct)
    {
        var until = DateTimeOffset.UtcNow.AddSeconds(10);
        while (true)
        {
            ct.ThrowIfCancellationRequested();
            ManagedStoragePaths.RejectLink(path);
            try { return new FileStream(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None, 1, FileOptions.Asynchronous); }
            catch (IOException) when (DateTimeOffset.UtcNow < until) { await Task.Delay(25, ct); }
            catch (IOException) { throw new DraftOperationException(503, "image_storage_busy", "Private image storage is busy; retry later"); }
        }
    }
    private static void ValidateKey(string key)
    {
        if (!Guid.TryParseExact(key, "N", out var id) || id == Guid.Empty || id.ToString("N") != key) throw InvalidKey();
    }
    private static DraftOperationException InvalidKey() => new(400, "invalid_storage_key", "Invalid opaque image identifier");
    private static DraftOperationException Integrity() => new(503, "image_integrity_failure", "Private image integrity check failed");
}
