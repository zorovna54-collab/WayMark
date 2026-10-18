namespace WayMark.Api.Services;

public sealed class EmailTestOptions
{
    public const string SectionName = "Smtp";

    public string? Host { get; set; }
    public int Port { get; set; } = 587;
    public bool UseStartTls { get; set; } = true;
    public string? SenderName { get; set; }
    public string? Username { get; set; }
    public string? AppPassword { get; set; }
    public string? FromEmail { get; set; }
    public string? TestRecipient { get; set; }

    public bool HasRequiredSettings =>
        !string.IsNullOrWhiteSpace(Host) &&
        Port is > 0 and <= 65535 &&
        UseStartTls &&
        !string.IsNullOrWhiteSpace(Username) &&
        !string.IsNullOrWhiteSpace(AppPassword) &&
        IsEmailAddress(FromEmail) &&
        IsEmailAddress(TestRecipient);

    private static bool IsEmailAddress(string? address) =>
        !string.IsNullOrWhiteSpace(address) &&
        System.Net.Mail.MailAddress.TryCreate(address, out _);
}
