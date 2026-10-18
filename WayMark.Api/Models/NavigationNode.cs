using System.ComponentModel.DataAnnotations;

namespace WayMark.Api.Models;

public class NavigationNode
{
    public int Id { get; set; }

    public int FloorId { get; set; }

    [Required]
    [StringLength(100)]
    public string NodeCode { get; set; } = string.Empty;

    [Required]
    [StringLength(200)]
    public string Name { get; set; } = string.Empty;

    [Range(typeof(decimal), "0", "1")]
    public decimal X { get; set; }

    [Range(typeof(decimal), "0", "1")]
    public decimal Y { get; set; }

    public NavigationNodeType NodeType { get; set; }
}
