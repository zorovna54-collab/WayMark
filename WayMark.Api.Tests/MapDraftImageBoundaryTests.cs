using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using WayMark.Api.Contracts;
using WayMark.Api.Data;
using WayMark.Api.Models;
using WayMark.Api.Services.MapDrafts;
using Xunit;

namespace WayMark.Api.Tests;

// Tests only the storage abstraction's HTTP/EF boundary. FakeStorage is NOT an image decoder.
// No actual image validation, server filesystem or object storage is exercised here.
public sealed class MapDraftImageBoundaryTests : IAsyncLifetime
{
    private const string Base = "/api/admin/floors/10/map-drafts";
    private readonly FakeStorage storage = new();
    private MapDraftTestHost test = null!;
    public async Task InitializeAsync()
    {
        test = new(storage); await test.StartAsync();
        Assert.Equal(HttpStatusCode.Created, (await test.Client.PostAsJsonAsync(Base, new MapDraftContent())).StatusCode);
    }
    public async Task DisposeAsync() => await test.DisposeAsync();

    [Fact]
    public async Task FakeProviderAssetRoundTripIsPrivateAndRevisionStoresOnlyItsId()
    {
        var asset = await Upload();
        Assert.Equal(900, asset.Width);
        using var read = await test.Client.GetAsync(Base + $"/images/{asset.Id}");
        Assert.Equal(HttpStatusCode.OK, read.StatusCode);
        Assert.Equal("image/png", read.Content.Headers.ContentType!.MediaType);
        Assert.True(read.Headers.CacheControl!.NoStore);
        Assert.Equal("nosniff", Assert.Single(read.Headers.GetValues("X-Content-Type-Options")));
        var content = MapDraftValidationTests.Content() with { ImageAssetId = asset.Id };
        var head = await test.Client.GetFromJsonAsync<MapDraftMetadataDto>(Base);
        using var create = await test.Client.PutAsJsonAsync(Base + $"/{head!.Id}", new SaveMapDraftRequest(1, content));
        Assert.Equal(HttpStatusCode.OK, create.StatusCode);
        using var scope = test.Scope();
        var revision = await scope.ServiceProvider.GetRequiredService<WayMarkDbContext>().FloorMapDraftRevisions.SingleAsync(x => x.Version == 2);
        Assert.Equal(asset.Id, revision.ImageAssetId);
        Assert.DoesNotContain("base64", revision.ContentJson, StringComparison.OrdinalIgnoreCase);
        test.Token(userId: "admin-b");
        Assert.Equal(HttpStatusCode.Forbidden, (await test.Client.GetAsync(Base + $"/images/{asset.Id}")).StatusCode);
    }

    [Fact]
    public async Task InvalidProviderMetadataIsRejectedAndOpaqueObjectIsCleanedUp()
    {
        storage.Width = 9000;
        using var body = Body();
        Assert.Equal(HttpStatusCode.ServiceUnavailable, (await test.Client.PostAsync(Base + "/images", body)).StatusCode);
        Assert.Equal(1, storage.Deletes);
        using var scope = test.Scope();
        Assert.Empty(await scope.ServiceProvider.GetRequiredService<WayMarkDbContext>().FloorMapImageAssets.ToListAsync());
    }

    [Fact]
    public async Task ImageMetadataSaveFailureRollsBackSqliteAndCleansUpPrivateObject()
    {
        test.Failure.FailAtWrite = 1;
        test.Failure.Armed = true;
        using var body = Body();
        Assert.Equal(HttpStatusCode.ServiceUnavailable, (await test.Client.PostAsync(Base + "/images", body)).StatusCode);
        Assert.Equal(1, storage.Deletes);
        using var scope = test.Scope();
        Assert.Empty(await scope.ServiceProvider.GetRequiredService<WayMarkDbContext>().FloorMapImageAssets.ToListAsync());
    }

