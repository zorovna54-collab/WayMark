using MailKit.Net.Smtp;
using MailKit.Security;
using Microsoft.Extensions.Options;
using MimeKit;

namespace WayMark.Api.Services;

public sealed class SmtpEmailService(
    IOptions<EmailTestOptions> options,
    ILogger<SmtpEmailService> logger) : ISmtpEmailService
{
    private static readonly TimeSpan SmtpTimeout = TimeSpan.FromSeconds(15);
    private readonly EmailTestOptions _settings = options.Value;

    public async Task SendTestEmailAsync(
        DateTimeOffset sentAtUtc,
        CancellationToken cancellationToken)
    {
        if (!_settings.HasRequiredSettings)
        {
            throw new SmtpEmailException(
                SmtpEmailFailure.Configuration,
                "Cấu hình SMTP chưa đầy đủ. Hãy thiết lập các giá trị Smtp trong User Secrets.");
        }

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(SmtpTimeout);

        using var client = new SmtpClient
        {
            Timeout = (int)SmtpTimeout.TotalMilliseconds
        };

        try
        {
            await client.ConnectAsync(
                _settings.Host!,
                _settings.Port,
                SecureSocketOptions.StartTls,
                timeout.Token);
            await client.AuthenticateAsync(
                _settings.Username!,
                _settings.AppPassword!,
                timeout.Token);

            var message = new MimeMessage();
            message.From.Add(new MailboxAddress(
                _settings.SenderName ?? "WayMark",
                _settings.FromEmail!));
            message.To.Add(MailboxAddress.Parse(_settings.TestRecipient!));
            message.Subject = "WayMark SMTP Test";

            var body = new TextPart("plain")
            {
                Text = $"Đây là email kiểm thử SMTP từ chức năng kiểm thử của WayMark.\nThời điểm gửi (UTC): {sentAtUtc:O}"
            };
            body.ContentType.Charset = "utf-8";
            message.Body = body;

            await client.SendAsync(message, timeout.Token);
        }
        catch (MailKit.Security.AuthenticationException)
        {
            logger.LogWarning("SMTP test failed: authentication rejected.");
            throw new SmtpEmailException(
                SmtpEmailFailure.Authentication,
                "Gmail từ chối xác thực SMTP. Hãy kiểm tra địa chỉ Gmail và App Password.");
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            logger.LogWarning("SMTP test failed: operation timed out.");
            throw new SmtpEmailException(
                SmtpEmailFailure.Timeout,
                "Kết nối SMTP quá thời gian chờ. Hãy thử lại sau.");
        }
        catch (Exception exception) when (
            exception is MailKit.Net.Smtp.SmtpCommandException or
            MailKit.Net.Smtp.SmtpProtocolException or
            MailKit.Security.SslHandshakeException or
            IOException or
            System.Net.Sockets.SocketException)
        {
            logger.LogWarning(
                "SMTP test failed with transport or delivery error ({FailureType}).",
                exception.GetType().Name);
            throw new SmtpEmailException(
                SmtpEmailFailure.Delivery,
                "Không thể kết nối hoặc gửi thư qua Gmail SMTP. Hãy kiểm tra mạng và cấu hình SMTP.");
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            logger.LogWarning(
                "SMTP test failed unexpectedly ({FailureType}).",
                exception.GetType().Name);
            throw new SmtpEmailException(
                SmtpEmailFailure.Delivery,
                "Không thể gửi email kiểm thử qua Gmail SMTP.");
        }
        finally
        {
            if (client.IsConnected)
            {
                try
                {
                    await client.DisconnectAsync(true, CancellationToken.None);
                }
                catch (Exception exception)
                {
                    logger.LogDebug(
                        "SMTP disconnect did not complete cleanly ({FailureType}).",
                        exception.GetType().Name);
                }
            }
        }
    }
}

public enum SmtpEmailFailure
{
    Configuration,
    Authentication,
    Timeout,
    Delivery
}

public sealed class SmtpEmailException(
    SmtpEmailFailure failure,
    string safeMessage) : Exception(safeMessage)
{
    public SmtpEmailFailure Failure { get; } = failure;
}
