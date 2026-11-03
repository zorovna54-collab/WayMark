namespace WayMark.Api.Services.MapDrafts;

internal sealed class ManagedStoragePaths
{
    public string Root { get; }
    public ManagedStoragePaths(string? root, string contentRoot, string? webRoot)
    {
        if (string.IsNullOrWhiteSpace(root) || !Path.IsPathFullyQualified(root) || root.StartsWith("\\\\", StringComparison.Ordinal)) throw Unsafe();
        Root = Path.TrimEndingDirectorySeparator(Path.GetFullPath(root));
        if (Root == Path.GetPathRoot(Root) || Within(Root, contentRoot) || (webRoot is not null && Within(Root, webRoot))) throw Unsafe();
        Check();
    }
    public void Check()
    {
        for (DirectoryInfo? directory = new(Root); directory is not null; directory = directory.Parent)
        {
            if (directory.Exists && (directory.Attributes & FileAttributes.ReparsePoint) != 0) throw Unsafe();
            if (Directory.Exists(Path.Combine(directory.FullName, ".git")) || System.IO.File.Exists(Path.Combine(directory.FullName, ".git"))) throw Unsafe();
        }
    }
    public string File(string area, string name)
    {
        Check();
        if (area is not ("objects" or "staging" or "leases") || Path.GetFileName(name) != name
            || name.IndexOfAny(['/', '\\', ':']) >= 0) throw Unsafe();
        var folder = Path.Combine(Root, area);
        RejectLink(folder);
        var path = Path.Combine(folder, name);
        RejectLink(path);
        return path;
    }
    public void Prepare()
    {
        Check();
        foreach (var area in new[] { "objects", "staging", "leases" })
        {
            var folder = Path.Combine(Root, area);
            RejectLink(folder);
            if (OperatingSystem.IsWindows()) Directory.CreateDirectory(folder);
            else Directory.CreateDirectory(folder, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
        }
        Check();
    }
    public static void RejectLink(string path)
    {
        if ((System.IO.File.Exists(path) || Directory.Exists(path)) && (System.IO.File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0) throw Unsafe();
        // LinkTarget also detects dangling links, for which Exists returns false.
        if (new FileInfo(path).LinkTarget is not null || new DirectoryInfo(path).LinkTarget is not null) throw Unsafe();
    }
    private static bool Within(string path, string parent)
    {
        var relative = Path.GetRelativePath(Path.GetFullPath(parent), path);
        return relative == "." || (!Path.IsPathRooted(relative) && relative != ".." && !relative.StartsWith(".." + Path.DirectorySeparatorChar, StringComparison.Ordinal));
    }
    private static DraftOperationException Unsafe() => new(503, "image_storage_configuration", "Image storage must be a private absolute directory outside the application, web root and any Git working tree, without symbolic links");
}
