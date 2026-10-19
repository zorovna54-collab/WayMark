using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using WayMark.Api.Services;
using WayMark.Api.Security;

namespace WayMark.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize(Policy = WayMarkSecurity.AdminPolicy)]
public sealed class EmailController(ISmtpEmailService emailService) : ControllerBase
{
    [HttpPost("test")]
    public async Task<IActionResult> SendTest(CancellationToken cancellationToken)
    {
        var sentAtUtc = DateTimeOffset.UtcNow;

        try
        {
            await emailService.SendTestEmailAsync(sentAtUtc, cancellationToken);
            return Ok(new
            {
                message = "Email kiểm thử đã được gửi.",
                sentAtUtc
            });
        }
        catch (SmtpEmailException exception)
        {
            var statusCode = exception.Failure switch
            {
                SmtpEmailFailure.Configuration => StatusCodes.Status503ServiceUnavailable,
                SmtpEmailFailure.Timeout => StatusCodes.Status504GatewayTimeout,
                _ => StatusCodes.Status502BadGateway
            };

            return StatusCode(statusCode, new { message = exception.Message });
        }
    }
}
