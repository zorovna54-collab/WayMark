using System.ComponentModel.DataAnnotations;

namespace WayMark.Api.Models;

public class Floor
{
    public int Id { get; set; }

    public int BuildingId { get; set; }

    [Required]
    [StringLength(200)]
    public string Name { get; set; } = string.Empty;

    [Required]
    [StringLength(30)]
    public string FloorCode { get; set; } = string.Empty;

    public int SortOrder { get; set; }

    [StringLength(1000)]
    public string? FloorPlanImageUrl { get; set; }
}
