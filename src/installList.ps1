# -----------------------------------------------
#  installList.ps1 - Smart Program Installer
# -----------------------------------------------
param([switch]$SkipConfirmation, [switch]$DryRun)
$ProgramDatabase = @(
    @{ Name = "VLC Media Player"; Winget = "VideoLAN.VLC"; Chocolatey = "vlc"; Website = "https://www.videolan.org/vlc/"; Description = "Multimedia player" },
    @{ Name = "7-Zip"; Winget = "7zip.7zip"; Chocolatey = "7zip"; Website = "https://www.7-zip.org/"; Description = "Archive utility" },
    @{ Name = "Git"; Winget = "Git.Git"; Chocolatey = "git"; Website = "https://git-scm.com/download/win"; Description = "Version control" },
    @{ Name = "Node.js"; Winget = "OpenJS.NodeJS"; Chocolatey = "nodejs"; Website = "https://nodejs.org/"; Description = "JavaScript runtime" },
    @{ Name = "VS Code"; Winget = "Microsoft.VisualStudioCode"; Chocolatey = "vscode"; Website = "https://code.visualstudio.com/"; Description = "Code editor" },
    @{ Name = "Python"; Winget = "Python.Python.3.11"; Chocolatey = "python"; Website = "https://www.python.org/"; Description = "Programming language" },
    @{ Name = "Firefox"; Winget = "Mozilla.Firefox"; Chocolatey = "firefox"; Website = "https://www.mozilla.org/firefox/"; Description = "Web browser" },
    @{ Name = "Discord"; Winget = "Discord.Discord"; Chocolatey = "discord"; Website = "https://discord.com/download"; Description = "Voice chat" }
)
function Write-Header([string]$Title) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
}
function Test-CommandExists([string]$Cmd) { return $null -ne (Get-Command -Name $Cmd -ErrorAction SilentlyContinue) }
function Test-ProgramInstalled([string]$Name) {
    $found = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match [regex]::Escape($Name) }
    return $null -ne $found
}
Write-Header "Smart Program Installer"
$WingetAvailable = Test-CommandExists "winget"
$ChocolateyAvailable = Test-CommandExists "choco"
Write-Host "  Winget: $(if ($WingetAvailable) { 'Yes' } else { 'No' })" -ForegroundColor Gray
Write-Host "  Chocolatey: $(if ($ChocolateyAvailable) { 'Yes' } else { 'No' })" -ForegroundColor Gray
Write-Host ""
Write-Header "Available Programs"
for ($i = 0; $i -lt $ProgramDatabase.Count; $i++) {
    Write-Host "  [$($i+1)] $($ProgramDatabase[$i].Name)" -ForegroundColor White
}
Write-Host ""
$sel = Read-Host "Enter numbers (1,2,3) or 0 for all, Q to quit"
if ($sel -eq "Q") { exit 0 }
if ($sel -eq "0") { $selected = $ProgramDatabase }
else { 
    $selected = @()
    $sel -split "," | ForEach-Object { 
        $idx = [int]$_.Trim() - 1
        if ($idx -ge 0 -and $idx -lt $ProgramDatabase.Count) { $selected += $ProgramDatabase[$idx] }
    }
}
Write-Header "Installation Plan"
Write-Host "  Programs: $($selected.Count)" -ForegroundColor White
$selected | ForEach-Object { Write-Host "  • $($_.Name)" -ForegroundColor Cyan }
Write-Host ""
if (-not $SkipConfirmation) {
    $ans = Read-Host "Proceed? (Y/N)"
    if ($ans -ne "Y") { exit 0 }
}
Write-Header "Installing"
$success = 0
$failed = 0
$skipped = 0
foreach ($prog in $selected) {
    Write-Host "Installing: $($prog.Name)" -ForegroundColor Cyan
    if (Test-ProgramInstalled -Name $prog.Name) {
        Write-Host "  Already installed" -ForegroundColor Gray
        $skipped++
        Write-Host ""
        continue
    }
    if ($DryRun) {
        Write-Host "  [DryRun] Would install via Winget/Choco" -ForegroundColor Yellow
        $success++
        Write-Host ""
        continue
    }
    if ($WingetAvailable -and $prog.Winget) {
        try {
            & winget install $prog.Winget -e --silent 2>&1 | Out-Null
            Write-Host "  Success (Winget)" -ForegroundColor Green
            $success++
        } catch {
            Write-Host "  Failed (Winget)" -ForegroundColor Red
            $failed++
        }
    }
    elseif ($ChocolateyAvailable -and $prog.Chocolatey) {
        try {
            & choco install $prog.Chocolatey -y 2>&1 | Out-Null
            Write-Host "  Success (Choco)" -ForegroundColor Green
            $success++
        } catch {
            Write-Host "  Failed (Choco)" -ForegroundColor Red
            $failed++
        }
    }
    else {
        Write-Host "  Visit: $($prog.Website)" -ForegroundColor Yellow
        $failed++
    }
    Write-Host ""
}
Write-Header "Summary"
Write-Host "  Success: $success" -ForegroundColor Green
Write-Host "  Skipped: $skipped" -ForegroundColor Gray
Write-Host "  Failed: $failed" -ForegroundColor Red
Write-Host ""
