using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using WayMark.Api.Contracts;
using WayMark.Api.Security;
using WayMark.Api.Services.MapDrafts;

namespace WayMark.Api.Controllers;

[ApiController, Route("api/admin/map-projects"), Authorize(Policy = WayMarkSecurity.MapAuthorPolicy)]
[ServiceFilter(typeof(MapDraftExceptionFilter))]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class MapProjectsController(MapProjectService service) : ControllerBase
{
    [HttpGet] public async Task<IActionResult> List(CancellationToken ct) => Ok(await service.ListAsync(User, ct));
    [HttpGet("{id:guid}")] public async Task<IActionResult> Get(Guid id, CancellationToken ct) => Ok(await service.GetAsync(User, id, ct));
    [HttpGet("{id:guid}/publish-readiness")]
    public async Task<IActionResult> Readiness(Guid id, CancellationToken ct) => Ok(await service.ReadinessAsync(User, id,
        HttpContext.RequestServices.GetRequiredService<IMapImageStorage>(), ct));
    [HttpPost, RequestSizeLimit(MapProjectService.MaxBytes)]
    public async Task<IActionResult> Create(CreateMapProjectRequest r, CancellationToken ct)
    {
        var p = await service.CreateAsync(User, r, ct);
        return CreatedAtAction(nameof(Get), new { id = p.Id }, p);
    }
    [HttpPut("{id:guid}"), RequestSizeLimit(MapProjectService.MaxBytes)]
    public async Task<IActionResult> Save(Guid id, SaveMapProjectRequest r, CancellationToken ct) => Ok(await service.SaveAsync(User, id, r, ct));
    [HttpPost("{id:guid}/publish"), RequestSizeLimit(1024)]
    public async Task<IActionResult> Publish(Guid id, PublishMapRequest r, CancellationToken ct) => Ok(await service.PublishAsync(User, id, r, ct));
    [HttpGet("{id:guid}/qrs")] public async Task<IActionResult> Qrs(Guid id, CancellationToken ct) => Ok(await service.QrsAsync(User, id, ct));
    [HttpPost("{id:guid}/qrs"), RequestSizeLimit(1024)]
    public async Task<IActionResult> Qr(Guid id, CreateNodeQrRequest r, CancellationToken ct) => Ok(await service.CreateQrAsync(User, id, r, ct));
    [HttpPost("{id:guid}/qrs/{qrId:guid}/revoke"), RequestSizeLimit(1024)]
    public async Task<IActionResult> Revoke(Guid id, Guid qrId, CancellationToken ct) => Ok(await service.RevokeAsync(User, id, qrId, ct));
}

[ApiController, Route("api/public"), AllowAnonymous]
[ServiceFilter(typeof(MapDraftExceptionFilter))]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class PublicMapsController(MapProjectService service) : ControllerBase
{
    [HttpGet("qr/{token}")]
    public async Task<IActionResult> Resolve(string token, CancellationToken ct) => Ok(await service.ResolveAsync(token, ct));
    [HttpGet("maps/{id:guid}/versions/{version:long}")]
    public async Task<IActionResult> Map(Guid id, long version, CancellationToken ct) => Ok(await service.PublicAsync(id, version, ct));
    [HttpGet("maps/{id:guid}/versions/{version:long}/images/{assetId:guid}")]
    public async Task<IActionResult> Image(Guid id, long version, Guid assetId, CancellationToken ct)
    {
        var image = await service.PublicImageAsync(id, version, assetId, ct);
        Response.Headers["X-Content-Type-Options"] = "nosniff";
        Response.Headers["Content-Security-Policy"] = "default-src 'none'; sandbox";
        return File(image.Content, image.Mime);
    }
}
