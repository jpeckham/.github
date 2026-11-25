param(
    [Parameter(Mandatory)][string]$GodotVersion,
    [Parameter(Mandatory)][string]$Payload,
    [string]$ProjectNotices
)
$ErrorActionPreference = 'Stop'
if ($GodotVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'Expected an exact stable Godot version.' }
$destination = Join-Path ([IO.Path]::GetFullPath($Payload)) 'licenses'
New-Item -ItemType Directory -Force $destination | Out-Null
if ($ProjectNotices -and (Test-Path -LiteralPath $ProjectNotices)) {
    Get-ChildItem -LiteralPath $ProjectNotices -Force | Copy-Item -Destination $destination -Recurse
}
$base = "https://raw.githubusercontent.com/godotengine/godot/$GodotVersion-stable"
foreach ($notice in @{'LICENSE.txt'='GODOT_LICENSE.txt'; 'COPYRIGHT.txt'='GODOT_COPYRIGHT.txt'}.GetEnumerator()) {
    $target = Join-Path $destination $notice.Value
    Invoke-WebRequest "$base/$($notice.Key)" -OutFile $target
    if ((Get-Item -LiteralPath $target).Length -lt 1000 -or -not (Select-String -LiteralPath $target -SimpleMatch 'Godot' -Quiet)) { throw "Missing or invalid upstream notice: $($notice.Key)" }
}
Write-Output "Bundled Godot $GodotVersion engine/dependency notices and available project notices."
