using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using SkiaSharp;
using WayMark.Api.Contracts;
using WayMark.Api.Data;
using WayMark.Api.Services.MapDrafts;
using Xunit;

namespace WayMark.Api.Tests;

public sealed class ManagedImageStorageTests : IAsyncLifetime
{
    private const string Base = "/api/admin/floors/10/map-drafts";
    private readonly ManagedImageTestStorage disk = new();
    private ManagedFileMapImageStorage storage = null!;
    private MapDraftTestHost host = null!;
    public async Task InitializeAsync()
    {
        storage = disk.Provider();
        host = new(storage, sqlitePath: disk.DatabasePath);
        await host.StartAsync();
        Assert.Equal(HttpStatusCode.Created, (await host.Client.PostAsJsonAsync(Base, new MapDraftContent())).StatusCode);
    }
    public async Task DisposeAsync() { await host.DisposeAsync(); disk.Dispose(); }

    [Theory]
    [InlineData("image/png", "plan.png")]
    [InlineData("image/jpeg", "plan.jpg")]
    public async Task RealUploadDecodeChecksumPrivateDownloadAndRestart(string mime, string name)
    {
        var asset = await Upload(ManagedImageTestStorage.Image(mime), mime, name);
        Assert.Equal(90, asset.Width); Assert.Equal(60, asset.Height);
        using var first = await host.Client.GetAsync(Base + $"/images/{asset.Id}");
        Assert.Equal(HttpStatusCode.OK, first.StatusCode);
        Assert.Equal(mime, first.Content.Headers.ContentType!.MediaType);
        Assert.True(first.Headers.CacheControl!.NoStore);
        Assert.Equal("nosniff", Assert.Single(first.Headers.GetValues("X-Content-Type-Options")));
        var bytes = await first.Content.ReadAsByteArrayAsync();
        Assert.Equal(bytes.LongLength, asset.ByteLength);
        Assert.Equal(Convert.ToHexStringLower(SHA256.HashData(bytes)), asset.Sha256);
        using (var decoded = SKBitmap.Decode(bytes))
        {
            Assert.Equal(90, decoded.Width); Assert.Equal(60, decoded.Height);
            Assert.True(decoded.GetPixel(10, 10).Red > 200);
            Assert.True(decoded.GetPixel(80, 10).Blue > 200);
            Assert.True(decoded.GetPixel(10, 50).Green > 80);
            Assert.True(decoded.GetPixel(80, 50).Red > 200 && decoded.GetPixel(80, 50).Green > 200);
        }
        Assert.True(File.Exists(Path.Combine(disk.Settings.RootPath!, "objects", asset.Id.ToString("N") + ".bin")));
        Assert.Equal("MetadataCommitted", Assert.Single(await storage.InspectAsync(default)).State);
        // Full HTTP host + DB connection + provider recreation; SQLite file and managed files survive.
        await host.DisposeAsync();
        storage = disk.Provider(); host = new(storage, sqlitePath: disk.DatabasePath);
        await host.StartAsync();
        Assert.Equal(bytes, await host.Client.GetByteArrayAsync(Base + $"/images/{asset.Id}"));
    }

    [Theory]
    [InlineData("image/png", "floor.jpg")]
    [InlineData("image/png", "../../floor.png")]
    [InlineData("image/png", "floor.exe")]
    [InlineData("image/jpeg", "floor.jpg")]
    public async Task ExtensionPathOrCodecMismatchIsRejected(string declared, string name)
    {
        using var request = UploadRequest(ManagedImageTestStorage.Image(), declared, name);
        Assert.Equal(HttpStatusCode.BadRequest, (await host.Client.SendAsync(request)).StatusCode);
        using var scope = host.Scope();
        Assert.Empty(await scope.ServiceProvider.GetRequiredService<WayMarkDbContext>().FloorMapImageAssets.ToListAsync());
    }

