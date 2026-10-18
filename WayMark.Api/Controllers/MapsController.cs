using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using WayMark.Api.Contracts;
using WayMark.Api.Data;

namespace WayMark.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class MapsController(WayMarkDbContext dbContext) : ControllerBase
{
    [HttpGet("sites")]
    public async Task<ActionResult<IReadOnlyList<SiteDto>>> GetSites(
        CancellationToken cancellationToken)
    {
        var sites = await dbContext.Sites.AsNoTracking()
            .OrderBy(site => site.Code).ThenBy(site => site.Id)
            .Select(site => new SiteDto(site.Id, site.Name, site.Code, site.Address))
            .ToListAsync(cancellationToken);
        return Ok(sites);
    }

    [HttpGet("sites/{siteId:int}/buildings")]
    public async Task<ActionResult<IReadOnlyList<BuildingDto>>> GetBuildings(
        int siteId, CancellationToken cancellationToken)
    {
        if (!await dbContext.Sites.AsNoTracking()
                .AnyAsync(site => site.Id == siteId, cancellationToken))
        {
            return NotFound(new ProblemDetails { Status = 404, Title = "Site not found" });
        }

        var buildings = await dbContext.Buildings.AsNoTracking()
            .Where(building => building.SiteId == siteId)
            .OrderBy(building => building.BuildingCode).ThenBy(building => building.Id)
            .Select(building => new BuildingDto(
                building.Id, building.SiteId, building.Name, building.BuildingCode))
            .ToListAsync(cancellationToken);
        return Ok(buildings);
    }

    [HttpGet("buildings/{buildingId:int}/floors")]
    public async Task<ActionResult<IReadOnlyList<FloorDto>>> GetFloors(
        int buildingId, CancellationToken cancellationToken)
    {
        if (!await dbContext.Buildings.AsNoTracking()
                .AnyAsync(building => building.Id == buildingId, cancellationToken))
        {
            return NotFound(new ProblemDetails { Status = 404, Title = "Building not found" });
        }

        var floors = await dbContext.Floors.AsNoTracking()
            .Where(floor => floor.BuildingId == buildingId)
            .OrderBy(floor => floor.SortOrder).ThenBy(floor => floor.Id)
            .Select(floor => new FloorDto(floor.Id, floor.BuildingId, floor.Name,
                floor.FloorCode, floor.SortOrder, floor.FloorPlanImageUrl))
            .ToListAsync(cancellationToken);
        return Ok(floors);
    }

    [HttpGet("floors/{floorId:int}/graph")]
    public async Task<ActionResult<FloorGraphDto>> GetFloorGraph(
        int floorId, CancellationToken cancellationToken)
    {
        var floor = await dbContext.Floors.AsNoTracking()
            .Where(item => item.Id == floorId)
            .Select(item => new FloorDto(item.Id, item.BuildingId, item.Name,
                item.FloorCode, item.SortOrder, item.FloorPlanImageUrl))
            .SingleOrDefaultAsync(cancellationToken);
        if (floor is null)
        {
            return NotFound(new ProblemDetails { Status = 404, Title = "Floor not found" });
        }

        var nodes = await dbContext.NavigationNodes.AsNoTracking()
            .Where(node => node.FloorId == floorId)
            .OrderBy(node => node.Id)
            .Select(node => new NavigationNodeDto(node.Id, node.FloorId, node.NodeCode,
                node.Name, node.X, node.Y, node.NodeType.ToString()))
            .ToListAsync(cancellationToken);

        // A floor graph deliberately excludes transitions between floors.
        // Keep inactive edges visible, with their status, for map inspection.
        var edges = await (
            from edge in dbContext.NavigationEdges.AsNoTracking()
            join fromNode in dbContext.NavigationNodes.AsNoTracking()
                on edge.FromNodeId equals fromNode.Id
            join toNode in dbContext.NavigationNodes.AsNoTracking()
                on edge.ToNodeId equals toNode.Id
            where fromNode.FloorId == floorId && toNode.FloorId == floorId
            orderby edge.Id
            select new NavigationEdgeDto(edge.Id, edge.FromNodeId, edge.ToNodeId,
                edge.EdgeType.ToString(), edge.DistanceMeters, edge.IsActive,
                edge.IsAccessible))
            .ToListAsync(cancellationToken);

        return Ok(new FloorGraphDto(floor, nodes, edges));
    }
}
