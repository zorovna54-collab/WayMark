using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using WayMark.Api.Contracts;
using WayMark.Api.Security;
using WayMark.Api.Services.MapDrafts;

namespace WayMark.Api.Controllers;

[ApiController]
[Route("api/admin/floors/{floorId:int}/map-drafts")]
[Authorize(Policy = WayMarkSecurity.MapAuthorPolicy)]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
[ServiceFilter(typeof(MapDraftExceptionFilter))]
public sealed class MapDraftsController(MapDraftService service) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<MapDraftMetadataDto>> Get(int floorId, CancellationToken ct)
        => Ok(await service.MetadataAsync(User, floorId, ct));

    [HttpPost]
    [RequestSizeLimit(MapDraftValidator.MaxDocumentBytes)]
    public async Task<ActionResult<MapDraftMetadataDto>> Create(int floorId, MapDraftContent content, CancellationToken ct)
    {
        var result = await service.CreateAsync(User, floorId, content, ct);
        return CreatedAtAction(nameof(Graph), new { floorId, draftId = result.Id, version = result.Version }, result);
    }

    [HttpPut("{draftId:guid}")]
    [RequestSizeLimit(MapDraftValidator.MaxDocumentBytes)]
    public async Task<ActionResult<MapDraftMetadataDto>> Save(int floorId, Guid draftId, SaveMapDraftRequest request, CancellationToken ct)
        => Ok(await service.SaveAsync(User, floorId, draftId, request, ct));

    [HttpGet("{draftId:guid}/graph")]
    public async Task<ActionResult<MapDraftGraphDto>> Graph(int floorId, Guid draftId, long? version, CancellationToken ct)
        => Ok(await service.GraphAsync(User, floorId, draftId, version, ct));

    [HttpGet("{draftId:guid}/versions")]
    public async Task<ActionResult<IReadOnlyList<MapDraftRevisionDto>>> Versions(int floorId, Guid draftId,
        CancellationToken ct, long? beforeVersion = null, int take = 50)
        => Ok(await service.VersionsAsync(User, floorId, draftId, beforeVersion, take, ct));

    [HttpGet("{draftId:guid}/places")]
    public async Task<ActionResult<IReadOnlyList<DraftPlaceDto>>> Places(int floorId, Guid draftId,
        CancellationToken ct, long? version = null, string? query = null)
        => Ok(await service.PlacesAsync(User, floorId, draftId, version, query, ct));

    [HttpPost("validate")]
    [RequestSizeLimit(MapDraftValidator.MaxDocumentBytes)]
    public async Task<ActionResult<DraftValidationDto>> Validate(int floorId, MapDraftContent content, CancellationToken ct)
    {
        var result = await service.ValidateAsync(User, floorId, content, ct);
        return result.IsValid ? Ok(result) : BadRequest(result);
    }

    [HttpPost("{draftId:guid}/restore")]
    [RequestSizeLimit(1024)]
    public async Task<ActionResult<MapDraftMetadataDto>> Restore(int floorId, Guid draftId, RestoreMapDraftRequest request, CancellationToken ct)
        => Ok(await service.RestoreAsync(User, floorId, draftId, request, ct));

    // Raw image body, not local JSON v2 Base64 or a multipart filesystem filename.
    [HttpPost("images")]
    [RequestSizeLimit(MapImageRules.MaxBytes)]
    public async Task<ActionResult<MapImageMetadataDto>> Upload(int floorId, CancellationToken ct)
    {
        var image = await service.UploadImageAsync(User, floorId, Request.Body, Request.ContentType, Request.ContentLength, ct,
            Request.Headers.TryGetValue("X-Image-File-Name", out var name) ? name.ToString() : null);
        return CreatedAtAction(nameof(Image), new { floorId, assetId = image.Id }, image);
    }

    [HttpGet("images/{assetId:guid}")]
    public async Task<IActionResult> Image(int floorId, Guid assetId, CancellationToken ct)
    {
        var image = await service.ImageAsync(User, floorId, assetId, ct);
        Response.Headers["X-Content-Type-Options"] = "nosniff";
        Response.Headers["Content-Security-Policy"] = "default-src 'none'; sandbox";
        Response.Headers.CacheControl = "no-store";
        return File(image.Content, image.Mime);
    }

    [HttpGet("images")]
    public async Task<ActionResult<IReadOnlyList<MapImageMetadataDto>>> Images(int floorId, CancellationToken ct, int page = 1, int take = 50)
        => Ok(await service.ImagesAsync(User, floorId, page, take, ct));
}