    [Theory]
    [InlineData("html")]
    [InlineData("truncated")]
    [InlineData("header-only")]
    [InlineData("appended")]
    public async Task NonImagesAndCorruptPayloadsNeverCreateAssetFiles(string kind)
    {
        var good = ManagedImageTestStorage.Image();
        var input = kind switch
        {
            "html" => Encoding.UTF8.GetBytes("<script>synthetic-invalid-input</script>"),
            "truncated" => good[..(good.Length / 2)],
            "header-only" => new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 },
            _ => good.Concat(Encoding.UTF8.GetBytes("appended payload")).ToArray()
        };
        using var request = UploadRequest(input);
        Assert.Equal(HttpStatusCode.BadRequest, (await host.Client.SendAsync(request)).StatusCode);
        Assert.Empty(await storage.InspectAsync(default));
        Assert.Empty(Directory.GetFiles(Path.Combine(disk.Settings.RootPath!, "staging")));
    }

    [Fact]
    public async Task JpegSourceCommentIsStrippedByRealReencoding()
    {
        var jpeg = ManagedImageTestStorage.Image("image/jpeg");
        var comment = Encoding.ASCII.GetBytes("synthetic-source-comment-not-to-retain");
        var payload = jpeg[..2].Concat(new byte[] { 255, 254, 0, (byte)(comment.Length + 2) })
            .Concat(comment).Concat(jpeg[2..]).ToArray();
        var asset = await Upload(payload, "image/jpeg", "plan.jpg");
        var normalized = await host.Client.GetByteArrayAsync(Base + $"/images/{asset.Id}");
        Assert.DoesNotContain("synthetic-source-comment-not-to-retain", Encoding.ASCII.GetString(normalized));
        Assert.NotEqual(Convert.ToHexStringLower(SHA256.HashData(payload)), asset.Sha256);
    }

    [Theory]
    [InlineData("missing", "admin-a", 401)]
    [InlineData("user", "admin-a", 403)]
    [InlineData("admin", "no-membership", 403)]
    [InlineData("admin", "admin-b", 403)]
    public async Task RealImagesCannotBeUploadedOrReadWithoutSitePermission(string kind, string user, int status)
    {
        var asset = await Upload(ManagedImageTestStorage.Image());
        host.Token(kind, user);
        using var request = UploadRequest(ManagedImageTestStorage.Image());
        Assert.Equal(status, (int)(await host.Client.SendAsync(request)).StatusCode);
        Assert.Equal(status, (int)(await host.Client.GetAsync(Base + $"/images/{asset.Id}")).StatusCode);
        Assert.Single(await storage.InspectAsync(default));
    }

    [Fact]
    public async Task ValidUploadRequiresAnExistingDraftAndDoesNotTrustClientScope()
    {
        using var request = UploadRequest(ManagedImageTestStorage.Image(), path: "/api/admin/floors/11/map-drafts/images");
        request.Headers.Add("X-Site-Id", "1");
        Assert.Equal(HttpStatusCode.NotFound, (await host.Client.SendAsync(request)).StatusCode);
        using var scope = host.Scope();
        Assert.Empty(await scope.ServiceProvider.GetRequiredService<WayMarkDbContext>().FloorMapImageAssets.ToListAsync());
    }

    [Fact]
    public async Task OldImagesSurviveNewRevisionRestoreAndUnreferencedMarking()
    {
        var first = await Upload(ManagedImageTestStorage.Image());
        var second = await Upload(ManagedImageTestStorage.Image("image/jpeg"), "image/jpeg");
        var head = (await host.Client.GetFromJsonAsync<MapDraftMetadataDto>(Base))!;
        var content = MapDraftValidationTests.Content();
        Assert.Equal(HttpStatusCode.OK, (await host.Client.PutAsJsonAsync(Base + $"/{head.Id}", new SaveMapDraftRequest(1, content with { ImageAssetId = first.Id }))).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await host.Client.PutAsJsonAsync(Base + $"/{head.Id}", new SaveMapDraftRequest(2, content with { ImageAssetId = second.Id }))).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await host.Client.PutAsJsonAsync(Base + $"/{head.Id}", new SaveMapDraftRequest(2, content))).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await host.Client.PostAsJsonAsync(Base + $"/{head.Id}/restore", new RestoreMapDraftRequest(3, 2))).StatusCode);
        var restored = (await host.Client.GetFromJsonAsync<MapDraftGraphDto>(Base + $"/{head.Id}/graph"))!;
        Assert.Equal(first.Id, restored.Content.ImageAssetId);
        var previous = (await host.Client.GetFromJsonAsync<MapDraftGraphDto>(Base + $"/{head.Id}/graph?version=3"))!;
        Assert.Equal(second.Id, previous.Content.ImageAssetId);
        await storage.DeleteUnreferencedAsync(first.Id.ToString("N"), default);
        Assert.Equal(HttpStatusCode.OK, (await host.Client.GetAsync(Base + $"/images/{first.Id}")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await host.Client.GetAsync(Base + $"/images/{second.Id}")).StatusCode);
        using var scope = host.Scope();
        var db = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
        var route = await new WayMark.Api.Services.Routing.RoutePlanner(db, new()).PlanAsync("PUBLISHED-QR-A", "PUBLISHED-QR-B", false, default);
        Assert.Equal(40m, route.Route!.TotalDistanceMeters);
    }

    [Fact]
    public async Task FailedSqlSaveLeavesAnInventoriedUnreferencedFileAndNoDraftDamage()
    {
        host.Failure.FailAtWrite = 1; host.Failure.Armed = true;
        using var request = UploadRequest(ManagedImageTestStorage.Image());
        Assert.Equal(HttpStatusCode.ServiceUnavailable, (await host.Client.SendAsync(request)).StatusCode);
        var pending = Assert.Single(await storage.InspectAsync(default));
        Assert.True(pending.ObjectPresent); Assert.Equal("NeedsReconciliation", pending.State);
        using var scope = host.Scope();
        var db = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
        Assert.Empty(await db.FloorMapImageAssets.ToListAsync());
        Assert.Equal(1, (await db.FloorMapDrafts.SingleAsync()).Version);
    }

    [Fact]
    public async Task ChangedBytesFailIntegrityCheckInsteadOfServingACorruptImage()
    {
        var asset = await Upload(ManagedImageTestStorage.Image());
        var path = Path.Combine(disk.Settings.RootPath!, "objects", asset.Id.ToString("N") + ".bin");
        var bytes = await File.ReadAllBytesAsync(path); bytes[bytes.Length / 2] ^= 1; await File.WriteAllBytesAsync(path, bytes);
        Assert.Equal(HttpStatusCode.ServiceUnavailable, (await host.Client.GetAsync(Base + $"/images/{asset.Id}")).StatusCode);
    }

    [Fact]
    public async Task SaveAndRestoreRejectMissingOrCorruptImageWithoutAdvancingTheDraft()
    {
        var asset = await Upload(ManagedImageTestStorage.Image());
        var path = Path.Combine(disk.Settings.RootPath!, "objects", asset.Id.ToString("N") + ".bin");
        var original = await File.ReadAllBytesAsync(path);
        await File.WriteAllBytesAsync(path, new byte[original.Length]);
        var head = (await host.Client.GetFromJsonAsync<MapDraftMetadataDto>(Base))!;
        var content = new MapDraftContent { ImageAssetId = asset.Id };
        Assert.Equal(HttpStatusCode.ServiceUnavailable, (await host.Client.PutAsJsonAsync(Base + $"/{head.Id}", new SaveMapDraftRequest(1, content))).StatusCode);
        Assert.Equal(1, (await host.Client.GetFromJsonAsync<MapDraftMetadataDto>(Base))!.Version);
        await File.WriteAllBytesAsync(path, original);
        Assert.Equal(HttpStatusCode.OK, (await host.Client.PutAsJsonAsync(Base + $"/{head.Id}", new SaveMapDraftRequest(1, content))).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await host.Client.PutAsJsonAsync(Base + $"/{head.Id}", new SaveMapDraftRequest(2, new()))).StatusCode);
        File.Delete(path); // Only this fixture's own temp object; simulate external storage loss.
        Assert.Equal(HttpStatusCode.ServiceUnavailable, (await host.Client.PostAsJsonAsync(Base + $"/{head.Id}/restore", new RestoreMapDraftRequest(3, 2))).StatusCode);
        Assert.Equal(3, (await host.Client.GetFromJsonAsync<MapDraftMetadataDto>(Base))!.Version);
    }

    [Fact]
    public async Task InventoryIdentifiesMissingManifestsAndCorruptMetadataWithoutDeletingFiles()
    {
        var asset = await Upload(ManagedImageTestStorage.Image());
        var manifest = Path.Combine(disk.Settings.RootPath!, "objects", asset.Id.ToString("N") + ".json");
        await File.WriteAllTextAsync(manifest, "invalid test metadata");
        Assert.Equal("InvalidManifest", Assert.Single(await storage.InspectAsync(default)).State);
        File.Delete(manifest); // Test-owned manifest only, simulating loss.
        var orphan = Assert.Single(await storage.InspectAsync(default));
        Assert.Equal("UnmanifestedObject", orphan.State); Assert.True(orphan.ObjectPresent);
    }

    [Fact]
    public async Task StorageQuotaRejectsMoreFilesWithoutDamagingTheExistingDraft()
    {
        disk.Settings.MaxObjects = 1;
        var existing = await Upload(ManagedImageTestStorage.Image());
        using var request = UploadRequest(ManagedImageTestStorage.Image());
        Assert.Equal(HttpStatusCode.Conflict, (await host.Client.SendAsync(request)).StatusCode);
        Assert.Single(await storage.InspectAsync(default));
        Assert.Equal(HttpStatusCode.OK, (await host.Client.GetAsync(Base + $"/images/{existing.Id}")).StatusCode);
        Assert.Equal(1, (await host.Client.GetFromJsonAsync<MapDraftMetadataDto>(Base))!.Version);
    }

    [Fact]
    public async Task NewProviderCanReadPendingMetadataAndConfirmIdempotentlyAfterRestart()
    {
        var id = Guid.NewGuid();
        await using (var input = new MemoryStream(ManagedImageTestStorage.Image())) await storage.StoreValidatedAsync(id, input, "image/png", default);
        storage = disk.Provider();
        Assert.Equal("PendingMetadata", Assert.Single(await storage.InspectAsync(default)).State);
        await using var reopened = await storage.OpenReadAsync(id.ToString("N"), default);
        Assert.True(reopened.Length > 0);
        await storage.ConfirmMetadataAsync(id.ToString("N"), default);
        await storage.ConfirmMetadataAsync(id.ToString("N"), default);
        Assert.Equal("MetadataCommitted", Assert.Single(await storage.InspectAsync(default)).State);
    }

    [Fact]
    public async Task AmbiguousPostCommitFailureRetainsRealBytesAndSqlMetadata()
    {
        host.PostCommitFailure.Armed = true;
        using var request = UploadRequest(ManagedImageTestStorage.Image());
        Assert.Equal(HttpStatusCode.ServiceUnavailable, (await host.Client.SendAsync(request)).StatusCode);
        var entry = Assert.Single(await storage.InspectAsync(default));
        Assert.Equal("PendingMetadata", entry.State); Assert.True(entry.ObjectPresent);
        using var scope = host.Scope();
        var asset = await scope.ServiceProvider.GetRequiredService<WayMarkDbContext>().FloorMapImageAssets.SingleAsync();
        Assert.Equal(HttpStatusCode.OK, (await host.Client.GetAsync(Base + $"/images/{asset.Id}")).StatusCode);
        var recovery = await host.Client.GetFromJsonAsync<MapImageMetadataDto[]>(Base + "/images");
        Assert.Equal(asset.Id, Assert.Single(recovery!).Id);
        host.Token(userId: "admin-b");
        Assert.Equal(HttpStatusCode.Forbidden, (await host.Client.GetAsync(Base + "/images")).StatusCode);
    }

    [Fact]
    public async Task ActualFilesystemWriteFailureDoesNotCreateSqlMetadataOrAdvanceTheDraft()
    {
        Directory.CreateDirectory(disk.Settings.RootPath!);
        await File.WriteAllTextAsync(Path.Combine(disk.Settings.RootPath!, "objects"), "test-owned blocker instead of directory");
        using var request = UploadRequest(ManagedImageTestStorage.Image());
        var response = await host.Client.SendAsync(request);
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.DoesNotContain(disk.DirectoryPath, await response.Content.ReadAsStringAsync());
        using var scope = host.Scope();
        var db = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
        Assert.Empty(await db.FloorMapImageAssets.ToListAsync());
        Assert.Equal(1, (await db.FloorMapDrafts.SingleAsync()).Version);
    }

    [Fact]
    public async Task FloorImageAndRevisionLimitsRetainHistoryWithoutPurging()
    {
        await host.DisposeAsync();
        host = new(storage, policy => { policy.MaxImagesPerFloor = 1; policy.MaxRevisionsPerFloor = 2; }, disk.DatabasePath);
        await host.StartAsync();
        var image = await Upload(ManagedImageTestStorage.Image());
        using var second = UploadRequest(ManagedImageTestStorage.Image());
        Assert.Equal(HttpStatusCode.Conflict, (await host.Client.SendAsync(second)).StatusCode);
        Assert.Single(await storage.InspectAsync(default));
        var head = (await host.Client.GetFromJsonAsync<MapDraftMetadataDto>(Base))!;
        Assert.Equal(HttpStatusCode.OK, (await host.Client.PutAsJsonAsync(Base + $"/{head.Id}", new SaveMapDraftRequest(1, new() { ImageAssetId = image.Id }))).StatusCode);
        var limited = await host.Client.PostAsJsonAsync(Base + $"/{head.Id}/restore", new RestoreMapDraftRequest(2, 1));
        Assert.Equal(HttpStatusCode.Conflict, limited.StatusCode);
        Assert.Contains("draft_revision_quota", await limited.Content.ReadAsStringAsync());
        using var scope = host.Scope();
        Assert.Equal(2, await scope.ServiceProvider.GetRequiredService<WayMarkDbContext>().FloorMapDraftRevisions.CountAsync());
    }

    [Fact]
    public async Task FloorByteQuotaRejectsNormalizedImageBeforeAnyFinalFileIsCreated()
    {
        await host.DisposeAsync();
        host = new(storage, policy => policy.MaxImageBytesPerFloor = 1, disk.DatabasePath);
        await host.StartAsync();
        using var request = UploadRequest(ManagedImageTestStorage.Image());
        Assert.Equal(HttpStatusCode.Conflict, (await host.Client.SendAsync(request)).StatusCode);
        Assert.Empty(await storage.InspectAsync(default));
    }

    [Fact]
    public async Task SeparateProviderInstancesShareAnExclusiveFloorUploadLease()
    {
        var first = await storage.AcquireUploadLeaseAsync(10, default);
        var other = disk.Provider();
        var pending = other.AcquireUploadLeaseAsync(10, default);
        Assert.False(pending.IsCompleted);
        await using var differentFloor = await other.AcquireUploadLeaseAsync(11, default);
        await first.DisposeAsync();
        await using var second = await pending;
    }

    [Fact]
    public async Task CompletedAssetStoreRetryIsIdempotentAndNeverOverwritesAnotherImage()
    {
        disk.Settings.MaxObjects = 1;
        var id = Guid.NewGuid();
        var input = ManagedImageTestStorage.Image();
        var first = await storage.StoreValidatedAsync(id, new MemoryStream(input), "image/png", default);
        var second = await disk.Provider().StoreValidatedAsync(id, new MemoryStream(input), "image/png", default);
        Assert.Equal(first, second);
        var conflict = await Assert.ThrowsAsync<DraftOperationException>(() => storage.StoreValidatedAsync(id,
            new MemoryStream(ManagedImageTestStorage.Image("image/jpeg")), "image/jpeg", default));
        Assert.Equal(409, conflict.Status);
        Assert.Single(await storage.InspectAsync(default));
    }

    [Fact]
    public async Task OversizedUploadAndOversizedEncodedDimensionsAreRejected()
    {
        using (var request = UploadRequest(new byte[MapImageRules.MaxBytes + 1]))
            Assert.Equal(HttpStatusCode.RequestEntityTooLarge, (await host.Client.SendAsync(request)).StatusCode);
        var png = ManagedImageTestStorage.Image();
        System.Buffers.Binary.BinaryPrimitives.WriteUInt32BigEndian(png.AsSpan(16, 4), 9000);
        uint crc = uint.MaxValue;
        foreach (var value in png.AsSpan(12, 17))
        {
            crc ^= value;
            for (var bit = 0; bit < 8; bit++) crc = (crc >> 1) ^ ((crc & 1) != 0 ? 0xedb88320u : 0);
        }
        System.Buffers.Binary.BinaryPrimitives.WriteUInt32BigEndian(png.AsSpan(29, 4), ~crc);
        using var invalidSize = UploadRequest(png);
        Assert.Equal(HttpStatusCode.BadRequest, (await host.Client.SendAsync(invalidSize)).StatusCode);
        Assert.Empty(await storage.InspectAsync(default));
    }

    [Theory]
    [InlineData("missing")]
    [InlineData("relative")]
    [InlineData("webroot")]
    [InlineData("git")]
    public async Task UnsafeOrUnconfiguredRootsAreRejectedWithoutExposingTheirPath(string kind)
    {
        disk.Settings.RootPath = kind switch
        {
            "missing" => null,
            "relative" => "relative-storage",
            "webroot" => Path.Combine(disk.Environment.WebRootPath, "private-images"),
            _ => AppContext.BaseDirectory // Test output lives under the repository's .git ancestor.
        };
        using var request = UploadRequest(ManagedImageTestStorage.Image());
        var response = await host.Client.SendAsync(request);
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.DoesNotContain(disk.DirectoryPath, await response.Content.ReadAsStringAsync());
    }

    [Theory]
    [InlineData("../../appsettings.json")]
    [InlineData("C:\\Windows\\win.ini")]
    [InlineData("https://host/image.png")]
    public async Task PrivateProviderRejectsCallerSuppliedPathsInsteadOfResolvingThem(string key)
    {
        var error = await Assert.ThrowsAsync<DraftOperationException>(() => storage.OpenReadAsync(key, default));
        Assert.Equal(400, error.Status);
    }

    private async Task<MapImageMetadataDto> Upload(byte[] bytes, string mime = "image/png", string? name = null)
    {
        using var request = UploadRequest(bytes, mime, name);
        using var response = await host.Client.SendAsync(request);
        Assert.True(response.StatusCode == HttpStatusCode.Created, await response.Content.ReadAsStringAsync());
        var json = await response.Content.ReadAsStringAsync();
        Assert.DoesNotContain(disk.DirectoryPath, json);
        Assert.DoesNotContain("storageKey", json);
        return (await response.Content.ReadFromJsonAsync<MapImageMetadataDto>())!;
    }
    private static HttpRequestMessage UploadRequest(byte[] bytes, string mime = "image/png", string? name = null, string path = Base + "/images")
    {
        var request = new HttpRequestMessage(HttpMethod.Post, path) { Content = new ByteArrayContent(bytes) };
        request.Content.Headers.ContentType = new(mime);
        if (name is not null) request.Headers.Add("X-Image-File-Name", name);
        return request;
    }
}