    [Fact]
    public async Task FailureAfterImageCommitRetainsReferencedBytesAndDoesNotClaimSuccess()
    {
        test.PostCommitFailure.Armed = true;
        using var body = Body();
        Assert.Equal(HttpStatusCode.ServiceUnavailable, (await test.Client.PostAsync(Base + "/images", body)).StatusCode);
        Assert.Equal(0, storage.Deletes);
        using var scope = test.Scope();
        var asset = await scope.ServiceProvider.GetRequiredService<WayMarkDbContext>().FloorMapImageAssets.SingleAsync();
        await using var bytes = await storage.OpenReadAsync(asset.StorageKey, default);
        Assert.True(bytes.Length > 0);
    }

    [Fact]
    public async Task UnknownLengthStreamCannotBypassTenMiBLimit()
    {
        using var body = new UnknownLengthContent();
        body.Headers.ContentType = new("image/png");
        Assert.Equal(HttpStatusCode.RequestEntityTooLarge, (await test.Client.PostAsync(Base + "/images", body)).StatusCode);
        using var scope = test.Scope();
        Assert.Empty(await scope.ServiceProvider.GetRequiredService<WayMarkDbContext>().FloorMapImageAssets.ToListAsync());
    }

    [Fact]
    public async Task InvalidStoredPathNeverReachesTheProvider()
    {
        var id = Guid.NewGuid();
        using (var scope = test.Scope())
        {
            var db = scope.ServiceProvider.GetRequiredService<WayMarkDbContext>();
            db.FloorMapImageAssets.Add(new FloorMapImageAsset { Id = id, FloorId = 10, StorageKey = "../../appsettings.json",
                MimeType = "image/png", Width = 900, Height = 598, ByteLength = 10, Sha256 = new string('a', 64), CreatedBy = "admin-a" });
            await db.SaveChangesAsync();
        }
        Assert.Equal(HttpStatusCode.ServiceUnavailable, (await test.Client.GetAsync(Base + $"/images/{id}")).StatusCode);
        Assert.Equal(0, storage.Reads);
    }

    private async Task<MapImageMetadataDto> Upload()
    {
        using var body = Body();
        using var response = await test.Client.PostAsync(Base + "/images", body);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.DoesNotContain("storageKey", await response.Content.ReadAsStringAsync());
        return (await response.Content.ReadFromJsonAsync<MapImageMetadataDto>())!;
    }
    private static ByteArrayContent Body()
    {
        var body = new ByteArrayContent([137, 80, 78, 71]); // Deliberately NOT a real/decodeable PNG; fake contract only.
        body.Headers.ContentType = new("image/png");
        return body;
    }

    private sealed class FakeStorage : IMapImageStorage
    {
        private readonly Dictionary<string, byte[]> objects = [];
        public int Width { get; set; } = 900;
        public int Deletes { get; private set; }
        public int Reads { get; private set; }
        public async Task<StoredMapImage> StoreValidatedAsync(Guid id, Stream content, string mime, CancellationToken ct)
        {
            using var buffer = new MemoryStream();
            await content.CopyToAsync(buffer, ct);
            var bytes = buffer.ToArray();
            objects[id.ToString("N")] = bytes;
            return new(id.ToString("N"), mime, Width, 598, bytes.Length, Convert.ToHexStringLower(SHA256.HashData(bytes)));
        }
        public Task<Stream> OpenReadAsync(string key, CancellationToken ct)
        {
            Reads++;
            return Task.FromResult<Stream>(new MemoryStream(objects[key], false));
        }
        public Task DeleteUnreferencedAsync(string key, CancellationToken ct)
        {
            Deletes++; objects.Remove(key); return Task.CompletedTask;
        }
    }

    private sealed class UnknownLengthContent : HttpContent
    {
        protected override bool TryComputeLength(out long length) { length = 0; return false; }
        protected override async Task SerializeToStreamAsync(Stream stream, TransportContext? context)
        {
            var chunk = new byte[65536];
            for (var i = 0; i < MapImageRules.MaxBytes / chunk.Length; i++) await stream.WriteAsync(chunk);
            await stream.WriteAsync(new byte[1]);
        }
    }
}
