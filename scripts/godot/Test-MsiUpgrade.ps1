param(
    [Parameter(Mandatory)][string]$Msi,
    [Parameter(Mandatory)][string]$Payload,
    [Parameter(Mandatory)][string]$ProductName,
    [Parameter(Mandatory)][string]$Manufacturer,
    [Parameter(Mandatory)][string]$Executable,
    [Parameter(Mandatory)][string]$UpgradeCode,
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$LogDirectory
)
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted') { throw 'MSI verification requires a GitHub-hosted runner.' }
if ([version]$Version -le [version]'0.0.0') { throw 'Upgrade verification requires a candidate version greater than 0.0.0.' }
$candidate = (Resolve-Path -LiteralPath $Msi).Path
$source = (Resolve-Path -LiteralPath $Payload).Path
$logs = [IO.Path]::GetFullPath($LogDirectory)
$fixture = Join-Path $env:RUNNER_TEMP ('godot-upgrade-' + [guid]::NewGuid().ToString('N'))
$baselinePayload = Join-Path $fixture 'payload'
$baseline = Join-Path $fixture 'baseline.msi'
$destination = Join-Path $fixture 'installed'
New-Item -ItemType Directory -Force $baselinePayload, $logs | Out-Null
Get-ChildItem -LiteralPath $source -Force | Copy-Item -Destination $baselinePayload -Recurse
$probe = '_obsolete-upgrade-probe.txt'
if (Test-Path -LiteralPath (Join-Path $source $probe)) { throw 'Payload collides with upgrade fixture probe.' }
'This file must disappear during the major upgrade.' | Set-Content -LiteralPath (Join-Path $baselinePayload $probe)
& "$PSScriptRoot/Build-Msi.ps1" -Payload $baselinePayload -ProductName $ProductName -Manufacturer $Manufacturer -Executable $Executable -UpgradeCode $UpgradeCode -Version '0.0.0' -Output $baseline

function Invoke-Installer([string]$operation, [string]$package, [string]$logName) {
    $log = Join-Path $logs $logName
    $process = Start-Process msiexec.exe -ArgumentList @($operation, "`"$package`"", '/qn', '/norestart', "INSTALLFOLDER=`"$destination`"", '/l*v', "`"$log`"") -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(120000)) { $process.Kill(); throw "MSI operation timed out: $logName" }
    return $process.ExitCode
}
function Assert-Payload {
    $expected = @(Get-ChildItem -LiteralPath $source -Recurse -File)
    $actual = @(Get-ChildItem -LiteralPath $destination -Recurse -File)
    if ($actual.Count -ne $expected.Count) { throw "Upgraded payload file count differs: $($actual.Count) versus $($expected.Count)." }
    foreach ($file in $expected) {
        $relative = [IO.Path]::GetRelativePath($source, $file.FullName)
        $installed = Join-Path $destination $relative
        if (-not (Test-Path -LiteralPath $installed) -or (Get-FileHash -LiteralPath $installed).Hash -ne (Get-FileHash -LiteralPath $file.FullName).Hash) { throw "Upgraded payload differs: $relative" }
    }
}
$installedPackage = $null
try {
    $code = Invoke-Installer '/i' $baseline 'msi-baseline-install.log'
    if ($code -notin @(0,3010)) { throw "Baseline install failed: $code" }
    $installedPackage = $baseline
    if (-not (Test-Path -LiteralPath (Join-Path $destination $probe))) { throw 'Baseline fixture probe was not installed.' }
    $code = Invoke-Installer '/i' $candidate 'msi-upgrade.log'
    if ($code -notin @(0,3010)) { throw "Candidate major upgrade failed: $code" }
    $installedPackage = $candidate
    if (Test-Path -LiteralPath (Join-Path $destination $probe)) { throw 'Major upgrade left an obsolete file.' }
    Assert-Payload
    $code = Invoke-Installer '/i' $baseline 'msi-downgrade.log'
    if ($code -notin @(1603,1638) -or -not (Select-String -LiteralPath (Join-Path $logs 'msi-downgrade.log') -SimpleMatch 'A newer version is already installed.' -Quiet)) { throw "Downgrade was not rejected by the major-upgrade guard: $code" }
    Assert-Payload
} finally {
    if ($null -ne $installedPackage) {
        $code = Invoke-Installer '/x' $installedPackage 'msi-upgrade-uninstall.log'
        if ($code -notin @(0,3010)) { throw "Upgrade fixture uninstall failed: $code" }
    }
}
if ((Test-Path -LiteralPath $destination) -and @(Get-ChildItem -LiteralPath $destination -Recurse -File).Count -gt 0) { throw 'Upgraded payload remains after uninstall.' }
Write-Output 'MSI major upgrade, obsolete-file removal, payload hashes, downgrade rejection and uninstall verified.'
