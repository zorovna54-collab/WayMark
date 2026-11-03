using System.Net.Http.Json;
using WayMark.Api.Contracts;
using WayMark.Api.Tests;

// Isolated SQLite + generated test image files ONLY. No appsettings, User Secrets, SQL Server or Identity login.
using var disk = new ManagedImageTestStorage();
await using var host = new MapDraftTestHost(disk.Provider(), sqlitePath: disk.DatabasePath, listenUrl: "http://127.0.0.1:5188");
await host.StartAsync();
var p = await PublishedMapTests.Create(host, await PublishedMapTests.Fixture(host));
var qr = await PublishedMapTests.Qr(host, p);
(await host.Client.PostAsJsonAsync($"/api/admin/map-projects/{p.Id}/publish", new PublishMapRequest(p.Version, true))).EnsureSuccessStatusCode();
host.Token("missing");
var resolved = await host.Client.GetFromJsonAsync<ResolveMapQrDto>("/api/public/qr/" + qr.Payload[6..]);
Console.WriteLine("ISOLATED FIXTURE API: http://127.0.0.1:5188/api (Android: http://10.0.2.2:5188/api)");
Console.WriteLine("SQLite + generated images. NOT SQL Server or actual hospital data. No login secret is output.");
Console.WriteLine("PUBLIC_QR=" + qr.Payload);
Console.WriteLine($"PUBLIC_MAP={resolved!.MapId}; version={resolved.Version}; 2 floors; 0 Rooms; path=13 meters.");
if (args.Length == 1)
{
    var root = Path.GetFullPath(args[0]);
    if (!root.EndsWith(Path.Combine("waymark", "build", "core-integration-evidence"), StringComparison.OrdinalIgnoreCase))
        throw new InvalidOperationException("Evidence output must be the ignored core-integration-evidence directory");
    Directory.CreateDirectory(root);
    File.WriteAllText(Path.Combine(root, "public-qr.txt"), qr.Payload); // A public locator, never a JWT.
}
Console.WriteLine("Press Ctrl+C to stop the isolated API and release its owned temporary test files.");
using var stop = new CancellationTokenSource();
Console.CancelKeyPress += (_, e) => { e.Cancel = true; stop.Cancel(); };
try { await Task.Delay(Timeout.InfiniteTimeSpan, stop.Token); } catch (OperationCanceledException) { }
