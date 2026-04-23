param(
    [switch]$DryRun,
    [int]$TimeoutSeconds = 25,
    [int]$PollMilliseconds = 250,
    [ValidateRange(0, 16)]
    [int]$ScreenIndex = 1,
    [string]$StartupAudioPath = "",
    [ValidateRange(1, 30)]
    [int]$StartupAudioSeconds = 4,
    [switch]$SkipStartupAudio
)

Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class NativeMethods
{
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetWindowPos(
        IntPtr hWnd,
        IntPtr hWndInsertAfter,
        int X,
        int Y,
        int cx,
        int cy,
        uint uFlags
    );

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@

function Resolve-Executable {
    param(
        [string]$CommandName,
        [string[]]$CandidatePaths
    )

    $command = Get-Command -Name $CommandName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command -and $command.Source) {
        return $command.Source
    }

    foreach ($path in $CandidatePaths) {
        if (Test-Path -LiteralPath $path) {
            return $path
        }
    }

    return $null
}

function Start-OrReuseProcess {
    param(
        [string]$AppName,
        [string]$ExecutablePath,
        [string[]]$ProcessNames,
        [string]$Arguments = "",
        [string]$ProtocolUri = ""
    )

    foreach ($processName in $ProcessNames) {
        $running = Get-Process -Name $processName -ErrorAction SilentlyContinue |
            Sort-Object -Property StartTime -Descending

        if ($running) {
            Write-Host "$AppName is already running. Reusing existing process."
            return $running[0]
        }
    }

    if ($DryRun) {
        if ($ExecutablePath) {
            Write-Host "[DryRun] Would start $AppName from: $ExecutablePath $Arguments"
        }
        elseif ($ProtocolUri) {
            Write-Host "[DryRun] Would start $AppName using protocol: $ProtocolUri"
        }
        else {
            Write-Host "[DryRun] $AppName executable was not found."
        }
        return $null
    }

    if (-not $ExecutablePath -and -not $ProtocolUri) {
        throw "Could not find executable for $AppName."
    }

    if ($ExecutablePath) {
        $started = if ([string]::IsNullOrWhiteSpace($Arguments)) {
            Start-Process -FilePath $ExecutablePath -PassThru
        }
        else {
            Start-Process -FilePath $ExecutablePath -ArgumentList $Arguments -PassThru
        }

        Start-Sleep -Milliseconds 300
        return Get-Process -Id $started.Id -ErrorAction SilentlyContinue
    }

    Start-Process -FilePath $ProtocolUri
    Start-Sleep -Milliseconds 600

    foreach ($processName in $ProcessNames) {
        $fromProtocol = Get-Process -Name $processName -ErrorAction SilentlyContinue |
            Sort-Object -Property StartTime -Descending |
            Select-Object -First 1
        if ($fromProtocol) {
            return $fromProtocol
        }
    }

    return $null
}

function Wait-ForMainWindow {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$AppName,
        [string[]]$ProcessNames,
        [string]$WindowTitlePattern = ""
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        if ($Process) {
            try {
                $Process.Refresh()
            }
            catch {
                throw "$AppName process could not be refreshed."
            }

            if (-not $Process.HasExited -and $Process.MainWindowHandle -and $Process.MainWindowHandle -ne 0) {
                return $Process.MainWindowHandle
            }
        }

        foreach ($processName in $ProcessNames) {
            $withWindow = Get-Process -Name $processName -ErrorAction SilentlyContinue |
                Where-Object { $_.MainWindowHandle -and $_.MainWindowHandle -ne 0 } |
                Sort-Object -Property StartTime -Descending |
                Select-Object -First 1

            if ($withWindow) {
                return $withWindow.MainWindowHandle
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($WindowTitlePattern)) {
            $byTitle = Get-Process -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.MainWindowHandle -and
                    $_.MainWindowHandle -ne 0 -and
                    $_.MainWindowTitle -match $WindowTitlePattern
                } |
                Sort-Object -Property StartTime -Descending |
                Select-Object -First 1

            if ($byTitle) {
                return $byTitle.MainWindowHandle
            }
        }

        Start-Sleep -Milliseconds $PollMilliseconds
    }

    throw "Timed out waiting for $AppName window after $TimeoutSeconds seconds."
}

function Get-TargetScreen {
    param(
        [int]$RequestedIndex
    )

    Add-Type -AssemblyName System.Windows.Forms
    $screens = [System.Windows.Forms.Screen]::AllScreens

    if (-not $screens -or $screens.Count -eq 0) {
        throw "No screens detected."
    }

    if ($RequestedIndex -ge 0 -and $RequestedIndex -lt $screens.Count) {
        return $screens[$RequestedIndex]
    }

    # Fallback to a guaranteed available screen if the requested index does not exist.
    $primary = $screens | Where-Object { $_.Primary } | Select-Object -First 1
    if ($primary) {
        $primaryIndex = [Array]::IndexOf($screens, $primary)
        Write-Host "Requested screen index $RequestedIndex not found. Falling back to primary screen index $primaryIndex."
        return $primary
    }

    Write-Host "Requested screen index $RequestedIndex not found. Falling back to first available screen."
    return $screens[0]
}

