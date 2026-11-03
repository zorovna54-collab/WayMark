# REVIEW ONLY. Not executed. Requires explicit approval and an elevated terminal.
# Do not change execution policy to run this file. No SQL or server settings here.
[CmdletBinding()]
param([switch]$ExecuteApproved)
$ErrorActionPreference = 'Stop'
throw 'RETIRED: current Sprint 6 uses the existing Windows identity. Do not create a Windows account with this script.'
if (-not $ExecuteApproved) { throw 'WAITING FOR USER APPROVAL: Windows account and private directory setup not authorized.' }
$operatorIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$operatorPrincipal = New-Object System.Security.Principal.WindowsPrincipal($operatorIdentity)
if (-not $operatorPrincipal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'An approved elevated operator must perform this Windows step; no changes started.'
}
if ($env:COMPUTERNAME -ne 'LAPTOP-PFRPMR3O') { throw 'Wrong machine; no changes started.' }
if ($operatorIdentity.Name -ne 'LAPTOP-PFRPMR3O\pc') { throw 'Run under the approved operator account so DPAPI credentials remain readable by that operator.' }
$runKey = '2e5448b27c064a93a438f0d22a2edca6'
$runtimeName = 'wmcore6_2e5448b2'
$privateRoot = 'C:\WayMarkData\CoreSprint6\' + $runKey
if ((Get-LocalUser -Name $runtimeName -ErrorAction SilentlyContinue) -or (Test-Path -LiteralPath $privateRoot)) {
    throw 'Reserved account/path exists; stop rather than adopt, overwrite or delete.'
}
$privateAcl = New-Object System.Security.AccessControl.DirectorySecurity
$privateAcl.SetAccessRuleProtection($true,$false)
foreach ($sid in @($operatorIdentity.User.Value,'S-1-5-18','S-1-5-32-544')) {
    $identityReference = New-Object System.Security.Principal.SecurityIdentifier($sid)
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($identityReference,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
    $privateAcl.AddAccessRule($rule)
}
New-Item -ItemType Directory -Path $privateRoot | Out-Null
Set-Acl -LiteralPath $privateRoot -AclObject $privateAcl
$credentialsPath = Join-Path $privateRoot 'credentials'
New-Item -ItemType Directory -Path $credentialsPath | Out-Null
Set-Acl -LiteralPath $credentialsPath -AclObject $privateAcl
$bytes = New-Object byte[] 48
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
$securePassword = ConvertTo-SecureString ('Aa1!'+[Convert]::ToBase64String($bytes)) -AsPlainText -Force
[Array]::Clear($bytes,0,$bytes.Length)
$runtimeUser = New-LocalUser -Name $runtimeName -Password $securePassword -AccountExpires (Get-Date).AddDays(7) -Description ('WayMark Core Sprint 6 runtime only; '+$runKey)
Add-LocalGroupMember -Group (Get-LocalGroup -SID 'S-1-5-32-545') -Member $runtimeUser
# No Administrators membership or user-right/security-policy changes.
$credential = New-Object System.Management.Automation.PSCredential(($env:COMPUTERNAME+'\'+$runtimeName),$securePassword)
$credential | Export-Clixml -LiteralPath (Join-Path $credentialsPath 'windows-runtime.credential.xml')
# DPAPI file belongs to this operator account; a different elevated account must
# not run this step without reviewing how the original operator will launch.
$imageRoot = Join-Path $privateRoot 'images'
New-Item -ItemType Directory -Path $imageRoot | Out-Null
$imageAcl = Get-Acl -LiteralPath $imageRoot
$runtimeRule = New-Object System.Security.AccessControl.FileSystemAccessRule($runtimeUser.SID,'Modify','ContainerInherit,ObjectInherit','None','Allow')
$imageAcl.AddAccessRule($runtimeRule)
Set-Acl -LiteralPath $imageRoot -AclObject $imageAcl
$traverseRule = New-Object System.Security.AccessControl.FileSystemAccessRule($runtimeUser.SID,'ReadAndExecute','None','None','Allow')
$parentAcl = Get-Acl -LiteralPath $privateRoot
$parentAcl.AddAccessRule($traverseRule)
Set-Acl -LiteralPath $privateRoot -AclObject $parentAcl
# Failure retains partial setup for inspection; never auto-delete account/data.
Write-Output 'Approved Windows runtime setup completed; credentials withheld. SQL permissions still require the reviewed SQL provisioning step.'
