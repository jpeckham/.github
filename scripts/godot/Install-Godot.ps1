param([Parameter(Mandatory)][string]$Version)
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^4\.\d+\.\d+$') { throw 'Expected a stable Godot 4.x.y version.' }
$destination = Join-Path $env:RUNNER_TEMP 'godot-toolchain'
New-Item -ItemType Directory -Force $destination | Out-Null
$base = "https://github.com/godotengine/godot-builds/releases/download/$Version-stable"
$sums = (Invoke-WebRequest "$base/SHA512-SUMS.txt").Content
if ($sums -is [byte[]]) { $sums = [Text.Encoding]::UTF8.GetString($sums) }
$engine = "Godot_v$Version-stable_win64.exe.zip"
$templates = "Godot_v$Version-stable_export_templates.tpz"
foreach ($asset in @($engine, $templates)) {
    $path = Join-Path $destination $asset
    Invoke-WebRequest "$base/$asset" -OutFile $path
    $line = @($sums -split "`n" | Where-Object { $_.Trim() -match ('\s+\*?' + [regex]::Escape($asset) + '$') })
    if ($line.Count -ne 1) { throw "Expected one official checksum for $asset" }
    $expected = ($line[0].Trim() -split '\s+')[0]
    if ((Get-FileHash $path -Algorithm SHA512).Hash -ine $expected) { throw "Checksum mismatch: $asset" }
}
Expand-Archive -LiteralPath (Join-Path $destination $engine) -DestinationPath $destination
$templateZip = Join-Path $destination 'templates.zip'
Copy-Item -LiteralPath (Join-Path $destination $templates) -Destination $templateZip
$unpacked = Join-Path $destination 'unpacked'
Expand-Archive -LiteralPath $templateZip -DestinationPath $unpacked
$templateDirectory = Join-Path $env:APPDATA "Godot/export_templates/$Version.stable"
New-Item -ItemType Directory -Force $templateDirectory | Out-Null
Copy-Item -Path "$unpacked/templates/*" -Destination $templateDirectory -Recurse
$executable = Join-Path $destination "Godot_v$Version-stable_win64_console.exe"
if (-not (Test-Path -LiteralPath $executable)) { throw 'Godot console executable missing.' }
"GODOT=$executable" >> $env:GITHUB_ENV
& $executable --version
if ($LASTEXITCODE -ne 0) { throw 'Godot version check failed.' }