function Tile-Windows-OnScreen {
    param(
        [IntPtr[]]$WindowHandles,
        [int]$RequestedScreenIndex
    )

    $screen = Get-TargetScreen -RequestedIndex $RequestedScreenIndex
    $area = $screen.WorkingArea

    if (-not $WindowHandles -or $WindowHandles.Count -eq 0) {
        throw "No window handles were provided for tiling."
    }

    $columnCount = $WindowHandles.Count
    $baseColumnWidth = [int][Math]::Floor($area.Width / $columnCount)
    $remainder = $area.Width - ($baseColumnWidth * $columnCount)

    # Keep window z-order unchanged while resizing/repositioning.
    $SWP_NOZORDER = 0x0004
    $SW_RESTORE = 9

    function Apply-TileLayout {
        param(
            [IntPtr[]]$Handles,
            [System.Drawing.Rectangle]$WorkArea,
            [int]$Count,
            [int]$Width,
            [int]$Remaining,
            [uint32]$SetPosFlags,
            [int]$RestoreCode
        )

        $x = $WorkArea.X
        for ($j = 0; $j -lt $Count; $j++) {
            $plusOne = if ($j -lt $Remaining) { 1 } else { 0 }
            $w = $Width + $plusOne
            [void][NativeMethods]::ShowWindow($Handles[$j], $RestoreCode)
            [void][NativeMethods]::SetWindowPos($Handles[$j], [IntPtr]::Zero, $x, $WorkArea.Y, $w, $WorkArea.Height, $SetPosFlags)
            $x += $w
        }
    }

    # Apply twice because some UWP windows (like Microsoft To Do) override size right after launch.
    Apply-TileLayout -Handles $WindowHandles -WorkArea $area -Count $columnCount -Width $baseColumnWidth -Remaining $remainder -SetPosFlags $SWP_NOZORDER -RestoreCode $SW_RESTORE
    Start-Sleep -Milliseconds 450
    Apply-TileLayout -Handles $WindowHandles -WorkArea $area -Count $columnCount -Width $baseColumnWidth -Remaining $remainder -SetPosFlags $SWP_NOZORDER -RestoreCode $SW_RESTORE

    return $screen
}

function Play-StartupAudio {
    param(
        [string]$AudioPath,
        [int]$MaxSeconds
    )

    if ($SkipStartupAudio) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($AudioPath)) {
        $AudioPath = Join-Path $PSScriptRoot "welcome.mp3"
    }

    if (-not (Test-Path -LiteralPath $AudioPath)) {
        $fallbackPath = Join-Path $PSScriptRoot "startup_audio.wav"
        if (Test-Path -LiteralPath $fallbackPath) {
            $AudioPath = $fallbackPath
        }
        else {
            Write-Host "Startup audio not found at '$AudioPath'. Skipping audio."
            return
        }
    }

    try {
        Add-Type -AssemblyName PresentationCore
        $resolvedPath = [System.IO.Path]::GetFullPath($AudioPath)
        $player = New-Object System.Windows.Media.MediaPlayer
        $player.Open([System.Uri]::new($resolvedPath))
        Start-Sleep -Milliseconds 250
        $player.Play()
        Start-Sleep -Seconds $MaxSeconds
        $player.Stop()
        $player.Close()
    }
    catch {
        Write-Host "Could not play startup audio from '$AudioPath'."
    }
}

$roamingAppData = [Environment]::GetFolderPath("ApplicationData")
$localAppData = [Environment]::GetFolderPath("LocalApplicationData")
$programFiles = [Environment]::GetFolderPath("ProgramFiles")
$programFilesX86 = [Environment]::GetFolderPath("ProgramFilesX86")

$thunderbirdPath = Resolve-Executable -CommandName "thunderbird" -CandidatePaths @(
    (Join-Path $programFiles "Mozilla Thunderbird\thunderbird.exe"),
    (Join-Path $programFilesX86 "Mozilla Thunderbird\thunderbird.exe")
)

$spotifyPath = Resolve-Executable -CommandName "spotify" -CandidatePaths @(
    (Join-Path $roamingAppData "Spotify\Spotify.exe"),
    (Join-Path $localAppData "Microsoft\WindowsApps\Spotify.exe")
)

$toDoPath = Resolve-Executable -CommandName "todo" -CandidatePaths @(
    (Join-Path $localAppData "Microsoft\WindowsApps\Todo.exe"),
    (Join-Path $localAppData "Microsoft\WindowsApps\Microsoft.Todos.exe")
)

try {
    $thunderbirdProcess = Start-OrReuseProcess -AppName "Thunderbird" -ExecutablePath $thunderbirdPath -ProcessNames @("thunderbird")
    $spotifyProcess = Start-OrReuseProcess -AppName "Spotify" -ExecutablePath $spotifyPath -ProcessNames @("Spotify")
    $toDoProcess = Start-OrReuseProcess -AppName "Microsoft To Do" -ExecutablePath $toDoPath -ProtocolUri "ms-todo:" -ProcessNames @("Todo", "ToDo", "Microsoft.Todos")

    if ($DryRun) {
        Write-Host "[DryRun] Script completed without starting or moving windows."
        return
    }

    $thunderbirdWindow = Wait-ForMainWindow -Process $thunderbirdProcess -AppName "Thunderbird" -ProcessNames @("thunderbird")
    $spotifyWindow = Wait-ForMainWindow -Process $spotifyProcess -AppName "Spotify" -ProcessNames @("Spotify")
    $toDoWindow = Wait-ForMainWindow -Process $toDoProcess -AppName "Microsoft To Do" -ProcessNames @("Todo", "ToDo", "Microsoft.Todos", "ApplicationFrameHost") -WindowTitlePattern "To Do"

    $selectedScreen = Tile-Windows-OnScreen -WindowHandles @($thunderbirdWindow, $spotifyWindow, $toDoWindow) -RequestedScreenIndex $ScreenIndex
    Play-StartupAudio -AudioPath $StartupAudioPath -MaxSeconds $StartupAudioSeconds
    Write-Host "Thunderbird, Spotify, and Microsoft To Do are now tiled in 3 columns on screen '$($selectedScreen.DeviceName)' (requested index: $ScreenIndex)."
}
catch {
    Write-Error $_
    exit 1
}


