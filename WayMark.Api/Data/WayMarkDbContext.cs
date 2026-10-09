using Microsoft.EntityFrameworkCore;
using WayMarkEntity = global::WayMark.Api.Models.WayMark;

namespace WayMark.Api.Data;

public class WayMarkDbContext(DbContextOptions<WayMarkDbContext> options)
    : DbContext(options)
{
    public DbSet<WayMarkEntity> WayMarks => Set<WayMarkEntity>();

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
    }
}
