using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Options;
using SkiaSharp;
using WayMark.Api.Services.MapDrafts;

namespace WayMark.Api.Tests;

// Real PNG/JPEG codec + actual files, always in an owned temp directory outside the repository.
internal sealed class ManagedImageTestStorage : IDisposable
{
    private readonly string parent = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "WayMarkImageStorageTests"));
    private readonly string owner = Guid.NewGuid().ToString("N");
    public string DirectoryPath { get; }
    public ManagedMapImageOptions Settings { get; }
    public IWebHostEnvironment Environment { get; }
    public ManagedImageTestStorage()
    {
        DirectoryPath = Path.Combine(parent, owner);
        Directory.CreateDirectory(DirectoryPath);
        File.WriteAllText(Path.Combine(DirectoryPath, ".test-owner"), owner);
        Settings = new() { Enabled = true, RootPath = Path.Combine(DirectoryPath, "private-images") };
        Environment = new ImageTestEnvironment { ContentRootPath = AppContext.BaseDirectory,
            WebRootPath = Path.Combine(AppContext.BaseDirectory, "wwwroot") };
    }
    public ManagedFileMapImageStorage Provider() => new(Options.Create(Settings), Environment, new MapImageCodec(), TimeProvider.System);
    public string DatabasePath => Path.Combine(DirectoryPath, "isolated.db");
    public static byte[] Image(string mime = "image/png")
    {
        using var bitmap = new SKBitmap(90, 60, SKColorType.Rgba8888, SKAlphaType.Premul);
        using var canvas = new SKCanvas(bitmap);
        canvas.Clear(SKColors.White);
        using var paint = new SKPaint { Color = SKColors.Red };
        canvas.DrawRect(new SKRect(0, 0, 45, 30), paint);
        paint.Color = SKColors.Blue; canvas.DrawRect(new SKRect(45, 0, 90, 30), paint);
        paint.Color = SKColors.Green; canvas.DrawRect(new SKRect(0, 30, 45, 60), paint);
        paint.Color = SKColors.Yellow; canvas.DrawRect(new SKRect(45, 30, 90, 60), paint);
        using var image = SKImage.FromBitmap(bitmap);
        using var encoded = image.Encode(mime == "image/png" ? SKEncodedImageFormat.Png : SKEncodedImageFormat.Jpeg, 90);
        return encoded.ToArray();
    }
    public void Dispose()
    {
        // Delete only this fixture's owned directory; never a workspace or an arbitrary computed root.
        var resolved = Path.GetFullPath(DirectoryPath);
        var relative = Path.GetRelativePath(parent, resolved);
        if (relative != owner || File.ReadAllText(Path.Combine(resolved, ".test-owner")) != owner)
            throw new InvalidOperationException("Unsafe test-directory cleanup refused");
        Microsoft.Data.Sqlite.SqliteConnection.ClearAllPools();
        Directory.Delete(resolved, true);
    }
    private sealed class ImageTestEnvironment : IWebHostEnvironment
    {
        public string EnvironmentName { get; set; } = "Development";
        public string ApplicationName { get; set; } = "WayMark.Api.Tests";
        public string WebRootPath { get; set; } = string.Empty;
        public IFileProvider WebRootFileProvider { get; set; } = new NullFileProvider();
        public string ContentRootPath { get; set; } = string.Empty;
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }
}
