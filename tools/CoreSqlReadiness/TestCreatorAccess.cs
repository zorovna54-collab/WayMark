using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using WayMark.Api.Data;
using WayMark.Api.Models;
using WayMark.Api.Security;

namespace WayMark.CoreSqlReadiness;

// Operator tool only. No HTTP endpoint or startup registration. Never creates,
// renames, resets passwords or adopts accounts. Approval precedes even the reads.
public static class TestCreatorAccess
{
    public static async Task GrantAsync(ReadinessPlan plan, bool execute, UserManager<IdentityUser> users,
        RoleManager<IdentityRole> roles, AuthDbContext auth, WayMarkDbContext map)
    {
        plan.RequireApproval(execute);
        var floors = await (from f in map.Floors join b in map.Buildings on f.BuildingId equals b.Id
            where plan.FloorIds.Contains(f.Id) && b.SiteId == plan.SiteId select new { f.Id, f.BuildingId }).ToListAsync();
        if (floors.Count != 2 || floors.Select(x => x.BuildingId).Distinct().Count() != 1)
            throw new InvalidOperationException("Approved floors must exist in one Building/Site");
        var accounts = new List<IdentityUser>();
        foreach (var selected in new[] { plan.CreatorA, plan.CreatorB }) {
            var user = await users.FindByIdAsync(selected.Id);
            if (user is null || user.UserName != selected.UserName || user.Email != selected.UserName + "@example.invalid")
                throw new InvalidOperationException("Selected account does not exactly match the approved test identity");
            if ((await users.GetRolesAsync(user)).Any(role => role != WayMarkSecurity.CreatorRole
                && !(user.Id == plan.CreatorA.Id && role == WayMarkSecurity.SitePublisherRole(plan.SiteId))))
                throw new InvalidOperationException("Test accounts must not have unrelated or administrative roles; no role is removed automatically");
            var membership = await map.SiteMapMemberships.SingleOrDefaultAsync(x => x.SiteId == plan.SiteId && x.UserId == user.Id);
            if (membership is not null && (!membership.IsActive || !membership.CanEditDrafts))
                throw new InvalidOperationException("Existing revoked/restricted membership must not be reactivated by setup");
            accounts.Add(user);
        }
        // Both contexts must share one actual connection/transaction. The CLI
        // pins this, and the SQLite test host supplies one shared connection.
        if (!ReferenceEquals(auth.Database.GetDbConnection(), map.Database.GetDbConnection()))
            throw new InvalidOperationException("Shared database transaction connection required");
        await using var transaction = await auth.Database.BeginTransactionAsync();
        await map.Database.UseTransactionAsync(transaction.GetDbTransaction());
        try {
            var grants = new[] { WayMarkSecurity.CreatorRole, WayMarkSecurity.SitePublisherRole(plan.SiteId) };
            foreach (var role in grants)
                if (!await roles.RoleExistsAsync(role)) Check(await roles.CreateAsync(new(role)));
            foreach (var user in accounts) {
                foreach (var role in user.Id == plan.CreatorA.Id ? grants : [WayMarkSecurity.CreatorRole])
                    if (!await users.IsInRoleAsync(user, role)) Check(await users.AddToRoleAsync(user, role));
                if (!await map.SiteMapMemberships.AnyAsync(x => x.SiteId == plan.SiteId && x.UserId == user.Id))
                    map.SiteMapMemberships.Add(new SiteMapMembership { SiteId = plan.SiteId, UserId = user.Id, IsActive = true, CanEditDrafts = true });
            }
            await map.SaveChangesAsync();
            await transaction.CommitAsync();
        } catch {
            await transaction.RollbackAsync(); auth.ChangeTracker.Clear(); map.ChangeTracker.Clear(); throw;
        } finally { await map.Database.UseTransactionAsync(null); }
    }
    private static void Check(IdentityResult result)
    {
        if (!result.Succeeded) throw new InvalidOperationException("Identity setup refused; no credentials logged");
    }
}
