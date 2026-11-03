namespace WayMark.Api.Services;

/// <summary>E2E never connects to SMTP or exposes reset tokens through a test sink.</summary>
public sealed class E2EDisabledEmail : ISmtpEmailService
{
    private static SmtpEmailException Disabled() => new(SmtpEmailFailure.Configuration, "Email delivery is disabled in the isolated E2E environment.");
    public Task SendTestEmailAsync(DateTimeOffset sentAtUtc, CancellationToken cancellationToken) => throw Disabled();
    public Task SendPasswordResetEmailAsync(string toEmail, string username, string resetToken, string resetUrl,
        CancellationToken cancellationToken) => throw Disabled();
}
