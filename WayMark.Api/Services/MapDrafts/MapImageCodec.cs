using System.Security.Cryptography;
using SkiaSharp;

namespace WayMark.Api.Services.MapDrafts;

public sealed record NormalizedMapImage(byte[] Bytes, string Mime, int Width, int Height, string Sha256);

/// <summary>Decode every pixel; re-encode without source EXIF/comments/trailing payloads.</summary>
public sealed class MapImageCodec
{
    // Bound native pixel allocations to one image per application instance.
    private readonly SemaphoreSlim decodeGate = new(1, 1);
    public async Task<NormalizedMapImage> NormalizeAsync(Stream input, string mime, CancellationToken ct)
    {
        if (!MapImageRules.Mime(mime)) throw Invalid();
        await decodeGate.WaitAsync(ct);
        try
        {
            using var bytes = new MemoryStream();
            var buffer = new byte[65536];
            int count;
            while ((count = await input.ReadAsync(buffer, ct)) != 0)
            {
                if (bytes.Length + count > MapImageRules.MaxBytes) throw TooLarge();
                bytes.Write(buffer, 0, count);
            }
            var data = bytes.ToArray();
            var png = data.AsSpan().StartsWith(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 });
            var jpeg = data.Length >= 4 && data[0] == 255 && data[1] == 216 && data[^2] == 255 && data[^1] == 217;
            if ((mime == "image/png" && (!png || !data.AsSpan().EndsWith(new byte[] { 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130 })))
                || (mime == "image/jpeg" && !jpeg)) throw Invalid();
            using var encoded = SKData.CreateCopy(data);
            using var codec = SKCodec.Create(encoded);
            if (codec is null || codec.FrameCount > 1 || codec.EncodedOrigin != SKEncodedOrigin.TopLeft
                || (mime == "image/png" ? codec.EncodedFormat != SKEncodedImageFormat.Png : codec.EncodedFormat != SKEncodedImageFormat.Jpeg)) throw Invalid();
            var info = codec.Info;
            if (info.Width is <= 0 or > 8192 || info.Height is <= 0 or > 8192 || (long)info.Width * info.Height > 32000000) throw Invalid();
            using var bitmap = new SKBitmap();
            var pixels = new SKImageInfo(info.Width, info.Height, SKColorType.Rgba8888, SKAlphaType.Premul);
            if (!bitmap.TryAllocPixels(pixels) || codec.GetPixels(pixels, bitmap.GetPixels()) != SKCodecResult.Success) throw Invalid();
            ct.ThrowIfCancellationRequested();
            using var image = SKImage.FromBitmap(bitmap);
            using var normalized = image.Encode(png ? SKEncodedImageFormat.Png : SKEncodedImageFormat.Jpeg, 90);
            if (normalized is null || normalized.Size > MapImageRules.MaxBytes) throw TooLarge();
            var output = normalized.ToArray();
            return new(output, mime, bitmap.Width, bitmap.Height, Convert.ToHexStringLower(SHA256.HashData(output)));
        }
        catch (DraftOperationException) { throw; }
        catch (OperationCanceledException) { throw; }
        catch (Exception error) when (error is ArgumentException or InvalidOperationException or OverflowException)
        { throw Invalid(); }
        finally { decodeGate.Release(); }
    }

    public static void ValidateFileName(string? name, string? mime)
    {
        if (name is null) return; // Raw-body clients may omit a filename entirely.
        if (string.IsNullOrWhiteSpace(name) || name.Length > 255 || name.Any(char.IsControl)
            || name.IndexOfAny(['/', '\\', ':']) >= 0 || name != name.Trim()) throw Invalid();
        var extension = Path.GetExtension(name).ToLowerInvariant();
        if (!(mime == "image/png" && extension == ".png")
            && !(mime == "image/jpeg" && extension is ".jpg" or ".jpeg")) throw Invalid();
    }
    private static DraftOperationException Invalid() => new(400, "invalid_image", "Expected a complete static PNG/JPG with matching MIME/extension, top-left orientation and valid dimensions");
    private static DraftOperationException TooLarge() => new(413, "image_too_large", "Encoded image exceeds 10 MiB");
}
