using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using WayMark.Api.Data;

namespace WayMark.CoreSqlReadiness;

// Explicit operator command, never registered in API startup. Passwords are
// supplied privately in memory; no default passwords, logging or account adoption.
public static class TestCreatorBootstrap
{
    public static async Task<ReadinessPlan> CreateAsync(ReadinessPlan plan, bool execute,
        UserManager<IdentityUser> users, AuthDbContext auth, WayMarkDbContext map,
        string passwordA, string passwordB)
    {
        plan.RequireApproval(execute, bootstrap: true);
        if (passwordA.Length < 8 || passwordB.Length < 8
            || !ReferenceEquals(auth.Database.GetDbConnection(), map.Database.GetDbConnection()))
            throw new InvalidOperationException("Private test credentials/shared transaction connection required");
        var floors = await (from f in map.Floors.AsNoTracking() join b in map.Buildings.AsNoTracking() on f.BuildingId equals b.Id
            where plan.FloorIds.Contains(f.Id) && b.SiteId == plan.SiteId select f.BuildingId).ToListAsync();
        if (floors.Count != 2 || floors.Distinct().Count() != 1
            || await map.FloorMapDrafts.AnyAsync(d => plan.FloorIds.Contains(d.FloorId)))
            throw new InvalidOperationException("Approved unused floors in one Building/Site are required");
        foreach (var selected in new[] { plan.CreatorA, plan.CreatorB })
            if (await users.FindByNameAsync(selected.UserName) is not null
                || await users.FindByEmailAsync(selected.UserName + "@example.invalid") is not null)
                throw new InvalidOperationException("Reserved test identity exists; no overwrite, reset or automatic resume");
        await using var transaction = await auth.Database.BeginTransactionAsync();
        try {
            var a = new IdentityUser { UserName = plan.CreatorA.UserName, Email = plan.CreatorA.UserName + "@example.invalid" };
            var b = new IdentityUser { UserName = plan.CreatorB.UserName, Email = plan.CreatorB.UserName + "@example.invalid" };
            if (!(await users.CreateAsync(a, passwordA)).Succeeded || !(await users.CreateAsync(b, passwordB)).Succeeded)
                throw new InvalidOperationException("Test Identity creation refused; credential details withheld");
            await transaction.CommitAsync();
            return plan with { CreatorA = plan.CreatorA with { Id = a.Id }, CreatorB = plan.CreatorB with { Id = b.Id } };
        } catch {
            await transaction.RollbackAsync(); auth.ChangeTracker.Clear(); throw;
        }
    }
}
