using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using WayMark.Api.Contracts;
using WayMark.Api.Data;
using WayMark.Api.Models;

namespace WayMark.Api.Services.MapDrafts;

public sealed class MapDraftService(WayMarkDbContext db, IDraftSiteAccess access,
    MapDraftValidator validator, IMapImageStorage images, TimeProvider clock, ILogger<MapDraftService> logger,
    IOptions<MapDraftLimitsOptions> limits)
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    public async Task<MapDraftMetadataDto> MetadataAsync(ClaimsPrincipal user, int floorId, CancellationToken ct)
    {
        var scope = await access.RequireAsync(user, floorId, ct);
        var head = await db.FloorMapDrafts.AsNoTracking().SingleOrDefaultAsync(x => x.FloorId == floorId, ct) ?? throw Missing();
        return Metadata(head, scope);
    }

    public async Task<MapDraftMetadataDto> CreateAsync(ClaimsPrincipal user, int floorId, MapDraftContent? content, CancellationToken ct)
    {
        var scope = await access.RequireAsync(user, floorId, ct);
        if (limits.Value.MaxRevisionsPerFloor < 1) throw new DraftOperationException(503, "draft_quota_configuration", "Invalid revision quota configuration");
        if (await db.FloorMapDrafts.AsNoTracking().AnyAsync(x => x.FloorId == floorId, ct)) throw Conflict();
        var validation = await ValidateContentAsync(scope, content, ct);
        RequireValid(validation);
        var now = clock.GetUtcNow();
        var head = new FloorMapDraft { Id = Guid.NewGuid(), FloorId = floorId, Version = 1,
            CreatedAt = now, UpdatedAt = now, CreatedBy = scope.UserId, UpdatedBy = scope.UserId };
        db.FloorMapDrafts.Add(head);
        AddRevision(head, content!, scope.UserId, now);
        // Head and immutable revision are saved atomically in ONE relational SaveChanges.
        await PersistAsync(head, null, ct);
        return Metadata(head, scope);
    }

    public async Task<MapDraftMetadataDto> SaveAsync(ClaimsPrincipal user, int floorId, Guid draftId,
        SaveMapDraftRequest request, CancellationToken ct)
    {
        var scope = await access.RequireAsync(user, floorId, ct);
        var head = await HeadAsync(floorId, draftId, ct);
        if (request.ExpectedVersion <= 0) throw Invalid("version_required", "ExpectedVersion must be positive");
        if (request.ExpectedVersion != head.Version) throw Conflict();
        var validation = await ValidateContentAsync(scope, request.Content, ct);
        RequireValid(validation);
        return await AppendAsync(head, request.Content!, scope, ct);
    }

    public async Task<MapDraftMetadataDto> RestoreAsync(ClaimsPrincipal user, int floorId, Guid draftId,
        RestoreMapDraftRequest request, CancellationToken ct)
    {
        var scope = await access.RequireAsync(user, floorId, ct);
        var head = await HeadAsync(floorId, draftId, ct);
        if (request.ExpectedVersion <= 0 || request.SourceVersion <= 0) throw Invalid("invalid_version", "Versions must be positive");
        if (head.Version != request.ExpectedVersion) throw Conflict();
        var old = await RevisionAsync(draftId, request.SourceVersion, ct);
        var content = Read(old);
        RequireValid(await ValidateContentAsync(scope, content, ct));
        return await AppendAsync(head, content, scope, ct);
    }

    public async Task<MapDraftGraphDto> GraphAsync(ClaimsPrincipal user, int floorId, Guid draftId, long? version, CancellationToken ct)
    {
        await access.RequireAsync(user, floorId, ct);
        var head = await db.FloorMapDrafts.AsNoTracking().SingleOrDefaultAsync(x => x.Id == draftId && x.FloorId == floorId, ct) ?? throw Missing();
        if (version <= 0) throw Invalid("invalid_version", "Version must be positive");
        var revision = await RevisionAsync(draftId, version ?? head.Version, ct);
        return new(draftId, floorId, revision.Version, "Draft", Read(revision));
    }

    public async Task<IReadOnlyList<MapDraftRevisionDto>> VersionsAsync(ClaimsPrincipal user, int floorId, Guid draftId,
        long? beforeVersion, int take, CancellationToken ct)
    {
        await access.RequireAsync(user, floorId, ct);
        await HeadAsync(floorId, draftId, ct);
        if (take is < 1 or > 100 || beforeVersion <= 0) throw Invalid("invalid_page", "Take must be 1–100 and beforeVersion positive");
        return await db.FloorMapDraftRevisions.AsNoTracking().Where(x => x.DraftId == draftId
            && (!beforeVersion.HasValue || x.Version < beforeVersion.Value)).OrderByDescending(x => x.Version)
            .Take(take).Select(x => new MapDraftRevisionDto(x.Version, x.CreatedAt, x.CreatedBy)).ToListAsync(ct);
    }

    public async Task<IReadOnlyList<DraftPlaceDto>> PlacesAsync(ClaimsPrincipal user, int floorId, Guid draftId,
        long? version, string? query, CancellationToken ct)
    {
        if (query?.Length > 200) throw Invalid("invalid_query", "Search query is too long");
        var graph = await GraphAsync(user, floorId, draftId, version, ct);
        var text = query?.Trim() ?? string.Empty;
        return graph.Content.Places!.Where(x => x.Name.Contains(text, StringComparison.OrdinalIgnoreCase)
            || x.PlaceCode.Contains(text, StringComparison.OrdinalIgnoreCase)).ToArray();
    }

    public async Task<DraftValidationDto> ValidateAsync(ClaimsPrincipal user, int floorId, MapDraftContent? content, CancellationToken ct)
        => await ValidateContentAsync(await access.RequireAsync(user, floorId, ct), content, ct);

    private async Task<DraftValidationDto> ValidateContentAsync(DraftFloorScope scope, MapDraftContent? content, CancellationToken ct)
    {
        if (content is not null && Encoding.UTF8.GetByteCount(JsonSerializer.Serialize(content, Json)) > MapDraftValidator.MaxDocumentBytes)
            throw new DraftOperationException(413, "document_too_large", "Draft document exceeds 2 MiB");
        var result = validator.Validate(content);
        if (!result.IsValid) return result;
        var errors = result.Errors.ToList();
        if (content!.ImageAssetId is Guid assetId)
        {
            var image = await db.FloorMapImageAssets.AsNoTracking().SingleOrDefaultAsync(x => x.Id == assetId && x.FloorId == scope.FloorId, ct);
            if (image is null) errors.Add(new("image_reference", "imageAssetId", "Image is not an available asset of this floor"));
            else { await using var verified = await OpenVerifiedImageAsync(image, ct); }
        }

        var sources = content.Nodes!.Where(x => x.SourceNodeId.HasValue).Select(x => x.SourceNodeId!.Value).ToArray();
        var sourceIds = await db.NavigationNodes.AsNoTracking().Where(x => x.FloorId == scope.FloorId && sources.Contains(x.Id))
            .Select(x => x.Id).ToListAsync(ct);
        if (sources.Distinct().Count() != sources.Length || sources.Any(id => !sourceIds.Contains(id)))
            errors.Add(new("source_node_scope", "nodes", "Source nodes must be distinct existing nodes of this floor"));
        foreach (var node in content.Nodes!.Where(x => x.ExistingWayMarkCode is not null))
        {
            // A reference is only provenance; it never changes a QR mapping or becomes a NodeCode.
            var qr = await db.WayMarks.AsNoTracking().SingleOrDefaultAsync(x => x.WayMarkCode == node.ExistingWayMarkCode, ct);
            if (qr is null || node.SourceNodeId is null || qr.NavigationNodeId != node.SourceNodeId || !sourceIds.Contains(node.SourceNodeId.Value))
                errors.Add(new("qr_reference", "nodes", "QR reference must match the source node on this floor"));
        }
        foreach (var transition in content.Transitions!)
        {
            var target = await (from draft in db.FloorMapDrafts.AsNoTracking()
                join floor in db.Floors.AsNoTracking() on draft.FloorId equals floor.Id
                join building in db.Buildings.AsNoTracking() on floor.BuildingId equals building.Id
                where draft.Id == transition.TargetDraftId && building.SiteId == scope.SiteId && floor.Id != scope.FloorId
                select draft).SingleOrDefaultAsync(ct);
            var revision = target is null ? null : await db.FloorMapDraftRevisions.AsNoTracking().SingleOrDefaultAsync(x =>
                x.DraftId == target.Id && x.Version == transition.TargetVersion, ct);
            var targetNode = revision is null ? null : Read(revision).Nodes!.SingleOrDefault(x => x.Id == transition.TargetNodeId);
            if (targetNode is null || !MapDraftValidator.Connector(targetNode.NodeType, transition.EdgeType))
                errors.Add(new("transition_scope", "transitions", "Target must be a compatible node in a pinned revision of another floor in this Site"));
        }
        return new(errors, result.Warnings);
    }

    public async Task<MapImageMetadataDto> UploadImageAsync(ClaimsPrincipal user, int floorId, Stream content,
        string? mime, long? length, CancellationToken ct, string? fileName = null)
    {
        var scope = await access.RequireAsync(user, floorId, ct);
        if (!MapImageRules.Mime(mime)) throw Invalid("invalid_image_type", "Only image/png and image/jpeg are supported");
        if (length == 0) throw Invalid("empty_image", "Image cannot be empty");
        if (length > MapImageRules.MaxBytes) throw new DraftOperationException(413, "image_too_large", "Image exceeds 10 MiB");
        MapImageCodec.ValidateFileName(fileName, mime);
        if (!await db.FloorMapDrafts.AsNoTracking().AnyAsync(x => x.FloorId == floorId, ct)) throw Missing();
        await using var uploadLease = await images.AcquireUploadLeaseAsync(floorId, ct);
        var policy = limits.Value;
        if (policy.MaxImagesPerFloor < 1 || policy.MaxImageBytesPerFloor < 1) throw new DraftOperationException(503, "draft_quota_configuration", "Invalid image quota configuration");
        var usage = await db.FloorMapImageAssets.AsNoTracking().Where(x => x.FloorId == floorId).Select(x => x.ByteLength).ToListAsync(ct);
        var remaining = policy.MaxImageBytesPerFloor - usage.Sum();
        if (usage.Count >= policy.MaxImagesPerFloor || remaining <= 0) throw new DraftOperationException(409, "floor_image_quota", "Floor image quota reached");
        var id = Guid.NewGuid();
        await using var bounded = new BoundedImageStream(content);
        var stored = await images.StoreValidatedAsync(id, bounded, mime!, remaining, ct);
        if (!MapImageRules.Metadata(stored, id) || stored.MimeType != mime)
        {
            await CleanupAsync(id.ToString("N"));
            throw new DraftOperationException(503, "image_storage_invalid", "Image provider did not return validated metadata");
        }
        if (stored.ByteLength > remaining)
        {
            await CleanupAsync(stored.StorageKey);
            throw new DraftOperationException(409, "floor_image_quota", "Floor image quota reached");
        }
        var asset = new FloorMapImageAsset { Id = id, FloorId = floorId, StorageKey = stored.StorageKey,
            MimeType = stored.MimeType, Width = stored.Width, Height = stored.Height, ByteLength = stored.ByteLength,
            Sha256 = stored.Sha256, CreatedAt = clock.GetUtcNow(), CreatedBy = scope.UserId };
        db.FloorMapImageAssets.Add(asset);
        try { await db.SaveChangesAsync(ct); }
        catch
        {
            // A transport/cancellation failure can leave the commit outcome uncertain.
            // Never delete bytes if SQL might already reference them. Reconcile later
            // when even a bounded follow-up read cannot establish the outcome.
            using var check = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            try
            {
                if (!await db.FloorMapImageAssets.AsNoTracking().AnyAsync(x => x.Id == id, check.Token))
                    await CleanupAsync(stored.StorageKey);
                else logger.LogWarning("Image save outcome uncertain; private object retained for reconciliation");
            }
            catch { logger.LogWarning("Could not establish image save outcome; private object retained for reconciliation"); }
            throw;
        }
        try { await images.ConfirmMetadataAsync(stored.StorageKey, ct); }
        catch { logger.LogWarning("Image metadata saved; durable manifest confirmation needs reconciliation"); }
        return new(asset.Id, asset.FloorId, asset.MimeType, asset.Width, asset.Height, asset.ByteLength, asset.Sha256);
    }

    public async Task<(Stream Content, string Mime)> ImageAsync(ClaimsPrincipal user, int floorId, Guid assetId, CancellationToken ct)
    {
        await access.RequireAsync(user, floorId, ct);
        var asset = await db.FloorMapImageAssets.AsNoTracking().SingleOrDefaultAsync(x => x.Id == assetId && x.FloorId == floorId, ct) ?? throw Missing();
        return (await OpenVerifiedImageAsync(asset, ct), asset.MimeType);
    }

    public async Task<IReadOnlyList<MapImageMetadataDto>> ImagesAsync(ClaimsPrincipal user, int floorId, int page, int take, CancellationToken ct)
    {
        await access.RequireAsync(user, floorId, ct);
        if (page is < 1 or > 10000 || take is < 1 or > 100) throw Invalid("invalid_page", "Page must be 1–10000 and take 1–100");
        return await db.FloorMapImageAssets.AsNoTracking().Where(x => x.FloorId == floorId).OrderBy(x => x.Id)
            .Skip((page - 1) * take).Take(take).Select(x => new MapImageMetadataDto(x.Id, x.FloorId, x.MimeType,
                x.Width, x.Height, x.ByteLength, x.Sha256)).ToListAsync(ct);
    }

    internal async Task<Stream> OpenVerifiedImageAsync(FloorMapImageAsset asset, CancellationToken ct)
    {
        if (!MapImageRules.Metadata(new(asset.StorageKey, asset.MimeType, asset.Width, asset.Height, asset.ByteLength, asset.Sha256), asset.Id))
            throw new DraftOperationException(503, "image_metadata_invalid", "Private image metadata is unavailable");
        var stream = await images.OpenReadAsync(asset.StorageKey, ct);
        try
        {
            if (!stream.CanSeek || stream.Length != asset.ByteLength || stream.Length > MapImageRules.MaxBytes)
                throw new DraftOperationException(503, "image_integrity_failure", "Image integrity check failed");
            var hash = Convert.ToHexStringLower(await SHA256.HashDataAsync(stream, ct));
            if (hash != asset.Sha256) throw new DraftOperationException(503, "image_integrity_failure", "Image integrity check failed");
            stream.Position = 0;
            return stream;
        }
        catch { await stream.DisposeAsync(); throw; }
    }

    private async Task CleanupAsync(string key)
    {
        try { await images.DeleteUnreferencedAsync(key, CancellationToken.None); }
        catch { logger.LogWarning("Draft image cleanup failed; an operator must reconcile unreferenced private assets"); }
    }
    private async Task<MapDraftMetadataDto> AppendAsync(FloorMapDraft head, MapDraftContent content, DraftFloorScope scope, CancellationToken ct)
    {
        if (limits.Value.MaxRevisionsPerFloor < 1) throw new DraftOperationException(503, "draft_quota_configuration", "Invalid revision quota configuration");
        if (head.Version >= limits.Value.MaxRevisionsPerFloor) throw new DraftOperationException(409, "draft_revision_quota", "Revision limit reached; existing history is retained");
        if (head.Version == long.MaxValue) throw Conflict();
        head.Version++;
        head.UpdatedAt = clock.GetUtcNow();
        head.UpdatedBy = scope.UserId;
        AddRevision(head, content, scope.UserId, head.UpdatedAt);
        // EF compares the original concurrency token; head + revision succeed together or roll back together.
        await PersistAsync(head, head.Version - 1, ct);
        return Metadata(head, scope);
    }
    private async Task PersistAsync(FloorMapDraft head, long? expectedVersion, CancellationToken ct)
    {
        try { await db.SaveChangesAsync(ct); }
        catch (DbUpdateConcurrencyException) { throw Conflict(); }
        catch (DbUpdateException)
        {
            // A relational provider may INSERT the revision before UPDATE checks the token.
            // The revision PK also guards concurrent saves. After EF's rollback, read a fresh
            // head without tracking; normalize an actual concurrent winner to 409 on either DB.
            var actual = await db.FloorMapDrafts.AsNoTracking().Where(x => x.FloorId == head.FloorId)
                .Select(x => new { x.Id, x.Version }).SingleOrDefaultAsync(ct);
            if (actual is not null && (expectedVersion is null || actual.Id != head.Id || actual.Version != expectedVersion.Value))
                throw Conflict();
            throw;
        }
    }
    private void AddRevision(FloorMapDraft head, MapDraftContent content, string userId, DateTimeOffset now)
        => db.FloorMapDraftRevisions.Add(new FloorMapDraftRevision { Draft = head, DraftId = head.Id,
            Version = head.Version, ContentJson = JsonSerializer.Serialize(content, Json), ImageAssetId = content.ImageAssetId,
            CreatedAt = now, CreatedBy = userId });
    private async Task<FloorMapDraft> HeadAsync(int floorId, Guid id, CancellationToken ct)
        => await db.FloorMapDrafts.SingleOrDefaultAsync(x => x.Id == id && x.FloorId == floorId, ct) ?? throw Missing();
    private async Task<FloorMapDraftRevision> RevisionAsync(Guid id, long version, CancellationToken ct)
        => await db.FloorMapDraftRevisions.AsNoTracking().SingleOrDefaultAsync(x => x.DraftId == id && x.Version == version, ct) ?? throw Missing();
    private static MapDraftContent Read(FloorMapDraftRevision revision)
        => JsonSerializer.Deserialize<MapDraftContent>(revision.ContentJson, Json)
            ?? throw new DraftOperationException(503, "draft_unavailable", "Draft revision is unavailable");
    private static MapDraftMetadataDto Metadata(FloorMapDraft head, DraftFloorScope scope)
        => new(head.Id, scope.SiteId, scope.BuildingId, head.FloorId, head.Version, head.Status,
            head.CreatedAt, head.UpdatedAt, head.CreatedBy, head.UpdatedBy);
    private static void RequireValid(DraftValidationDto result)
    {
        if (!result.IsValid) throw Invalid("invalid_draft", result.Errors[0].Message);
    }
    private static DraftOperationException Invalid(string code, string message) => new(400, code, message);
    private static DraftOperationException Conflict() => new(409, "draft_version_conflict", "Draft already exists or its version changed; reload before saving");
    private static DraftOperationException Missing() => new(404, "draft_resource_not_found", "Draft resource was not found on this floor");
}
