using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.IdentityModel.Tokens;
using WayMark.Api.Models;
using WayMark.Api.Services;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using WayMark.Api.Data;
using WayMark.Api.Services.MapDrafts;

namespace WayMark.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public partial class AuthController : ControllerBase
{
    private const string DisplayNameClaim = "waymark:display_name";
    private readonly UserManager<IdentityUser> _userManager;
    private readonly IConfiguration _configuration;
    private readonly ISmtpEmailService _emailService;

    public AuthController(
        UserManager<IdentityUser> userManager,
        IConfiguration configuration,
        ISmtpEmailService emailService)
    {
        _userManager = userManager;
        _configuration = configuration;
        _emailService = emailService;
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
            UserName = username,
            Email = string.IsNullOrWhiteSpace(request.Email)
                ? null
                : request.Email.Trim()
        };

        // Pair with email-confirmation range locks; never merge identities.
        using var emailTx = await EmailTransaction();
        if (user.Email is not null && await EmailTaken(_userManager.NormalizeEmail(user.Email)!, user.Id))
            return Conflict(new { message = "Không thể sử dụng email này." });
        var result = await _userManager.CreateAsync(user, request.Password);

        if (!result.Succeeded)
        {
            return BadRequest(new
            {
                errors = result.Errors.Select(
                    error => error.Description)
            });
        }

        if (emailTx is Microsoft.EntityFrameworkCore.Storage.IDbContextTransaction tx) await tx.CommitAsync();
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
            new Claim("waymark:security_stamp", await _userManager.GetSecurityStampAsync(user)),
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

    [Authorize]
    [HttpGet("me")]
    public async Task<IActionResult> Me()
    {
        var user = await _userManager.GetUserAsync(User);
        if (user is null) return Unauthorized();
        var claims = await _userManager.GetClaimsAsync(user);
        var roles = await _userManager.GetRolesAsync(user);
        var personalSites = await new PersonalMapAccess(HttpContext.RequestServices).SitesAsync(User);
        var mapDb = HttpContext.RequestServices.GetService<WayMarkDbContext>();
        var managedSites = mapDb is null || !roles.Contains("SiteManager") ? [] :
            await mapDb.SiteMapMemberships.AsNoTracking().Where(m => m.UserId == user.Id && m.IsActive && m.CanEditDrafts)
                .Join(mapDb.Sites.Where(s => !s.Code.StartsWith(PersonalMapAccess.Prefix)), m => m.SiteId, s => s.Id, (m, s) => new { s.Id, s.Name }).ToArrayAsync();
        return Ok(new {
            userName = user.UserName,
            displayName = claims.FirstOrDefault(c => c.Type == DisplayNameClaim)?.Value ?? user.UserName,
            email = user.Email,
            emailVerified = user.EmailConfirmed,
            roles = roles.Distinct().Order().ToArray(),
            capabilities = new {
                canCreatePersonalMaps = true,
                canManageMaps = personalSites.Length > 0 || roles.Any(r => r is "Admin" or "Creator" or "SiteManager"),
                canManageFacility = managedSites.Length > 0,
                isSystemAdmin = roles.Contains("Admin"),
                managedSites
            }
        });
    }

    [Authorize]
    [HttpPut("me")]
    public async Task<IActionResult> UpdateMe([FromBody] UpdateProfileRequest request)
    {
        var user = await _userManager.GetUserAsync(User);
        if (user is null) return Unauthorized();
        var name = request.DisplayName.Trim();
        if (name.Length == 0 || name.Length > 80 || name.Any(char.IsControl))
            return BadRequest(new { message = "Tên hiển thị cần 1–80 ký tự, không chứa ký tự điều khiển." });
        var existing = (await _userManager.GetClaimsAsync(user)).FirstOrDefault(c => c.Type == DisplayNameClaim);
        var claim = new Claim(DisplayNameClaim, name);
        var result = existing is null
            ? await _userManager.AddClaimAsync(user, claim)
            : await _userManager.ReplaceClaimAsync(user, existing, claim);
        if (!result.Succeeded) return Problem(statusCode: 503, title: "Không lưu được hồ sơ. Vui lòng thử lại.");
        // Whitelisted DTO changes only this user's display-name claim; no role,
        // username, email, verification, membership or password is writable here.
        return await Me();
    }

    [HttpPost("forgot-password")]
    [EnableRateLimiting("PasswordReset")]
    [AllowAnonymous]
    public async Task<IActionResult> ForgotPassword(
        [FromBody] ForgotPasswordRequest request)
    {
        var key = request.UsernameOrEmail.Trim();
        if (string.IsNullOrWhiteSpace(key))
        {
            return BadRequest(new { message = "Username hoặc email không được để trống." });
        }

        var user = await FindResetUser(key);

        if (user != null && !string.IsNullOrWhiteSpace(user.Email))
        {
            var token = await _userManager.GeneratePasswordResetTokenAsync(user);
            var resetUrl = _configuration["Frontend:ResetPasswordUrl"]
                ?? string.Empty; // The app also accepts the emailed token directly.

            try
            {
                await _emailService.SendPasswordResetEmailAsync(
                    user.Email!,
                    user.UserName ?? key,
                    token,
                    resetUrl,
                    HttpContext.RequestAborted);
            }
        catch (SmtpEmailException error)
            {
                // Do not leak SMTP failures to caller.
            HttpContext.RequestServices.GetService<ILogger<AuthController>>()?
                .LogWarning("Password reset delivery unavailable ({FailureKind}); no token/recipient logged", error.Failure);
            }
        }

        return Ok(new { message = "Nếu tài khoản tồn tại, email đặt lại mật khẩu đã được gửi." });
    }

    [HttpPost("reset-password")]
    [EnableRateLimiting("PasswordReset")]
    [AllowAnonymous]
    public async Task<IActionResult> ResetPassword(
        [FromBody] ResetPasswordRequest request)
    {
        var key = request.UsernameOrEmail.Trim();
        if (string.IsNullOrWhiteSpace(key))
        {
            return BadRequest(new { message = "Username hoặc email không được để trống." });
        }

        var user = await FindResetUser(key);

        if (user == null)
        {
            return BadRequest(new { message = "Không thể đặt lại mật khẩu. Kiểm tra tài khoản, token còn hạn và yêu cầu mật khẩu." });
        }

        var result = await _userManager.ResetPasswordAsync(
            user, request.Token, request.NewPassword);

        if (!result.Succeeded)
        {
            return BadRequest(new { message = "Không thể đặt lại mật khẩu. Kiểm tra tài khoản, token còn hạn và yêu cầu mật khẩu." });
        }

        return Ok(new { message = "Đặt lại mật khẩu thành công." });
    }

    private async Task<IdentityUser?> FindResetUser(string key)
    {
        if (!key.Contains('@')) return await _userManager.FindByNameAsync(key);
        // Email-shaped input always resolves the normalized EMAIL owner. A
        // different account whose username equals that address cannot shadow it.
        // Existing Identity permits duplicate email addresses. Never choose an
        // arbitrary account or let SingleOrDefault expose an ambiguous lookup.
        var normalized = _userManager.NormalizeEmail(key);
        var matches = await _userManager.Users.Where(u => u.NormalizedEmail == normalized)
            .Take(2).ToListAsync(HttpContext.RequestAborted);
        return matches.Count == 1 ? matches[0] : null;
    }
}
