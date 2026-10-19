using System.Data.Common;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using WayMark.Api.Contracts;
using WayMark.Api.Services.Routing;

namespace WayMark.Api.Controllers;

[ApiController]
[Route("api/routes")]
[Authorize]
public class RoutesController(IRoutePlanner planner, ILogger<RoutesController> logger) : ControllerBase
{
    [HttpPost]
    [ProducesResponseType(typeof(RouteResponseDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status409Conflict)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status422UnprocessableEntity)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status500InternalServerError)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status503ServiceUnavailable)]
    public async Task<ActionResult<RouteResponseDto>> FindRoute(
        [FromBody] RouteRequest request, CancellationToken cancellationToken,
        [FromQuery] bool accessibleOnly = false)
    {
        try
        {
            var result = await planner.PlanAsync(request.StartWayMarkCode.Trim(),
                request.DestinationWayMarkCode.Trim(), accessibleOnly, cancellationToken, request.Options);
            return result.Status switch
            {
                RoutePlanStatus.Success when result.Route is not null => Ok(result.Route),
                RoutePlanStatus.StartWayMarkNotFound => Failure(404, "start_waymark_not_found", "Start WayMark not found"),
                RoutePlanStatus.DestinationWayMarkNotFound => Failure(404, "destination_waymark_not_found", "Destination WayMark not found"),
                RoutePlanStatus.StartNotMapped => Failure(409, "start_not_mapped", "Start WayMark has no navigation node"),
                RoutePlanStatus.DestinationNotMapped => Failure(409, "destination_not_mapped", "Destination WayMark has no navigation node"),
                RoutePlanStatus.StartNodeNotFound => Failure(409, "start_node_not_found", "Start navigation node or floor is unavailable"),
                RoutePlanStatus.DestinationNodeNotFound => Failure(409, "destination_node_not_found", "Destination navigation node or floor is unavailable"),
                RoutePlanStatus.NoRoute => Failure(422, "no_route", "No route exists for the requested direction and filters"),
                RoutePlanStatus.AccessibilityNotVerified => Failure(422, "accessibility_not_verified", "Wheelchair routing requires verified accessibility metadata; IsAccessible alone is insufficient"),
                _ => Failure(500, "invalid_graph", "Map data cannot be used to calculate a route")
            };
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (DbException exception)
        {
            logger.LogError(exception, "Route map data could not be read.");
            return Failure(503, "route_data_unavailable", "Map data is temporarily unavailable");
        }
        catch (Exception exception)
        {
            logger.LogError(exception, "Route calculation failed.");
            return Failure(500, "route_calculation_failed", "Route calculation failed");
        }
    }

    private ObjectResult Failure(int status, string code, string title) => StatusCode(status,
        new ProblemDetails { Status = status, Title = title, Extensions = { ["code"] = code } });
}
