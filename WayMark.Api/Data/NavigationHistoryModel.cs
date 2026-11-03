using Microsoft.EntityFrameworkCore;
using WayMark.Api.Models;

namespace WayMark.Api.Data;

public static class NavigationHistoryModel
{
    public static void Configure(ModelBuilder model)
    {
        var h = model.Entity<NavigationHistory>();
        h.ToTable("NavigationHistory", t => t.HasCheckConstraint("CK_NavigationHistory_Status", "[Status] IN ('Scanned', 'InProgress', 'Completed', 'Cancelled')"));
        h.HasKey(x => x.Id);
        h.Property(x => x.UserId).HasMaxLength(450).IsRequired();
        h.Property(x => x.MapName).HasMaxLength(200).IsRequired();
        h.Property(x => x.StartName).HasMaxLength(200).IsRequired();
        h.Property(x => x.DestinationName).HasMaxLength(200).IsRequired();
        h.Property(x => x.Status).HasMaxLength(20).IsRequired().IsConcurrencyToken();
        h.Property(x => x.DistanceMeters).HasPrecision(18, 3);
        h.HasIndex(x => new { x.UserId, x.StartedAtUtc });
        // Retain the historical identifiers when a public map/QR becomes unavailable;
        // resume always validates live public access instead of trusting old routes.
    }
}
