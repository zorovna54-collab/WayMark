using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using WayMark.Api.Data;
using WayMark.Api.Security;

namespace WayMark.Api.Services.MapDrafts;

public sealed class DraftOperationException(int status, string code, string message) : Exception(message)
{
    public int Status { get; } = status;
    public string Code { get; } = code;
}

public sealed record DraftFloorScope(int FloorId, int BuildingId, int SiteId, string UserId);

public interface IDraftSiteAccess
{
    Task<DraftFloorScope> RequireAsync(ClaimsPrincipal user, int floorId, CancellationToken cancellationToken);
}

public sealed class DraftSiteAccess(WayMarkDbContext db, PersonalMapAccess personal) : IDraftSiteAccess
{
    public async Task<DraftFloorScope> RequireAsync(ClaimsPrincipal user, int floorId, CancellationToken cancellationToken)
    {
        if (user.Identity?.IsAuthenticated != true) throw new DraftOperationException(401, "authentication_required", "Authentication is required");
        var userId = user.FindFirstValue(ClaimTypes.NameIdentifier);
        var roles = await personal.RolesAsync(user, cancellationToken);
        if (string.IsNullOrWhiteSpace(userId)) throw Denied();
        // Derive scope from the persisted hierarchy. No header, body SiteId or JWT site claim grants access.
        var scope = await (from floor in db.Floors.AsNoTracking()
            join building in db.Buildings.AsNoTracking() on floor.BuildingId equals building.Id
            join site in db.Sites.AsNoTracking() on building.SiteId equals site.Id
            where floor.Id == floorId
            select new { floor.Id, BuildingId = building.Id, SiteId = site.Id, site.Code }).SingleOrDefaultAsync(cancellationToken);
        if (scope is not null && (scope.Code.StartsWith(PersonalMapAccess.Prefix, StringComparison.Ordinal)
            ? !await personal.OwnsAsync(user, scope.SiteId, cancellationToken)
            : !roles.Any(r => r is "Admin" or "Creator" or "SiteManager"))) throw Denied();
        // Missing floor and out-of-scope floor deliberately look alike to prevent ID enumeration.
        if (scope is null || !await db.SiteMapMemberships.AsNoTracking().AnyAsync(x => x.SiteId == scope.SiteId
            && x.UserId == userId && x.IsActive && x.CanEditDrafts, cancellationToken)) throw Denied();
        // Floor drafts are singletons. Creator access must not expose another
        // Creator's draft, revision or image merely because they share a Site.
        // Existing Admin floor collaboration remains; SiteManager is Site-scoped.
        if (!roles.Contains(WayMarkSecurity.AdminRole) && !roles.Contains(WayMarkSecurity.SiteManagerRole)
            && await db.FloorMapDrafts.AsNoTracking().AnyAsync(x => x.FloorId == floorId && x.CreatedBy != userId, cancellationToken))
            throw Denied();
        return new(scope.Id, scope.BuildingId, scope.SiteId, userId);
    }
    private static DraftOperationException Denied() => new(403, "draft_scope_denied", "Draft access is not granted for this Site");
}
