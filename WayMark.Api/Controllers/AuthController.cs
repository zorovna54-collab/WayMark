using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.IdentityModel.Tokens;
using WayMark.Api.Models;

namespace WayMark.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AuthController : ControllerBase
{
    private readonly UserManager<IdentityUser> _userManager;
    private readonly IConfiguration _configuration;

    public AuthController(
        UserManager<IdentityUser> userManager,
        IConfiguration configuration)
    {
        _userManager = userManager;
        _configuration = configuration;
    }

    [HttpPost("register")]
    [AllowAnonymous]
    public async Task<IActionResult> Register(
        [FromBody] RegisterRequest request)
    {
        var username = request.Username.Trim();

        if (string.IsNullOrWhiteSpace(username))
        {
            return BadRequest(new
            {
                message = "Username không được để trống."
            });
        }

        var existingUser =
            await _userManager.FindByNameAsync(username);

        if (existingUser != null)
        {
            return Conflict(new
            {
                message = "Username đã tồn tại."
            });
        }

        var user = new IdentityUser
        {
            UserName = username
        };

        var result = await _userManager.CreateAsync(
            user,
            request.Password);

        if (!result.Succeeded)
        {
            return BadRequest(new
            {
                errors = result.Errors.Select(
                    error => error.Description)
            });
        }

        return Ok(new
        {
            message = "Đăng ký thành công."
        });
    }

    [HttpPost("login")]
    [AllowAnonymous]
    public async Task<IActionResult> Login(
        [FromBody] LoginRequest request)
    {
        var username = request.Username.Trim();

        var user = await _userManager.FindByNameAsync(username);

        if (user == null ||
            !await _userManager.CheckPasswordAsync(
                user, request.Password))
        {
            return Unauthorized(new
            {
                message = "Username hoặc password không đúng."
            });
        }

        var secret = _configuration["Jwt:SecretKey"]
            ?? throw new InvalidOperationException(
                "Missing Jwt:SecretKey.");

        var issuer = _configuration["Jwt:Issuer"]
            ?? throw new InvalidOperationException(
                "Missing Jwt:Issuer.");

        var audience = _configuration["Jwt:Audience"]
            ?? throw new InvalidOperationException(
                "Missing Jwt:Audience.");

        var expiryText = _configuration["Jwt:ExpiryMinutes"]
            ?? "30";

        if (!double.TryParse(
                expiryText,
                System.Globalization.NumberStyles.Number,
                System.Globalization.CultureInfo.InvariantCulture,
                out var expiryMinutes) ||
            expiryMinutes <= 0)
        {
            throw new InvalidOperationException(
                "Jwt:ExpiryMinutes must be a positive number.");
        }

        var key = new SymmetricSecurityKey(
            Convert.FromBase64String(secret));

        var credentials = new SigningCredentials(
            key,
            SecurityAlgorithms.HmacSha256);

        var expiresAt = DateTime.UtcNow
            .AddMinutes(expiryMinutes);

        var claims = new List<Claim>
        {
            new Claim(JwtRegisteredClaimNames.Sub, user.Id),
            new Claim(
                JwtRegisteredClaimNames.UniqueName,
                user.UserName ?? username),
            new Claim(ClaimTypes.NameIdentifier, user.Id),
            new Claim(
                ClaimTypes.Name,
                user.UserName ?? username)
        };

        // Membership comes only from the server's Identity store. Register/login
        // request bodies, usernames and Flutter UI state cannot grant a role.
        var roles = await _userManager.GetRolesAsync(user);
        claims.AddRange(roles.Select(role => new Claim(ClaimTypes.Role, role)));

        var jwt = new JwtSecurityToken(
            issuer: issuer,
            audience: audience,
            claims: claims,
            expires: expiresAt,
            signingCredentials: credentials);

        var token = new JwtSecurityTokenHandler()
            .WriteToken(jwt);

        return Ok(new
        {
            accessToken = token,
            tokenType = "Bearer",
            expiresAtUtc = expiresAt,
            username = user.UserName
        });
    }
}
