using Microsoft.EntityFrameworkCore;
using WayMark.Api.Models;

namespace WayMark.Api.Data;

internal static class MapDraftModel
{
    public static void Configure(ModelBuilder builder)
    {
        var membership = builder.Entity<SiteMapMembership>();
        membership.ToTable("SiteMapMemberships");
        membership.HasKey(x => x.Id);
        membership.Property(x => x.Id).UseIdentityColumn(1, 1);
        membership.Property(x => x.UserId).HasMaxLength(450).IsRequired();
        // 4 + 450*2 = 904 bytes exceeds SQL Server's 900-byte primary-key limit.
        // Use a narrow surrogate PK and a separate unique nonclustered scope index.
        membership.HasIndex(x => new { x.SiteId, x.UserId }).IsUnique();
        membership.HasOne<Site>().WithMany().HasForeignKey(x => x.SiteId).OnDelete(DeleteBehavior.Restrict);
        // Identity is managed by AuthDbContext. Do not duplicate its entities here.
        membership.HasIndex(x => x.UserId);

        var draft = builder.Entity<FloorMapDraft>();
        draft.ToTable("FloorMapDrafts", table =>
        {
            table.HasCheckConstraint("CK_FloorMapDrafts_Version", "[Version] > 0");
            table.HasCheckConstraint("CK_FloorMapDrafts_Status", "[Status] = 'Draft'");
        });
        draft.HasKey(x => x.Id);
        draft.Property(x => x.Id).ValueGeneratedNever();
        draft.Property(x => x.Version).IsConcurrencyToken();
        draft.Property(x => x.Status).HasMaxLength(20).IsRequired();
        draft.Property(x => x.CreatedBy).HasMaxLength(450).IsRequired();
        draft.Property(x => x.UpdatedBy).HasMaxLength(450).IsRequired();
        draft.HasIndex(x => x.FloorId).IsUnique();
        draft.HasAlternateKey(x => x.FloorId);
        draft.HasOne<Floor>().WithMany().HasForeignKey(x => x.FloorId).OnDelete(DeleteBehavior.Restrict);

        var asset = builder.Entity<FloorMapImageAsset>();
        asset.ToTable("FloorMapImageAssets", table =>
        {
            table.HasCheckConstraint("CK_FloorMapImageAssets_Width", "[Width] > 0 AND [Width] <= 8192");
            table.HasCheckConstraint("CK_FloorMapImageAssets_Height", "[Height] > 0 AND [Height] <= 8192");
            table.HasCheckConstraint("CK_FloorMapImageAssets_Pixels", "CAST([Width] AS bigint) * [Height] <= 32000000");
            table.HasCheckConstraint("CK_FloorMapImageAssets_Bytes", "[ByteLength] > 0 AND [ByteLength] <= 10485760");
            table.HasCheckConstraint("CK_FloorMapImageAssets_Mime", "[MimeType] IN ('image/png', 'image/jpeg')");
        });
        asset.HasKey(x => x.Id);
        asset.Property(x => x.Id).ValueGeneratedNever();
        asset.Property(x => x.StorageKey).HasMaxLength(64).IsRequired();
        asset.HasIndex(x => x.StorageKey).IsUnique();
        asset.Property(x => x.MimeType).HasMaxLength(20).IsRequired();
        asset.Property(x => x.Sha256).HasMaxLength(64).IsRequired();
        asset.Property(x => x.CreatedBy).HasMaxLength(450).IsRequired();
        asset.HasOne<Floor>().WithMany().HasForeignKey(x => x.FloorId).OnDelete(DeleteBehavior.Restrict);
        asset.HasOne<FloorMapDraft>().WithMany().HasForeignKey(x => x.FloorId)
            .HasPrincipalKey(x => x.FloorId).OnDelete(DeleteBehavior.Restrict);

        var revision = builder.Entity<FloorMapDraftRevision>();
        revision.ToTable("FloorMapDraftRevisions", table =>
            table.HasCheckConstraint("CK_FloorMapDraftRevisions_Version", "[Version] > 0"));
        revision.HasKey(x => new { x.DraftId, x.Version });
        revision.Property(x => x.ContentJson).IsRequired();
        revision.Property(x => x.CreatedBy).HasMaxLength(450).IsRequired();
        revision.HasOne(x => x.Draft).WithMany().HasForeignKey(x => x.DraftId).OnDelete(DeleteBehavior.Restrict);
        revision.HasOne<FloorMapImageAsset>().WithMany().HasForeignKey(x => x.ImageAssetId).OnDelete(DeleteBehavior.Restrict);
    }
}
