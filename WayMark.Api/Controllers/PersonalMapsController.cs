using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using WayMark.Api.Services.MapDrafts;

namespace WayMark.Api.Controllers;

[ApiController, Route("api/me/map-workspaces"), Authorize]
[ServiceFilter(typeof(MapDraftExceptionFilter))]
public sealed class PersonalMapsController(PersonalMapOnboarding onboarding) : ControllerBase
{
    [HttpPost, RequestSizeLimit(8192)]
    public async Task<IActionResult> Create(StartPersonalMapRequest request, CancellationToken ct)
        => StatusCode(201, await onboarding.StartAsync(User, request, ct));
    [HttpPost("{mapId:guid}/floors"), RequestSizeLimit(2048)]
    public async Task<IActionResult> Floor(Guid mapId, AddPersonalFloorRequest request, CancellationToken ct)
        => Ok(await onboarding.AddFloorAsync(User, mapId, request, ct));
}
