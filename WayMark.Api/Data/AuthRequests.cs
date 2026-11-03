using System.ComponentModel.DataAnnotations;

namespace WayMark.Api.Models;

public sealed class RegisterRequest
{
    [Required]
    [StringLength(50, MinimumLength = 3)]
    public string Username { get; set; } = string.Empty;

    [EmailAddress]
    public string? Email { get; set; }

    [Required]
    [MinLength(8)]
    public string Password { get; set; } = string.Empty;
}

public sealed class LoginRequest
{
    [Required]
    public string Username { get; set; } = string.Empty;

    [Required]
    public string Password { get; set; } = string.Empty;
}

public sealed class UpdateProfileRequest
{
    [Required]
    [StringLength(80, MinimumLength = 1)]
    public string DisplayName { get; set; } = string.Empty;
}

public sealed class ForgotPasswordRequest
{
    [Required]
    [StringLength(256)]
    public string UsernameOrEmail { get; set; } = string.Empty;
}

public sealed class ResetPasswordRequest
{
    [Required]
    [StringLength(256)]
    public string UsernameOrEmail { get; set; } = string.Empty;

    [Required]
    [StringLength(8192)]
    public string Token { get; set; } = string.Empty;

    [Required]
    [MinLength(8)]
    [MaxLength(128)]
    public string NewPassword { get; set; } = string.Empty;
}
