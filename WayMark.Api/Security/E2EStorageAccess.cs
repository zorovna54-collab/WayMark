using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
using WayMark.Api.Services.MapDrafts;

namespace WayMark.Api.Security;

public static class E2EStorageAccess
{
    /// <summary>Open an existing directory for add-file/add-directory access; never create a probe file.</summary>
    public static void Verify(E2ESafetyProfile profile, string contentRoot)
    {
        _ = new ManagedStoragePaths(profile.ImageRoot, contentRoot, Path.Combine(contentRoot, "wwwroot"));
        if (!Directory.Exists(profile.ImageRoot)) throw E2ESafetyProfile.Refused("Operator must provision the private E2E image directory first");
        if (OperatingSystem.IsWindows())
        {
            using var handle = CreateFile(profile.ImageRoot, 0x0002 | 0x0004 | 0x0020,
                1 | 2 | 4, IntPtr.Zero, 3, 0x02000000, IntPtr.Zero);
            if (handle.IsInvalid) throw E2ESafetyProfile.Refused("E2E image directory lacks required filesystem access");
        }
        else if (Access(profile.ImageRoot, 2 | 1) != 0)
            throw E2ESafetyProfile.Refused("E2E image directory lacks write/traverse access");
    }
    [DllImport("kernel32.dll", EntryPoint = "CreateFileW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security,
        uint disposition, uint flags, IntPtr template);
    [DllImport("libc", EntryPoint = "access", SetLastError = true)]
    private static extern int Access(string path, int mode);
}
