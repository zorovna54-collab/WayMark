using Microsoft.EntityFrameworkCore;
using WayMark.Api.Models;

namespace WayMark.Api.Data;

internal static class PublishedMapModel
{
    public static void Configure(ModelBuilder builder)
    {
        var project = builder.Entity<MapProject>();
        project.ToTable("MapProjects", t => t.HasCheckConstraint("CK_MapProjects_Version", "[Version] > 0"));
        project.HasKey(x => x.Id);
        project.Property(x => x.Id).ValueGeneratedNever();
        project.Property(x => x.Version).IsConcurrencyToken();
        project.Property(x => x.Name).HasMaxLength(200).IsRequired();
        project.Property(x => x.OwnerId).HasMaxLength(450).IsRequired();
        project.Property(x => x.ContentJson).IsRequired();
        project.HasIndex(x => new { x.OwnerId, x.LocalProjectId }).IsUnique();
        project.HasOne<Site>().WithMany().HasForeignKey(x => x.SiteId).OnDelete(DeleteBehavior.Restrict);
        project.HasOne<Building>().WithMany().HasForeignKey(x => x.BuildingId).OnDelete(DeleteBehavior.Restrict);
        var publication = builder.Entity<MapPublication>();
        publication.ToTable("MapPublications", t => t.HasCheckConstraint("CK_MapPublications_Version", "[Version] > 0"));
        publication.HasKey(x => new { x.MapId, x.Version });
        publication.Property(x => x.Name).HasMaxLength(200).IsRequired();
        publication.Property(x => x.PublishedBy).HasMaxLength(450).IsRequired();
        publication.Property(x => x.ContentJson).IsRequired();
        publication.HasOne<MapProject>().WithMany().HasForeignKey(x => x.MapId).OnDelete(DeleteBehavior.Restrict);
        var image = builder.Entity<MapPublicationImage>();
        image.ToTable("MapPublicationImages");
        image.HasKey(x => new { x.MapId, x.Version, x.AssetId });
        image.HasOne<MapPublication>().WithMany().HasForeignKey(x => new { x.MapId, x.Version }).OnDelete(DeleteBehavior.Restrict);
        image.HasOne<FloorMapImageAsset>().WithMany().HasForeignKey(x => x.AssetId).OnDelete(DeleteBehavior.Restrict);
        var qr = builder.Entity<MapNodeQr>();
        qr.ToTable("MapNodeQrs", t => t.HasCheckConstraint("CK_MapNodeQrs_Version", "[DraftVersion] > 0 AND ([PublishedVersion] IS NULL OR [PublishedVersion] = [DraftVersion])"));
        qr.HasKey(x => x.Id);
        qr.Property(x => x.Id).ValueGeneratedNever();
        qr.Property(x => x.Token).HasMaxLength(64).IsRequired();
        qr.Property(x => x.CreatedBy).HasMaxLength(450).IsRequired();
        qr.Property(x => x.IsActive).IsConcurrencyToken();
        qr.HasIndex(x => x.Token).IsUnique();
        qr.HasIndex(x => new { x.MapId, x.DraftVersion, x.FloorKey, x.NodeId }).IsUnique().HasFilter("[IsActive] = 1");
        qr.HasOne<MapProject>().WithMany().HasForeignKey(x => x.MapId).OnDelete(DeleteBehavior.Restrict);
        qr.HasOne<MapPublication>().WithMany().HasForeignKey(x => new { x.MapId, x.PublishedVersion }).OnDelete(DeleteBehavior.Restrict);
    }
}
