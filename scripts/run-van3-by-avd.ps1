$ErrorActionPreference = 'Stop'

$adb = 'C:\Users\TAM\AppData\Local\Android\Sdk\platform-tools\adb.exe'
if (-not (Test-Path $adb)) {
    Write-Error "ไม่พบ adb ที่ path: $adb"
    exit 1
}

$target = $null
$ids = (& $adb devices | Select-String 'emulator-' | ForEach-Object { ($_ -split '\s+')[0] })

foreach ($id in $ids) {
    $name = (& $adb -s $id emu avd name 2>$null | Select-Object -First 1).Trim()
    if ($name -eq 'van3') {
        $target = $id
        break
    }
}

if (-not $target) {
    Write-Error 'ไม่พบ emulator ที่ชื่อ van3 (AVD name)'
    exit 1
}

Set-Location (Resolve-Path (Join-Path $PSScriptRoot '..'))
Write-Host "Running van3 on $target (AVD: van3)"
flutter run -d $target
