namespace WayMark.Api.Services;

public interface ISmtpEmailService
{
    Task SendEmailVerificationAsync(string toEmail, string username, string token, CancellationToken cancellationToken)
        => throw new SmtpEmailException(SmtpEmailFailure.Configuration, "Email verification delivery is unavailable.");
    Task SendTestEmailAsync(DateTimeOffset sentAtUtc, CancellationToken cancellationToken);
    Task SendPasswordResetEmailAsync(
        string toEmail,
        string username,
        string resetToken,
        string resetUrl,
        CancellationToken cancellationToken);
}
