param(
    [Parameter(Mandatory)][string]$Payload,
    [Parameter(Mandatory)][string]$ProductName,
    [Parameter(Mandatory)][string]$Manufacturer,
    [Parameter(Mandatory)][string]$Executable,
    [Parameter(Mandatory)][string]$UpgradeCode,
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$Output
)
$ErrorActionPreference = 'Stop'
$null = [guid]::Parse($UpgradeCode)
if ($Version -notmatch '^(\d+)\.(\d+)\.(\d+)$' -or [int]$Matches[1] -gt 255 -or [int]$Matches[2] -gt 255 -or [int]$Matches[3] -gt 65535) { throw 'MSI version must fit 255.255.65535.' }
if ($Executable -notmatch '^[A-Za-z0-9._-]+\.exe$') { throw 'Executable must be a plain .exe filename.' }
$source = (Resolve-Path -LiteralPath $Payload).Path
if (-not (Test-Path -LiteralPath (Join-Path $source $Executable))) { throw 'Exported game executable missing.' }
$files = @(Get-ChildItem -LiteralPath $source -Recurse -File | Sort-Object FullName)
if ($files.Count -eq 0) { throw 'Empty MSI payload.' }
function Escape([string]$value) { [System.Security.SecurityElement]::Escape($value) }
$name = Escape $ProductName
$maker = Escape $Manufacturer
$exe = Escape $Executable
$script:fileIndex = 0
$script:directoryIndex = 0
function PayloadDirectory([IO.DirectoryInfo]$directory) {
    $content = [System.Collections.Generic.List[string]]::new()
    foreach ($file in Get-ChildItem -LiteralPath $directory.FullName -File | Sort-Object Name) {
        $id = $script:fileIndex++
        $relative = [IO.Path]::GetRelativePath($source, $file.FullName)
        $shortcut = ''
        if ($relative -eq $Executable) {
            $shortcut = '<Shortcut Id="GameShortcut" Directory="ProgramMenuFolder" Name="' + $name + '" WorkingDirectory="INSTALLFOLDER" Advertise="yes" />'
        }
        $content.Add('<Component Id="C' + $id + '" Guid="*"><File Id="F' + $id + '" Source="' + (Escape $file.FullName) + '" KeyPath="yes">' + $shortcut + '</File></Component>')
    }
    foreach ($child in Get-ChildItem -LiteralPath $directory.FullName -Directory | Sort-Object Name) {
        $id = $script:directoryIndex++
        $content.Add('<Directory Id="D' + $id + '" Name="' + (Escape $child.Name) + '">' + (PayloadDirectory $child) + '</Directory>')
    }
    return $content -join "`n"
}
$components = PayloadDirectory (Get-Item -LiteralPath $source)
$refs = (0..($script:fileIndex-1) | ForEach-Object { '<ComponentRef Id="C' + $_ + '" />' }) -join "`n"
$xml = @"
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">
  <Package Name="$name" Manufacturer="$maker" Version="$Version" UpgradeCode="$UpgradeCode" Scope="perMachine" InstallerVersion="500">
    <MajorUpgrade DowngradeErrorMessage="A newer version is already installed." />
    <MediaTemplate EmbedCab="yes" />
    <StandardDirectory Id="ProgramFiles64Folder">
      <Directory Id="INSTALLFOLDER" Name="$name">
        $components
      </Directory>
    </StandardDirectory>
    <StandardDirectory Id="ProgramMenuFolder" />
    <Feature Id="Game" Title="$name" Level="1">$refs</Feature>
  </Package>
</Wix>
"@
$wxs = Join-Path $env:RUNNER_TEMP 'game-installer.wxs'
$xml | Set-Content -LiteralPath $wxs -Encoding utf8
$outputPath = [IO.Path]::GetFullPath($Output)
New-Item -ItemType Directory -Force (Split-Path $outputPath) | Out-Null
& wix build $wxs -arch x64 -o $outputPath
if ($LASTEXITCODE -ne 0) { throw 'WiX build failed.' }
