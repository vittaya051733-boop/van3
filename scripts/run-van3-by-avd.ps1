$ErrorActionPreference = "Stop"

$adb = "C:\Users\TAM\AppData\Local\Android\Sdk\platform-tools\adb.exe"
$emulator = "C:\Users\TAM\AppData\Local\Android\Sdk\emulator\emulator.exe"
$avdName = "van3"

if (-not (Test-Path $adb)) {
    Write-Error "ไม่พบ adb ที่ path: $adb"
    exit 1
}

if (-not (Test-Path $emulator)) {
    Write-Error "ไม่พบ emulator ที่ path: $emulator"
    exit 1
}

function Get-EmulatorDevices {
    & $adb devices | Select-String "emulator-" | ForEach-Object {
        $parts = ($_ -split "\s+") | Where-Object { $_ }
        if ($parts.Count -ge 2) {
            [pscustomobject]@{ Id = $parts[0]; State = $parts[1] }
        }
    }
}

function Get-DeviceAvdName([string]$deviceId) {
    try {
        return (& $adb -s $deviceId emu avd name 2>$null | Select-Object -First 1).Trim()
    } catch {
        return ""
    }
}

function Find-Van3Device {
    $offline = $false
    foreach ($device in Get-EmulatorDevices) {
        $name = Get-DeviceAvdName $device.Id
        if ($name -eq $avdName) {
            if ($device.State -eq "device") {
                return [pscustomobject]@{ Id = $device.Id; Offline = $false }
            }
            $offline = $true
        }
    }
    return [pscustomobject]@{ Id = $null; Offline = $offline }
}

function Stop-StuckVan3Emulator {
    $processes = Get-CimInstance Win32_Process |
        Where-Object {
            ($_.Name -match "emulator|qemu") -and
            ($_.CommandLine -match "-avd\s+$avdName(\s|$)")
        }

    foreach ($process in $processes) {
        Write-Host "Stopping stuck $avdName emulator process $($process.ProcessId)"
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
    }

    & $adb kill-server | Out-Null
    & $adb start-server | Out-Null
}

function Start-Van3Emulator {
    Write-Host "Starting AVD $avdName with visible scale"
    Start-Process -FilePath $emulator -ArgumentList @("-avd", $avdName, "-scale", "0.25") | Out-Null

    $deadline = (Get-Date).AddMinutes(4)
    do {
        $match = Find-Van3Device
        if ($match.Id) {
            & $adb -s $match.Id wait-for-device | Out-Null
            return $match.Id
        }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    Write-Error "เปิด AVD $avdName แล้ว แต่รอให้ online ไม่สำเร็จ"
    exit 1
}

function Ensure-WindowApiLoaded {
    if ("WinMoveApi" -as [type]) {
        return
    }

    Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public class WinMoveApi {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
"@
}

function Restore-Van3EmulatorWindow {
    Ensure-WindowApiLoaded

    $targetProcesses = Get-CimInstance Win32_Process |
        Where-Object {
            ($_.Name -match "emulator|qemu") -and
            ($_.CommandLine -match "-avd\s+$avdName(\s|$)")
        } |
        Select-Object -ExpandProperty ProcessId

    if (-not $targetProcesses) {
        return
    }

    $windows = New-Object System.Collections.Generic.List[object]
    [WinMoveApi]::EnumWindows({
        param($hWnd, $lParam)
        $procId = 0
        [WinMoveApi]::GetWindowThreadProcessId($hWnd, [ref]$procId) | Out-Null
        if ($targetProcesses -contains [int]$procId) {
            $title = New-Object System.Text.StringBuilder 256
            [WinMoveApi]::GetWindowText($hWnd, $title, $title.Capacity) | Out-Null
            $titleText = $title.ToString()
            if ($titleText -match "Android Emulator - $avdName|^Emulator$") {
                $rect = New-Object WinMoveApi+RECT
                [WinMoveApi]::GetWindowRect($hWnd, [ref]$rect) | Out-Null
                $windows.Add([pscustomobject]@{
                    Handle = $hWnd
                    Title = $titleText
                    Left = $rect.Left
                    Top = $rect.Top
                    Width = [Math]::Max(320, $rect.Right - $rect.Left)
                    Height = [Math]::Max(480, $rect.Bottom - $rect.Top)
                }) | Out-Null
            }
        }
        return $true
    }, [IntPtr]::Zero) | Out-Null

    $main = $windows | Where-Object { $_.Title -match "Android Emulator - $avdName" } | Select-Object -First 1
    $toolbar = $windows | Where-Object { $_.Title -eq "Emulator" } | Select-Object -First 1

    if ($main) {
        $mainWidth = [Math]::Min([Math]::Max($main.Width, 359), 900)
        $mainHeight = [Math]::Min([Math]::Max($main.Height, 759), 780)
        [WinMoveApi]::ShowWindowAsync($main.Handle, 9) | Out-Null
        [WinMoveApi]::MoveWindow($main.Handle, 90, 20, $mainWidth, $mainHeight, $true) | Out-Null
        [WinMoveApi]::SetForegroundWindow($main.Handle) | Out-Null
        Write-Host "Restored $avdName emulator window to visible desktop"

        if ($toolbar) {
            [WinMoveApi]::ShowWindowAsync($toolbar.Handle, 9) | Out-Null
            [WinMoveApi]::MoveWindow($toolbar.Handle, 90 + $mainWidth + 4, 20, 65, 515, $true) | Out-Null
        }
    }
}

$target = Find-Van3Device
if (-not $target.Id) {
    if ($target.Offline) {
        Write-Host "พบ AVD $avdName แต่สถานะ offline กำลังปิดตัวที่ค้างและเปิดใหม่"
        Stop-StuckVan3Emulator
    }
    $targetId = Start-Van3Emulator
} else {
    $targetId = $target.Id
}

Restore-Van3EmulatorWindow

$projectRoot = Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath "..")
$devDir = Join-Path $projectRoot ".flutter-dev"
$runLog = Join-Path $devDir "run-output.log"
New-Item -ItemType Directory -Force -Path $devDir | Out-Null

Set-Location $projectRoot
Write-Host "Running van3 on $targetId (AVD: $avdName)"
Write-Host "Log: $runLog"
flutter run -d $targetId 2>&1 | Tee-Object -FilePath $runLog
