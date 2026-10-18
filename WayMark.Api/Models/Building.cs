using System.ComponentModel.DataAnnotations;

namespace WayMark.Api.Models;

public class Building
{
    public int Id { get; set; }

    public int SiteId { get; set; }

    [Required]
    [StringLength(200)]
    public string Name { get; set; } = string.Empty;

    [Required]
    [StringLength(50)]
    public string BuildingCode { get; set; } = string.Empty;
}
