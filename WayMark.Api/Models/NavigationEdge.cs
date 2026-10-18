using System.ComponentModel.DataAnnotations;

namespace WayMark.Api.Models;

public class NavigationEdge
{
    public int Id { get; set; }

    public int FromNodeId { get; set; }

    public int ToNodeId { get; set; }

    public NavigationEdgeType EdgeType { get; set; }

    [Range(typeof(decimal), "0.001", "999999999.999")]
    public decimal DistanceMeters { get; set; }

    public bool IsActive { get; set; } = true;

    public bool IsAccessible { get; set; }
}
