using System.Security.Claims;
using System.Text.Json.Serialization;
using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.EntityFrameworkCore;
using Microsoft.Data.SqlClient;
using WayMark.Api.Contracts;
using WayMark.Api.Data;
using WayMark.Api.Models;
using WayMark.Api.Services.MapDrafts;
using WayMark.Api.Services.Routing;

namespace WayMark.Api.Controllers;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record StartHistoryRequest(Guid SessionId, [Required, RegularExpression("^[a-f0-9]{64}$")] string QrToken,
    Guid? DestinationFloorKey = null, Guid? DestinationNodeId = null);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record HistoryDestinationRequest(Guid DestinationFloorKey, Guid DestinationNodeId);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record EndHistoryRequest([Required, RegularExpression("^(Completed|Cancelled)$")] string Status);
public sealed record HistoryItemDto(Guid Id, Guid MapId, long PublishedVersion, string MapName, string StartName,
    string DestinationName, DateTime StartedAtUtc, DateTime? EndedAtUtc, string Status,
    Guid StartNodeId, Guid? StartFloorKey, Guid? DestinationNodeId, Guid? DestinationFloorKey,
    DateTime ScannedAtUtc, DateTime? NavigationStartedAtUtc, decimal? DistanceMeters);

[ApiController, Route("api/me/navigation-history"), Authorize]
[ServiceFilter(typeof(MapDraftExceptionFilter))]
[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
public sealed class NavigationHistoryController(WayMarkDbContext db, MapProjectService maps, DijkstraRouter router) : ControllerBase, IAsyncActionFilter
{
    [NonAction]
    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        var executed = await next();
        if (executed.Exception?.GetBaseException() is SqlException { Number: 208 } error && error.Message.Contains("NavigationHistory", StringComparison.OrdinalIgnoreCase)) {
            executed.ExceptionHandled = true;
            executed.Result = StatusCode(503, new { code = "history_schema_unavailable", message = "Lịch sử chưa được triển khai trên máy chủ. Tuyến đường vẫn sử dụng được." });
        }
    }
    private string Subject => User.FindFirstValue(ClaimTypes.NameIdentifier) ?? throw new DraftOperationException(401, "unauthorized", "Sign in required");
    private static DateTime Utc(DateTime d) => DateTime.SpecifyKind(d, DateTimeKind.Utc);
    private static HistoryItemDto Dto(NavigationHistory h) => new(h.Id, h.MapId, h.PublishedVersion, h.MapName,
        h.StartName, h.DestinationName, Utc(h.StartedAtUtc), h.EndedAtUtc is DateTime end ? Utc(end) : null,
        h.Status, h.StartNodeId, h.StartFloorKey, h.DestinationNodeId, h.DestinationFloorKey,
        Utc(h.ScannedAtUtc ?? h.StartedAtUtc), h.NavigationStartedAtUtc is DateTime nav ? Utc(nav) : h.ScannedAtUtc is null ? Utc(h.StartedAtUtc) : null, h.DistanceMeters);
    private Task<NavigationHistory?> Own(Guid id, CancellationToken ct) => db.NavigationHistory.SingleOrDefaultAsync(x => x.Id == id && x.UserId == Subject, ct);
    [HttpGet]
    public async Task<IActionResult> List(CancellationToken ct) => Ok((await db.NavigationHistory.AsNoTracking()
        .Where(x => x.UserId == Subject).OrderByDescending(x => x.ScannedAtUtc ?? x.StartedAtUtc).ThenByDescending(x => x.Id).Take(100).ToListAsync(ct)).Select(Dto));
    [HttpGet("{id:guid}")]
    public async Task<IActionResult> Detail(Guid id, CancellationToken ct) => await Own(id, ct) is {} h ? Ok(Dto(h)) : NotFound();

    private async Task SelectDestination(NavigationHistory h, Guid floorKey, Guid nodeId, CancellationToken ct)
    {
        var map = await maps.PublicAsync(h.MapId, h.PublishedVersion, ct);
        var floor = map.Content.Floors.SingleOrDefault(f => f.Id == floorKey);
        var destination = floor?.Content.Nodes?.SingleOrDefault(n => n.Id == nodeId);
        if (destination is null || (!destination.SearchableAsDestination && !floor!.Content.Places!.Any(p => p.EntranceNodeIds!.Contains(nodeId))))
            throw new DraftOperationException(400, "history_destination_invalid", "Điểm đến không thuộc snapshot hoặc không tìm kiếm được.");
        var ids = map.Content.Floors.SelectMany(f => f.Content.Nodes!).Select((n,i) => (n.Id, Value:i+1)).ToDictionary(x => x.Id, x => x.Value);
        var edges = map.Content.Floors.SelectMany(f => f.Content.Edges!).Select(e => new RoutingEdge(0,ids[e.FromNodeId],ids[e.ToNodeId],e.DistanceMeters ?? 0,e.IsActive, EdgeType:e.EdgeType))
            .Concat(map.Content.Links.Select(e => new RoutingEdge(0,ids[e.FromNode],ids[e.ToNode],e.DistanceMeters,e.Active,EdgeType:Enum.Parse<NavigationEdgeType>(e.Type))))
            .Select((e,i) => e with { Id = i+1 }).ToArray();
        var path = router.FindPath(ids.Values.ToArray(), edges, ids[h.StartNodeId], ids[nodeId], cancellationToken:ct);
        if (path.Status != PathStatus.Success) throw new DraftOperationException(422, "history_no_route", "Không có tuyến hợp lệ đến điểm đích.");
        h.DestinationNodeId = nodeId; h.DestinationFloorKey = floorKey;
        h.DestinationName = destination.DisplayName ?? destination.Name; h.DistanceMeters = path.TotalDistanceMeters;
    }
    private async Task<IActionResult> Save(NavigationHistory h, CancellationToken ct)
    {
        try { await db.SaveChangesAsync(ct); return Ok(Dto(h)); }
        catch (DbUpdateConcurrencyException) { return Conflict(new { code = "history_session_conflict" }); }
    }
    [HttpPost, RequestSizeLimit(2048)]
    public async Task<IActionResult> Start(StartHistoryRequest request, CancellationToken ct)
    {
        if (request.SessionId == Guid.Empty || request.DestinationFloorKey.HasValue != request.DestinationNodeId.HasValue) return BadRequest();
        var old = await Own(request.SessionId, ct);
        if (old is not null) {
            var qr = await db.MapNodeQrs.AsNoTracking().SingleOrDefaultAsync(q => q.Id == old.StartQrId, ct);
            if (qr?.Token != request.QrToken || (request.DestinationNodeId.HasValue &&
                (old.DestinationFloorKey != request.DestinationFloorKey || old.DestinationNodeId != request.DestinationNodeId)))
                return Conflict(new { code = "history_session_conflict" });
            return Ok(Dto(old));
        }
        if (await db.NavigationHistory.AnyAsync(x => x.Id == request.SessionId, ct)) return Conflict(new { code = "history_session_conflict" });
        var r = await maps.ResolveAsync(request.QrToken, ct); // Active/public/version validation BEFORE any record.
        var map = await maps.PublicAsync(r.MapId, r.Version, ct);
        var start = await db.MapNodeQrs.AsNoTracking().SingleAsync(q => q.Token == request.QrToken, ct);
        var now = DateTime.UtcNow;
        var h = new NavigationHistory { Id=request.SessionId, UserId=Subject, MapId=r.MapId, PublishedVersion=r.Version,
            StartQrId=start.Id, StartNodeId=r.NodeId, StartFloorKey=r.FloorKey, MapName=map.Name, StartName=r.NodeName,
            DestinationName="", StartedAtUtc=now, ScannedAtUtc=now, Status="Scanned" };
        // Compatibility with clients that used the old destination-at-start request.
        if (request.DestinationNodeId is Guid destination) {
            await SelectDestination(h, request.DestinationFloorKey!.Value, destination, ct);
            h.Status="InProgress"; h.NavigationStartedAtUtc=now;
        }
        db.NavigationHistory.Add(h);
        try { await db.SaveChangesAsync(ct); }
        catch (DbUpdateException e) when (e.GetBaseException() is not SqlException { Number:208 }) {
            db.Entry(h).State = EntityState.Detached;
            var winner = await Own(request.SessionId, ct);
            if (winner?.StartQrId == start.Id && winner.DestinationNodeId == h.DestinationNodeId && winner.DestinationFloorKey == h.DestinationFloorKey) return Ok(Dto(winner));
            return Conflict(new { code="history_session_conflict" });
        }
        return CreatedAtAction(nameof(Detail), new {id=h.Id}, Dto(h));
    }
    [HttpPut("{id:guid}/destination"), RequestSizeLimit(1024)]
    public async Task<IActionResult> Destination(Guid id, HistoryDestinationRequest request, CancellationToken ct)
    {
        var h=await Own(id,ct); if(h is null)return NotFound();
        if(h.Status!="Scanned") return Conflict(new {code="history_already_started"});
        await SelectDestination(h,request.DestinationFloorKey,request.DestinationNodeId,ct);
        return await Save(h,ct);
    }
    [HttpPut("{id:guid}/start"), RequestSizeLimit(128)]
    public async Task<IActionResult> BeginNavigation(Guid id, CancellationToken ct)
    {
        var h=await Own(id,ct); if(h is null)return NotFound();
        if(h.Status=="InProgress")return Ok(Dto(h));
        if(h.Status!="Scanned" || h.DestinationNodeId is null)return Conflict(new {code="history_destination_required"});
        h.Status="InProgress"; h.NavigationStartedAtUtc=DateTime.UtcNow;
        return await Save(h,ct);
    }
    [HttpPut("{id:guid}"), RequestSizeLimit(1024)]
    public async Task<IActionResult> End(Guid id, EndHistoryRequest request, CancellationToken ct)
    {
        var h=await Own(id,ct); if(h is null)return NotFound();
        if(h.Status is "Completed" or "Cancelled") return h.Status==request.Status ? Ok(Dto(h)) : Conflict(new {code="history_already_ended"});
        if(request.Status=="Completed" && h.Status!="InProgress")return Conflict(new {code="history_not_started"});
        h.Status=request.Status; h.EndedAtUtc=DateTime.UtcNow; return await Save(h,ct);
    }
    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id, CancellationToken ct)
    {
        var h=await Own(id,ct); if(h is null)return NotFound();
        db.Remove(h); await db.SaveChangesAsync(ct); return NoContent();
    }
    [HttpGet("{id:guid}/resume")]
    public async Task<IActionResult> Resume(Guid id, CancellationToken ct)
    {
        var h=await Own(id,ct); if(h is null)return NotFound();
        var qr=await db.MapNodeQrs.AsNoTracking().SingleOrDefaultAsync(q=>q.Id==h.StartQrId,ct); if(qr is null)return NotFound();
        var r=await maps.ResolveAsync(qr.Token,ct);
        if(r.MapId!=h.MapId || r.Version!=h.PublishedVersion)return Conflict();
        var map=await maps.PublicAsync(r.MapId,r.Version,ct);
        if(h.DestinationNodeId is Guid node && !map.Content.Floors.Any(f=>f.Id==h.DestinationFloorKey && f.Content.Nodes!.Any(n=>n.Id==node)))return NotFound();
        return Ok(new {payload="WMQR1:"+qr.Token,h.DestinationFloorKey,h.DestinationNodeId});
    }
}
