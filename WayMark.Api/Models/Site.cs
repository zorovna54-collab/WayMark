using System.ComponentModel.DataAnnotations;

namespace WayMark.Api.Models;

public class Site
{
    public int Id { get; set; }

    [Required]
    [StringLength(200)]
    public string Name { get; set; } = string.Empty;

    [Required]
    [StringLength(50)]
    public string Code { get; set; } = string.Empty;

    [StringLength(500)]
    public string? Address { get; set; }
}
