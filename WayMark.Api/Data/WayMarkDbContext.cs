using Microsoft.EntityFrameworkCore;
using WayMarkEntity = global::WayMark.Api.Models.WayMark;
using WayMark.Api.Models;

namespace WayMark.Api.Data;

public class WayMarkDbContext(DbContextOptions<WayMarkDbContext> options)
    : DbContext(options)
{
    public DbSet<WayMarkEntity> WayMarks => Set<WayMarkEntity>();
    public DbSet<Site> Sites => Set<Site>();
    public DbSet<Building> Buildings => Set<Building>();
    public DbSet<Floor> Floors => Set<Floor>();
    public DbSet<NavigationNode> NavigationNodes => Set<NavigationNode>();
    public DbSet<NavigationEdge> NavigationEdges => Set<NavigationEdge>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        var wayMark = modelBuilder.Entity<WayMarkEntity>();

        wayMark.ToTable("WayMarks");
        wayMark.HasKey(item => item.Id);

        wayMark.Property(item => item.Id)
            .UseIdentityColumn(1, 1);

        wayMark.Property(item => item.Name)
            .HasColumnType("nvarchar(200)")
            .HasMaxLength(200)
            .IsRequired();

        wayMark.Property(item => item.Location)
            .HasColumnType("nvarchar(300)")
            .HasMaxLength(300)
            .IsRequired();

        wayMark.Property(item => item.WayMarkCode)
            .HasColumnType("nvarchar(100)")
            .HasMaxLength(100)
            .IsRequired();

        wayMark.HasIndex(item => item.WayMarkCode)
            .IsUnique();

        wayMark.Property(item => item.NavigationNodeId);

        wayMark.HasIndex(item => item.NavigationNodeId)
            .IsUnique()
            .HasFilter("[NavigationNodeId] IS NOT NULL");

        wayMark.HasOne<NavigationNode>()
            .WithOne()
            .HasForeignKey<WayMarkEntity>(item => item.NavigationNodeId)
            .OnDelete(DeleteBehavior.Restrict);

        var site = modelBuilder.Entity<Site>();
        site.ToTable("Sites");
        site.HasKey(item => item.Id);
        site.Property(item => item.Id).UseIdentityColumn(1, 1);
        site.Property(item => item.Name).HasMaxLength(200).IsRequired();
        site.Property(item => item.Code).HasMaxLength(50).IsRequired();
        site.Property(item => item.Address).HasMaxLength(500);
        site.HasIndex(item => item.Code).IsUnique();
        site.HasMany<Building>()
            .WithOne()
            .HasForeignKey(item => item.SiteId)
            .OnDelete(DeleteBehavior.Restrict);

        var building = modelBuilder.Entity<Building>();
        building.ToTable("Buildings");
        building.HasKey(item => item.Id);
        building.Property(item => item.Id).UseIdentityColumn(1, 1);
        building.Property(item => item.Name).HasMaxLength(200).IsRequired();
        building.Property(item => item.BuildingCode).HasMaxLength(50).IsRequired();
        building.HasIndex(item => new { item.SiteId, item.BuildingCode })
            .IsUnique();
        building.HasMany<Floor>()
            .WithOne()
            .HasForeignKey(item => item.BuildingId)
            .OnDelete(DeleteBehavior.Restrict);

        var floor = modelBuilder.Entity<Floor>();
        floor.ToTable("Floors");
        floor.HasKey(item => item.Id);
        floor.Property(item => item.Id).UseIdentityColumn(1, 1);
        floor.Property(item => item.Name).HasMaxLength(200).IsRequired();
        floor.Property(item => item.FloorCode).HasMaxLength(30).IsRequired();
        floor.Property(item => item.FloorPlanImageUrl).HasMaxLength(1000);
        floor.HasIndex(item => new { item.BuildingId, item.FloorCode })
            .IsUnique();
        floor.HasMany<NavigationNode>()
            .WithOne()
            .HasForeignKey(item => item.FloorId)
            .OnDelete(DeleteBehavior.Restrict);

        var node = modelBuilder.Entity<NavigationNode>();
        node.ToTable("NavigationNodes", table =>
        {
            table.HasCheckConstraint(
                "CK_NavigationNodes_X_Range",
                "[X] >= 0 AND [X] <= 1");
            table.HasCheckConstraint(
                "CK_NavigationNodes_Y_Range",
                "[Y] >= 0 AND [Y] <= 1");
        });
        node.HasKey(item => item.Id);
        node.Property(item => item.Id).UseIdentityColumn(1, 1);
        node.Property(item => item.NodeCode).HasMaxLength(100).IsRequired();
        node.Property(item => item.Name).HasMaxLength(200).IsRequired();
        node.Property(item => item.X).HasColumnType("decimal(9,6)");
        node.Property(item => item.Y).HasColumnType("decimal(9,6)");
        node.Property(item => item.NodeType).HasConversion<int>();
        node.HasIndex(item => item.NodeCode).IsUnique();
        node.HasIndex(item => item.FloorId);
        node.HasMany<NavigationEdge>()
            .WithOne()
            .HasForeignKey(item => item.FromNodeId)
            .OnDelete(DeleteBehavior.Restrict);
        node.HasMany<NavigationEdge>()
            .WithOne()
            .HasForeignKey(item => item.ToNodeId)
            .OnDelete(DeleteBehavior.Restrict);

        var edge = modelBuilder.Entity<NavigationEdge>();
        edge.ToTable("NavigationEdges", table =>
        {
            table.HasCheckConstraint(
                "CK_NavigationEdges_DistanceMeters_Positive",
                "[DistanceMeters] > 0");
            table.HasCheckConstraint(
                "CK_NavigationEdges_DifferentNodes",
                "[FromNodeId] <> [ToNodeId]");
        });
        edge.HasKey(item => item.Id);
        edge.Property(item => item.Id).UseIdentityColumn(1, 1);
        edge.Property(item => item.EdgeType).HasConversion<int>();
        edge.Property(item => item.DistanceMeters).HasPrecision(12, 3);
        edge.Property(item => item.IsActive).HasDefaultValue(true);
        edge.Property(item => item.IsAccessible).HasDefaultValue(false);
        edge.HasIndex(item => item.FromNodeId);
        edge.HasIndex(item => item.ToNodeId);
    }
}
