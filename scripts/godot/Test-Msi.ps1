param(
    [Parameter(Mandatory)][string]$Msi,
    [Parameter(Mandatory)][string]$Payload,
    [Parameter(Mandatory)][string]$LogDirectory
)
$ErrorActionPreference = 'Stop'
# This script must run only on a disposable GitHub-hosted runner.
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted') { throw 'MSI verification requires a GitHub-hosted runner.' }
New-Item -ItemType Directory -Force $LogDirectory | Out-Null
$installDirectory = Join-Path $env:RUNNER_TEMP 'installed-godot-game'
$package = (Resolve-Path -LiteralPath $Msi).Path
$installLog = Join-Path ([IO.Path]::GetFullPath($LogDirectory)) 'msi-install.log'
$uninstallLog = Join-Path ([IO.Path]::GetFullPath($LogDirectory)) 'msi-uninstall.log'
try {
    $process = Start-Process msiexec.exe -ArgumentList @('/i', "`"$package`"", '/qn', '/norestart', "INSTALLFOLDER=`"$installDirectory`"", '/l*v', "`"$installLog`"") -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(120000)) { $process.Kill(); throw 'MSI install timed out.' }
    if ($process.ExitCode -notin @(0,3010)) { throw "MSI install failed: $($process.ExitCode)" }
    $source = (Resolve-Path -LiteralPath $Payload).Path
    foreach ($file in Get-ChildItem -LiteralPath $source -Recurse -File) {
        $relative = [IO.Path]::GetRelativePath($source, $file.FullName)
        $installed = Join-Path $installDirectory $relative
        if (-not (Test-Path -LiteralPath $installed) -or (Get-FileHash -LiteralPath $installed).Hash -ne (Get-FileHash -LiteralPath $file.FullName).Hash) { throw "Installed payload differs: $relative" }
    }
} finally {
    $process = Start-Process msiexec.exe -ArgumentList @('/x', "`"$package`"", '/qn', '/norestart', '/l*v', "`"$uninstallLog`"") -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(120000)) { $process.Kill(); throw 'MSI uninstall timed out.' }
    if ($process.ExitCode -notin @(0,3010)) { throw "MSI uninstall failed: $($process.ExitCode)" }
}
if (Test-Path -LiteralPath $installDirectory) {
    if (@(Get-ChildItem -LiteralPath $installDirectory -Recurse -File).Count -gt 0) { throw 'Installed payload remains after uninstall.' }
}
Write-Output 'MSI payload hashes and uninstall verified.'
