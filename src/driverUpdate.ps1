# -----------------------------------------------
#  driverUpdate.ps1 - Trusted Driver Update Check
# -----------------------------------------------
param(
    [switch]$ListOnly,
    [switch]$AutoYes,
    [switch]$NoColor
)

function Write-Color {
    param([string]$Text, [ConsoleColor]$Color = [ConsoleColor]::White)
    if ($NoColor) { Write-Host $Text }
    else          { Write-Host $Text -ForegroundColor $Color }
}

function Write-Header {
    param([string]$Title)
    Write-Color "" Cyan
    Write-Color "============================================================" Cyan
    Write-Color "  $Title" Cyan
    Write-Color "============================================================" Cyan
    Write-Color "" Cyan
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ResultCodeLabel {
    param([int]$Code)
    switch ($Code) {
        0 { "NotStarted" }
        1 { "InProgress" }
        2 { "Succeeded" }
        3 { "SucceededWithErrors" }
        4 { "Failed" }
        5 { "Aborted" }
        default { "Unknown($Code)" }
    }
}

function Get-CategorySummary {
    param($Update)
    $names = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $Update.Categories.Count; $i++) {
        $name = $Update.Categories.Item($i).Name
        if (-not [string]::IsNullOrWhiteSpace($name)) { [void]$names.Add($name) }
    }
    return ($names | Select-Object -Unique) -join ", "
}

function Get-DriverUpdates {
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $searcher.Online = $true
        $criteria = "IsInstalled=0 and IsHidden=0 and Type='Driver'"
        $searchResult = $searcher.Search($criteria)

        $updates = [System.Collections.Generic.List[object]]::new()
        for ($i = 0; $i -lt $searchResult.Updates.Count; $i++) {
            $update = $searchResult.Updates.Item($i)
            $sizeMb = if ($update.MaxDownloadSize -gt 0) { [math]::Round(($update.MaxDownloadSize / 1MB), 2) } else { 0 }
            $updates.Add([pscustomobject]@{
                Index          = $i + 1
                Title          = $update.Title
                Categories     = Get-CategorySummary -Update $update
                SizeMb         = $sizeMb
                RebootRequired = [bool]$update.RebootRequired
                UpdateObject   = $update
            })
        }

        return [pscustomobject]@{
            Session = $session
            Updates = $updates
        }
    }
    catch {
        throw "Windows Update search failed. Make sure the Windows Update service is available and that the machine can reach Microsoft Update. Details: $($_.Exception.Message)"
    }
}

function Show-DriverUpdates {
    param([object[]]$Updates)
    foreach ($update in $Updates) {
        Write-Color ("[{0}] {1}" -f $update.Index, $update.Title) White
        if ($update.Categories) {
            Write-Color ("    Categories : {0}" -f $update.Categories) DarkGray
        }
        Write-Color ("    Size       : {0} MB" -f $update.SizeMb) DarkGray
        Write-Color ("    Reboot     : {0}" -f ($(if ($update.RebootRequired) { 'May be required' } else { 'Not flagged' }))) DarkGray
        Write-Color "" Gray
    }
}

function Read-InstallSelection {
    param([object[]]$Updates)

    if ($AutoYes) {
        return ,$Updates
    }

    Write-Color "Install options:" Yellow
    Write-Color "  A = install all listed driver updates" Yellow
    Write-Color "  1,3 = install only selected items" Yellow
    Write-Color "  N = do not install anything" Yellow
    $selection = Read-Host "Choose updates to install"

    if ([string]::IsNullOrWhiteSpace($selection) -or $selection.ToUpper() -eq 'N') {
        return @()
    }

    if ($selection.ToUpper() -eq 'A') {
        return ,$Updates
    }

    $picked = [System.Collections.Generic.List[object]]::new()
    foreach ($token in ($selection -split ',')) {
        $trimmed = $token.Trim()
        $number = 0
        if ([int]::TryParse($trimmed, [ref]$number)) {
            $match = $Updates | Where-Object { $_.Index -eq $number } | Select-Object -First 1
            if ($match) { [void]$picked.Add($match) }
        }
    }

    return @($picked | Select-Object -Unique)
}

