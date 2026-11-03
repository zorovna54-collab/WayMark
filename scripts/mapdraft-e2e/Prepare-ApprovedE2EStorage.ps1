[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string[]]$ProtectedRoots,
    [Parameter(Mandatory)][string]$RuntimeIdentitySid,
    [Parameter(Mandatory)][string]$ApprovalId,
    [Parameter(Mandatory)][ValidateSet('WayMark_MapDraft_E2E_Test')][string]$ConfirmDatabase,
    [Parameter(Mandatory)][string]$ApprovedManifestSha256
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'E2EPlan.psm1') -Force
Assert-PlanManifest -ApprovedManifestSha256 $ApprovedManifestSha256 -ForWrite
if ($ApprovalId -notmatch '^7B2D2-[A-Za-z0-9_-]{4,}$' -or ![OperatingSystem]::IsWindows()) { throw 'Explicit Windows storage approval required.' }
if (![IO.Path]::IsPathFullyQualified($Root) -or $Root.StartsWith('\\')) { throw 'Private absolute local root required.' }
$resolved=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Root))
if ((Split-Path (Split-Path $resolved -Parent) -Leaf) -cne 'WayMark_MapDraft_E2E_Test' -or (Split-Path $resolved -Leaf) -cne 'images') { throw 'Wrong dedicated storage path.' }
if (Test-Path -LiteralPath $resolved) { throw 'Directory already exists: no ACL changes or adoption permitted.' }
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if ($ProtectedRoots.Count -eq 0) { throw 'Protected-root inventory required.' }
foreach ($other in @($ProtectedRoots)+@($repo)) {
    if (![IO.Path]::IsPathFullyQualified($other)) { throw 'Protected roots must be absolute.' }
    foreach ($pair in @(@($resolved,$other),@($other,$resolved))) {
        $relative=[IO.Path]::GetRelativePath($pair[0],$pair[1])
        if ($relative -eq '.' -or (!$relative.StartsWith('..'+[IO.Path]::DirectorySeparatorChar) -and $relative -ne '..' -and ![IO.Path]::IsPathRooted($relative))) { throw 'Storage overlaps a protected root.' }
    }
}
for ($parent=[IO.DirectoryInfo]::new($resolved);$null -ne $parent;$parent=$parent.Parent) {
    if (($parent.Exists -and ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint)) -or
        (Test-Path -LiteralPath (Join-Path $parent.FullName '.git'))) { throw 'Git/reparse ancestry refused.' }
}
$sid=[Security.Principal.SecurityIdentifier]::new($RuntimeIdentitySid)
# New directory only; no recursion, no existing ACL or data modification.
New-Item -ItemType Directory -Path $resolved | Out-Null
& icacls.exe $resolved /inheritance:r /grant:r ('*'+$sid.Value+':(OI)(CI)M') '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'ACL setup failed. Stop; retain directory for inspection, no automatic cleanup.' }
Write-Output 'Created isolated E2E root and ACL; no files were uploaded.'
