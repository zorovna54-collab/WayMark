using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using WayMark.Api.Data;
using WayMark.Api.Models;
using Xunit;

namespace WayMark.Api.Tests;

public sealed class MapDraftModelTests
{
    [Fact]
    public void PublishedProjectMigrationIsAdditiveAndProtectsQrRevocation()
    {
        using var db = new WayMarkDbContext(new DbContextOptionsBuilder<WayMarkDbContext>().UseSqlServer().Options);
        Assert.False(db.Database.HasPendingModelChanges());
        var sql = db.GetService<IMigrator>().GenerateScript("20261020101304_BindMapImagesToDrafts", "20261023063955_AddPublishedMapProjects");
        foreach (var name in new[] { "MapProjects", "MapPublications", "MapNodeQrs", "MapPublicationImages" })
            Assert.Contains($"CREATE TABLE [{name}]", sql);
        Assert.DoesNotContain("DROP ", sql, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("TRUNCATE ", sql, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("CREATE TABLE [AspNet", sql);
        Assert.DoesNotContain("ALTER TABLE [WayMarks]", sql);
        Assert.DoesNotContain("INSERT INTO [Navigation", sql);
        Assert.True(db.Model.FindEntityType(typeof(MapNodeQr))!.FindProperty("IsActive")!.IsConcurrencyToken);
        Assert.Contains("[IsActive] = 1", sql);
    }

    [Fact]
    public void SqlServerModelMatchesSnapshotAndMigrationIsAdditiveOnly()
    {
        // Provider metadata/SQL generation only. No connection string or DB connection exists.
        using var db = new WayMarkDbContext(new DbContextOptionsBuilder<WayMarkDbContext>().UseSqlServer().Options);
        Assert.False(db.Database.HasPendingModelChanges());
        var sql = db.GetService<IMigrator>().GenerateScript("20261018053754_AddNavigationSchema", "20261020094848_AddMapDraftFoundation");
        foreach (var table in new[] { "FloorMapDrafts", "FloorMapDraftRevisions", "FloorMapImageAssets", "SiteMapMemberships" })
            Assert.Contains($"CREATE TABLE [{table}]", sql);
        Assert.DoesNotContain("DROP ", sql, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("TRUNCATE ", sql, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("ALTER TABLE [WayMarks]", sql);
        Assert.DoesNotContain("CREATE TABLE [AspNet", sql);
        Assert.DoesNotContain("INSERT INTO [WayMarks]", sql);
        Assert.Contains("INSERT INTO [__EFMigrationsHistory]", sql);
        Assert.Contains("20261020094848_AddMapDraftFoundation", sql);
        var binding = db.GetService<IMigrator>().GenerateScript("20261020094848_AddMapDraftFoundation", "20261020101304_BindMapImagesToDrafts");
        Assert.Contains("FK_FloorMapImageAssets_FloorMapDrafts_FloorId", binding);
        Assert.Contains("REFERENCES [FloorMapDrafts] ([FloorId])", binding);
        Assert.DoesNotContain("DROP ", binding, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("ALTER TABLE [WayMarks]", binding);
    }

    [Fact]
    public void ExistingGraphIsUnchangedAndDraftOwnershipDoesNotDuplicateIdentity()
    {
        using var db = new WayMarkDbContext(new DbContextOptionsBuilder<WayMarkDbContext>().UseSqlServer().Options);
        var model = db.Model;
        Assert.DoesNotContain(model.GetEntityTypes(), type => type.Name.Contains("Identity", StringComparison.Ordinal));
        var membership = model.FindEntityType(typeof(SiteMapMembership))!;
        Assert.Equal(new[] { "Id" }, membership.FindPrimaryKey()!.Properties.Select(p => p.Name));
        Assert.Contains(membership.GetIndexes(), index => index.IsUnique && index.Properties.Select(p => p.Name).SequenceEqual(new[] { "SiteId", "UserId" }));
        Assert.True(model.FindEntityType(typeof(FloorMapDraft))!.FindProperty("Version")!.IsConcurrencyToken);
        Assert.All(model.GetEntityTypes().Where(type => type.ClrType == typeof(FloorMapDraft)
            || type.ClrType == typeof(FloorMapDraftRevision) || type.ClrType == typeof(FloorMapImageAsset)
            || type.ClrType == typeof(SiteMapMembership)).SelectMany(type => type.GetForeignKeys()),
            fk => Assert.Equal(DeleteBehavior.Restrict, fk.DeleteBehavior));
        Assert.Contains(model.FindEntityType(typeof(NavigationNode))!.GetIndexes(), index => index.IsUnique
            && index.Properties.Select(p => p.Name).SequenceEqual(new[] { "NodeCode" }));
        var qr = model.FindEntityType(typeof(global::WayMark.Api.Models.WayMark))!;
        Assert.Contains(qr.GetIndexes(), index => index.IsUnique && index.GetFilter() == "[NavigationNodeId] IS NOT NULL");
    }
}
