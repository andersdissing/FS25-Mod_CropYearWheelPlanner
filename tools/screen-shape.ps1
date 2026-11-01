# screen-shape.ps1
# Test the mod at other screen shapes (ModHub guideline 8.2: 4:3, 16:9, 16:10, 21:9, preferably 32:9).
# Sets FS25 to a window of the chosen size by editing game.xml; -Restore puts your own setting back.
# The game must be closed (the script refuses otherwise; FS25 rewrites game.xml when it exits).
#
#   pwsh -File tools\screen-shape.ps1 4:3        1280 x 960 window
#   pwsh -File tools\screen-shape.ps1 16:10      1680 x 1050 window
#   pwsh -File tools\screen-shape.ps1 21:9       1720 x 720 window (fits a 1920 wide screen)
#   pwsh -File tools\screen-shape.ps1 32:9       1920 x 540 window
#   pwsh -File tools\screen-shape.ps1 -Restore   back to your own setting

param(
    [ValidateSet('4:3', '16:10', '16:9', '21:9', '32:9')]
    [string]$Shape,
    [switch]$Restore
)

$ErrorActionPreference = 'Stop'

$GameDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'My Games\FarmingSimulator2025'
$GameXml = Join-Path $GameDir 'game.xml'
$Backup  = Join-Path $GameDir 'game.xml.crp-backup'

$Sizes = @{
    '4:3'   = @(1280, 960)
    '16:10' = @(1680, 1050)
    '16:9'  = @(1600, 900)
    '21:9'  = @(1720, 720)
    '32:9'  = @(1920, 540)
}

if (Get-Process -Name 'FarmingSimulator2025*' -ErrorAction SilentlyContinue) {
    throw 'Close Farming Simulator 25 first (it writes game.xml when it exits).'
}

if ($Restore) {
    if (-not (Test-Path $Backup)) {
        throw "No backup found ($Backup); nothing to restore."
    }
    Copy-Item $Backup $GameXml -Force
    Remove-Item $Backup
    Write-Host 'Restored your own display settings.'
    return
}
if (-not $Shape) {
    throw 'Give a shape (4:3, 16:10, 16:9, 21:9, 32:9) or -Restore.'
}

# Keep the original only once, so several shapes in a row still restore to your own setting
if (-not (Test-Path $Backup)) {
    Copy-Item $GameXml $Backup
}

[xml]$xml = Get-Content $GameXml -Raw
$display = $xml.game.graphic.display
$width, $height = $Sizes[$Shape]
$display.width = "$width"
$display.height = "$height"
$display.fullscreenMode = 'windowed'
$xml.Save($GameXml)
Write-Host "FS25 set to a $width x $height window ($Shape). Start the game and check:"
Write-Host '  - the on-screen plan (Full and Minimized, Top and Left)'
Write-Host '  - Esc > Crop Year Wheel Planner: Settings, Plans (both views), plan editor, Field groups'
Write-Host 'Afterwards: pwsh -File tools\screen-shape.ps1 -Restore'
