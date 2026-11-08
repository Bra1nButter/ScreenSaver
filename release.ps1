param(
    [Parameter(Mandatory=$true)]
    [string]$Version,
    [string]$Message = "Release v$Version"
)

$ErrorActionPreference = "Stop"
$CleanVer = $Version -replace '^[vV]', ''
$Tag = "v$CleanVer"

# 1. Обновляем версию в pubspec.yaml
$pubspec = Get-Content "pubspec.yaml" -Raw
if ($pubspec -match 'version:\s*[\d\.]+\+(\d+)') {
    $nextBuild = [int]$Matches[1] + 1
} else {
    $nextBuild = 1
}
$pubspec = $pubspec -replace 'version:\s*[^\r\n]+', "version: $CleanVer+$nextBuild"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Resolve-Path "pubspec.yaml"), $pubspec, $Utf8NoBom)

Write-Host "==> Версия в pubspec.yaml обновлена до $CleanVer+$nextBuild" -ForegroundColor Cyan

# 2. Коммит и тег
git add .
git commit -m $Message
git tag -a $Tag -m $Message

# 3. Отправка в GitHub
Write-Host "==> Отправка кода и тега $Tag в GitHub..." -ForegroundColor Cyan
git push origin HEAD
git push origin $Tag

Write-Host "[OK] Тег $Tag отправлен! GitHub Actions начал сборку APK: https://github.com/Bra1nButter/ScreenSaver/actions" -ForegroundColor Green