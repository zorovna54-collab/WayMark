namespace WayMark.Api.Services;

public interface ISmtpEmailService
{
    Task SendTestEmailAsync(DateTimeOffset sentAtUtc, CancellationToken cancellationToken);
}
