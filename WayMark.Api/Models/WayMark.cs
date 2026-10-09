using System.ComponentModel.DataAnnotations;

namespace WayMark.Api.Models;

public class WayMark
{
    public int Id { get; set; }

    [Required]
    [StringLength(200)]
    public string Name { get; set; } = string.Empty;

    [Required]
    [StringLength(300)]
    public string Location { get; set; } = string.Empty;

    [Required]
    [StringLength(100)]
    public string WayMarkCode { get; set; } = string.Empty;
}