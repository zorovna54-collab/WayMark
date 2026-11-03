using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.EntityFrameworkCore;
using WayMark.Api.Data;
using WayMark.Api.Services;

namespace WayMark.Api.Controllers;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record EmailBindingRequest([Required, EmailAddress, MaxLength(256)] string Email, [Required] string CurrentPassword);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record ConfirmEmailBindingRequest([Required, EmailAddress, MaxLength(256)] string Email, [Required, MaxLength(8192)] string Token);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record ChangeOwnPasswordRequest([Required] string CurrentPassword, [Required, MinLength(8), MaxLength(128)] string NewPassword);

[TypeFilter(typeof(AccountStorageExceptionFilter))]
public partial class AuthController
{
    // The nonunique NormalizedEmail index also covers old accounts. Serializable
    // range locking serializes this check with our registration/confirmation writes
    // without imposing a destructive unique constraint on legacy duplicate emails.
    private async Task<IDisposable?> EmailTransaction()
    {
        var db = HttpContext.RequestServices.GetRequiredService<AuthDbContext>();
        return db.Database.IsRelational() ? await db.Database.BeginTransactionAsync(IsolationLevel.Serializable) : null;
    }
    private Task<bool> EmailTaken(string normalized, string exceptId) => _userManager.Users
        .AnyAsync(u => u.NormalizedEmail == normalized && u.Id != exceptId, HttpContext.RequestAborted);

    [Authorize, HttpPost("me/email/request"), EnableRateLimiting("PasswordReset"), RequestSizeLimit(12288)]
    public async Task<IActionResult> RequestEmailBinding(EmailBindingRequest request)
    {
        var user = await _userManager.GetUserAsync(User);
        if (user is null) return Unauthorized();
        if (!await _userManager.CheckPasswordAsync(user, request.CurrentPassword))
            return BadRequest(new { message = "Mật khẩu hiện tại không đúng." });
        var email = request.Email.Trim();
        if (await EmailTaken(_userManager.NormalizeEmail(email)!, user.Id))
            return Conflict(new { message = "Không thể liên kết địa chỉ email này. Hãy dùng địa chỉ khác." });
        var token = await _userManager.GenerateChangeEmailTokenAsync(user, email);
        try {
            await _emailService.SendEmailVerificationAsync(email, user.UserName ?? "", token, HttpContext.RequestAborted);
        } catch (SmtpEmailException) {
            return Problem(statusCode: 503, title: "Chưa gửi được email xác minh. Email tài khoản chưa thay đổi.");
        }
        return Ok(new { message = "Đã gửi token xác minh. Email chỉ thay đổi sau khi bạn nhập token đúng, còn hạn." });
    }

    [Authorize, HttpPost("me/email/confirm"), EnableRateLimiting("PasswordReset"), RequestSizeLimit(12288)]
    public async Task<IActionResult> ConfirmEmailBinding(ConfirmEmailBindingRequest request)
    {
        try {
            using var transaction = await EmailTransaction();
            var user = await _userManager.GetUserAsync(User);
            if (user is null) return Unauthorized();
            var email = request.Email.Trim();
            if (await EmailTaken(_userManager.NormalizeEmail(email)!, user.Id))
                return Conflict(new { message = "Không thể liên kết địa chỉ email này. Hãy dùng địa chỉ khác." });
            var result = await _userManager.ChangeEmailAsync(user, email, request.Token);
            if (!result.Succeeded) return BadRequest(new { message = "Token sai, hết hạn hoặc đã được dùng. Email chưa thay đổi." });
            if (transaction is Microsoft.EntityFrameworkCore.Storage.IDbContextTransaction tx) await tx.CommitAsync();
            return Ok(new { message = "Email đã được xác minh cho tài khoản hiện tại. Hãy đăng nhập lại." });
        } catch (System.Data.Common.DbException) { return Conflict(new { message = "Có cập nhật email đồng thời. Vui lòng thử lại." }); }
        catch (DbUpdateException) { return Conflict(new { message = "Có cập nhật email đồng thời. Vui lòng thử lại." }); }
    }

    [Authorize, HttpPost("me/change-password"), EnableRateLimiting("PasswordReset"), RequestSizeLimit(2048)]
    public async Task<IActionResult> ChangeOwnPassword(ChangeOwnPasswordRequest request)
    {
        var user = await _userManager.GetUserAsync(User);
        if (user is null) return Unauthorized();
        var result = await _userManager.ChangePasswordAsync(user, request.CurrentPassword, request.NewPassword);
        if (!result.Succeeded) return BadRequest(new { message = "Mật khẩu hiện tại sai hoặc mật khẩu mới chưa đạt yêu cầu." });
        return Ok(new { message = "Đã đổi mật khẩu của tài khoản hiện tại. Hãy đăng nhập lại." });
    }
}

public sealed class AccountStorageExceptionFilter : IExceptionFilter
{
    public void OnException(ExceptionContext context)
    {
        if (context.Exception is not (System.Data.Common.DbException or DbUpdateException)) return;
        // Includes a deadlock victim from competing SERIALIZABLE email reservations.
        // The disposed transaction rolls back; no SQL details go to the client.
        context.Result = new ObjectResult(new ProblemDetails { Status = 409,
            Title = "Cập nhật tài khoản đồng thời hoặc storage chưa sẵn sàng. Tải lại rồi thử lại; chưa xác nhận thay đổi." }) { StatusCode = 409 };
        context.ExceptionHandled = true;
    }
}
