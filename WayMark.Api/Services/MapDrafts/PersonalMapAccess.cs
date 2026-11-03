using System.Globalization;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using WayMark.Api.Data;
using WayMark.Api.Security;

namespace WayMark.Api.Services.MapDrafts;

// Ownership is a SERVER-STORED entitlement in the existing Identity claim store,
// never a JWT site claim or a role supplied by the client. No schema change.
public sealed class PersonalMapAccess(IServiceProvider services)
{
    public const string Claim = "waymark:personal_site";
    public const string Prefix = "WM-PERSONAL-";
    public async Task<string[]> RolesAsync(ClaimsPrincipal user, CancellationToken ct = default)
    {
        var auth = services.GetService<AuthDbContext>();
        // Standalone graph test hosts have signed fixture roles but no Identity
        // store. The actual API always registers AuthDbContext (same SQL DB).
        if (auth is null) return user.FindAll(ClaimTypes.Role).Select(c => c.Value).ToArray();
        var id = user.FindFirstValue(ClaimTypes.NameIdentifier);
        return await (from link in auth.UserRoles.AsNoTracking() join role in auth.Roles.AsNoTracking()
            on link.RoleId equals role.Id where link.UserId == id select role.Name!).ToArrayAsync(ct);
    }
    public async Task<int[]> SitesAsync(ClaimsPrincipal user, CancellationToken ct = default)
    {
        var id = user.FindFirstValue(ClaimTypes.NameIdentifier);
        var auth = services.GetService<AuthDbContext>();
        if (id is null || auth is null) return [];
        var values = await auth.UserClaims.AsNoTracking().Where(c => c.UserId == id && c.ClaimType == Claim)
            .Select(c => c.ClaimValue).ToListAsync(ct);
        var claimed = values.Select(v => int.TryParse(v, NumberStyles.None, CultureInfo.InvariantCulture, out var n) ? n : 0)
            .Where(n => n > 0).Distinct().ToArray();
        var maps = services.GetService<WayMarkDbContext>();
        if (maps is null || claimed.Length == 0) return [];
        return await (from membership in maps.SiteMapMemberships.AsNoTracking()
            join site in maps.Sites.AsNoTracking() on membership.SiteId equals site.Id
            where membership.UserId == id && membership.IsActive && membership.CanEditDrafts
                && claimed.Contains(site.Id) && site.Code.StartsWith(Prefix)
            select site.Id).Distinct().ToArrayAsync(ct);
    }
    public async Task<bool> OwnsAsync(ClaimsPrincipal user, int site, CancellationToken ct = default)
        => (await SitesAsync(user, ct)).Contains(site);
}

public sealed class MapAuthorRequirement : IAuthorizationRequirement;
public sealed class CurrentAdminRequirement : IAuthorizationRequirement;
public sealed class CurrentAdminHandler(IServiceProvider services) : AuthorizationHandler<CurrentAdminRequirement>
{
    protected override async Task HandleRequirementAsync(AuthorizationHandlerContext context, CurrentAdminRequirement requirement)
    {
        if (context.User.Identity?.IsAuthenticated == true &&
            (await new PersonalMapAccess(services).RolesAsync(context.User)).Contains(WayMarkSecurity.AdminRole))
            context.Succeed(requirement);
    }
}
public sealed class MapAuthorHandler(IServiceProvider services) : AuthorizationHandler<MapAuthorRequirement>
{
    protected override async Task HandleRequirementAsync(AuthorizationHandlerContext context, MapAuthorRequirement requirement)
    {
        if (context.User.Identity?.IsAuthenticated != true) return;
        var access = new PersonalMapAccess(services);
        if ((await access.RolesAsync(context.User)).Any(r => r is "Admin" or "Creator" or "SiteManager") ||
            (await access.SitesAsync(context.User)).Length > 0)
            context.Succeed(requirement);
    }
}
