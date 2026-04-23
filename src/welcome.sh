#!/bin/bash
# -----------------------------------------------
#  welcome.sh - Launch Applications (Bash/Linux)
# -----------------------------------------------
# Note: This version launches apps but does NOT tile windows.
# Window tiling is not portable across Linux desktop environments.
# For X11/Wayland window management, use a separate tool like wmctrl.

APPS=("thunderbird" "spotify" "todoist")
DRY_RUN=false
TIMEOUT_SECONDS=25
SKIP_STARTUP_AUDIO=false
STARTUP_AUDIO_SECONDS=4
STARTUP_AUDIO_PATH=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -DryRun) DRY_RUN=true; shift ;;
        -TimeoutSeconds) TIMEOUT_SECONDS="$2"; shift 2 ;;
        -SkipStartupAudio) SKIP_STARTUP_AUDIO=true; shift ;;
        -StartupAudioPath) STARTUP_AUDIO_PATH="$2"; shift 2 ;;
        -StartupAudioSeconds) STARTUP_AUDIO_SECONDS="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Find command helper
find_executable() {
    local cmd="$1"
    if command -v "$cmd" &>/dev/null; then
        command -v "$cmd"
    else
        return 1
    fi
}

# Start or reuse process
start_or_reuse_process() {
    local app_name="$1"
    local executable="$2"

    if pgrep -x "$(basename "$executable")" &>/dev/null; then
        echo "$app_name is already running. Reusing existing process."
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        if [[ -n "$executable" ]]; then
            echo "[DryRun] Would start $app_name from: $executable"
        else
            echo "[DryRun] $app_name executable was not found."
        fi
        return 0
    fi

    if [[ -z "$executable" ]]; then
        echo "[!] Could not find executable for $app_name."
        return 1
    fi

    "$executable" &
    sleep 0.3
    return 0
}

# Play startup audio
play_startup_audio() {
    local audio_path="$1"

    if [[ "$SKIP_STARTUP_AUDIO" == true ]]; then
        return
    fi

    if [[ -z "$audio_path" ]]; then
        audio_path="$(dirname "$0")/welcome.mp3"
    fi

    if [[ ! -f "$audio_path" ]]; then
        # Try fallback
        local fallback="$(dirname "$0")/startup_audio.wav"
        if [[ -f "$fallback" ]]; then
            audio_path="$fallback"
        else
            echo "Startup audio not found at '$audio_path'. Skipping audio."
            return
        fi
    fi

    # Use available audio player
    if command -v paplay &>/dev/null; then
        timeout "$STARTUP_AUDIO_SECONDS" paplay "$audio_path" 2>/dev/null
    elif command -v ffplay &>/dev/null; then
        timeout "$STARTUP_AUDIO_SECONDS" ffplay -nodisp -autoexit "$audio_path" 2>/dev/null
    elif command -v mpv &>/dev/null; then
        timeout "$STARTUP_AUDIO_SECONDS" mpv --no-video "$audio_path" 2>/dev/null
    else
        echo "No audio player found. Install paplay, ffplay, or mpv to enable startup audio."
    fi
}

# Main execution
echo "=========================================="
echo "   Welcome Script (Linux - App Launcher)"
echo "=========================================="
echo ""

# Find executables
thunderbird_exe=$(find_executable "thunderbird")
spotify_exe=$(find_executable "spotify")
# For Microsoft To Do on Linux, we can try the snap, web version, or similar alternatives
todoist_exe=$(find_executable "todoist" || find_executable "todo" || echo "")

# Start apps
start_or_reuse_process "Thunderbird" "$thunderbird_exe" || true
start_or_reuse_process "Spotify" "$spotify_exe" || true
start_or_reuse_process "Todoist/To Do" "$todoist_exe" || true

if [[ "$DRY_RUN" == true ]]; then
    echo "[DryRun] Script completed without starting applications."
    exit 0
fi

# Play startup audio
play_startup_audio "$STARTUP_AUDIO_PATH"

echo ""
echo "Applications launched successfully."
echo ""
echo "Note: Window tiling is not supported on Linux."
echo "To tile windows, use wmctrl or a tiling window manager."
echo ""