function Install-DriverUpdates {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][object[]]$SelectedUpdates
    )

    if ($SelectedUpdates.Count -eq 0) {
        return $null
    }

    if (-not (Test-IsAdministrator)) {
        throw "Driver installation requires an elevated PowerShell session (Run as Administrator)."
    }

    $collection = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($entry in $SelectedUpdates) {
        if (-not $entry.UpdateObject.EulaAccepted) {
            $entry.UpdateObject.AcceptEula()
        }
        [void]$collection.Add($entry.UpdateObject)
    }

    $downloader = $Session.CreateUpdateDownloader()
    $downloader.Updates = $collection
    $downloadResult = $downloader.Download()

    $installer = $Session.CreateUpdateInstaller()
    $installer.Updates = $collection
    $installResult = $installer.Install()

    return [pscustomobject]@{
        DownloadResult = $downloadResult
        InstallResult  = $installResult
    }
}

Write-Header "Trusted Driver Update Check"
Write-Color "This script only uses Windows Update / Microsoft Update via the Windows Update Agent." DarkGray
Write-Color "It does not download random driver packages from websites." DarkGray
Write-Color "" Gray

try {
    $scan = Get-DriverUpdates
}
catch {
    Write-Color "[!] $_" Red
    exit 1
}

if ($scan.Updates.Count -eq 0) {
    Write-Color "No new driver updates were offered by Windows Update." Green
    Write-Color "OEM tools such as Dell Command Update, Lenovo System Update, or HP Support Assistant may still offer vendor-specific updates." DarkYellow
    exit 0
}

Write-Header "Available Driver Updates"
Show-DriverUpdates -Updates $scan.Updates
Write-Color ("Found {0} driver update(s)." -f $scan.Updates.Count) Cyan

if ($ListOnly) {
    Write-Color "List-only mode enabled. No installation started." Yellow
    exit 0
}

$selectedUpdates = Read-InstallSelection -Updates $scan.Updates
if ($selectedUpdates.Count -eq 0) {
    Write-Color "No updates selected. Nothing was installed." Yellow
    exit 0
}

Write-Header "Installing Driver Updates"
try {
    $result = Install-DriverUpdates -Session $scan.Session -SelectedUpdates $selectedUpdates
}
catch {
    Write-Color "[!] $_" Red
    exit 1
}

$downloadCode = Get-ResultCodeLabel -Code ([int]$result.DownloadResult.ResultCode)
$installCode  = Get-ResultCodeLabel -Code ([int]$result.InstallResult.ResultCode)
Write-Color ("Download result: {0}" -f $downloadCode) DarkGray
Write-Color ("Install result : {0}" -f $installCode) DarkGray
Write-Color "" Gray

for ($i = 0; $i -lt $selectedUpdates.Count; $i++) {
    try {
        $itemResult = $result.InstallResult.GetUpdateResult($i)
        $status = Get-ResultCodeLabel -Code ([int]$itemResult.ResultCode)
        Write-Color ("[{0}] {1}" -f $selectedUpdates[$i].Index, $selectedUpdates[$i].Title) White
        Write-Color ("    Status : {0}" -f $status) $(if ($itemResult.ResultCode -eq 2 -or $itemResult.ResultCode -eq 3) { 'Green' } else { 'Red' })
        if ($itemResult.HResult -ne 0) {
            Write-Color ("    HResult: 0x{0}" -f ([Convert]::ToString(($itemResult.HResult -band 0xffffffff), 16).ToUpper())) DarkYellow
        }
    }
    catch {
        Write-Color ("[{0}] {1}" -f $selectedUpdates[$i].Index, $selectedUpdates[$i].Title) White
        Write-Color "    Status : result details unavailable" DarkYellow
    }
    Write-Color "" Gray
}

if ($result.InstallResult.RebootRequired) {
    Write-Color "A reboot is required to finish one or more driver updates." Yellow
}
else {
    Write-Color "No reboot was flagged by the installer." Green
}

