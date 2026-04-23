#!/usr/bin/env bash
# -----------------------------------------------
# installList.sh - Smart Program Installer (Linux)
# -----------------------------------------------
# Strategy (safer first):
# 1) Native distro repositories (apt/dnf/pacman)
# 2) Flatpak or Snap (if available)
# 3) Official project website (manual fallback)

set -u

DRY_RUN=false
SKIP_CONFIRMATION=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|-n)
      DRY_RUN=true
      shift
      ;;
    --yes|-y)
      SKIP_CONFIRMATION=true
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: ./src/installList.sh [--dry-run] [--yes]"
      exit 1
      ;;
  esac
done

write_header() {
  echo
  echo "============================================================"
  echo "  $1"
  echo "============================================================"
  echo
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Linux package name mapping by installer backend
get_package_name() {
  local program="$1"
  local backend="$2"

  case "$program|$backend" in
    "Firefox|apt"|"Firefox|dnf"|"Firefox|pacman"|"Firefox|snap") echo "firefox" ;;
    "Firefox|flatpak") echo "org.mozilla.firefox" ;;

    "VLC|apt"|"VLC|dnf"|"VLC|pacman"|"VLC|snap") echo "vlc" ;;
    "VLC|flatpak") echo "org.videolan.VLC" ;;

    "Git|apt"|"Git|dnf"|"Git|pacman") echo "git" ;;

    "Node.js|apt"|"Node.js|dnf"|"Node.js|pacman"|"Node.js|snap") echo "nodejs" ;;

    "Python|apt"|"Python|dnf"|"Python|pacman") echo "python3" ;;

    "Discord|apt"|"Discord|dnf"|"Discord|pacman"|"Discord|snap") echo "discord" ;;
    "Discord|flatpak") echo "com.discordapp.Discord" ;;

    "VS Code|apt"|"VS Code|dnf"|"VS Code|pacman") echo "code" ;;
    "VS Code|snap") echo "code --classic" ;;
    "VS Code|flatpak") echo "com.visualstudio.code" ;;

    "7-Zip|apt") echo "p7zip-full" ;;
    "7-Zip|dnf"|"7-Zip|pacman") echo "p7zip" ;;
    *) echo "" ;;
  esac
}

# Official download pages used as manual fallback
get_website() {
  local program="$1"
  case "$program" in
    "Firefox") echo "https://www.mozilla.org/firefox/" ;;
    "VLC") echo "https://www.videolan.org/vlc/" ;;
    "Git") echo "https://git-scm.com/download/linux" ;;
    "Node.js") echo "https://nodejs.org/en/download" ;;
    "Python") echo "https://www.python.org/downloads/source/" ;;
    "VS Code") echo "https://code.visualstudio.com/download" ;;
    "Discord") echo "https://discord.com/download" ;;
    "7-Zip") echo "https://www.7-zip.org/download.html" ;;
    *) echo "" ;;
  esac
}

# Best-effort installed check
is_installed() {
  local program="$1"
  case "$program" in
    "Firefox") command_exists firefox ;;
    "VLC") command_exists vlc ;;
    "Git") command_exists git ;;
    "Node.js") command_exists node ;;
    "Python") command_exists python3 ;;
    "VS Code") command_exists code ;;
    "Discord") command_exists discord ;;
    "7-Zip") command_exists 7z ;;
    *) return 1 ;;
  esac
}

# Select first available backend, ordered by safer/default channel
choose_backend() {
  if command_exists apt-get; then echo "apt"; return; fi
  if command_exists dnf; then echo "dnf"; return; fi
  if command_exists pacman; then echo "pacman"; return; fi
  if command_exists flatpak; then echo "flatpak"; return; fi
  if command_exists snap; then echo "snap"; return; fi
  echo "none"
}

install_with_backend() {
  local backend="$1"
  local package_name="$2"

  if [[ -z "$package_name" ]]; then
    return 2
  fi

  if [[ "$DRY_RUN" == true ]]; then
    echo "  [DryRun] Would install using $backend: $package_name"
    return 0
  fi

  case "$backend" in
    apt)
      sudo apt-get update && sudo apt-get install -y "$package_name"
      ;;
    dnf)
      sudo dnf install -y "$package_name"
      ;;
    pacman)
      sudo pacman -Sy --noconfirm "$package_name"
      ;;
    flatpak)
      flatpak install -y flathub "$package_name"
      ;;
    snap)
      # package_name may include options (e.g. code --classic)
      # shellcheck disable=SC2086
      sudo snap install $package_name
      ;;
    *)
      return 2
      ;;
  esac
}

PROGRAMS=(
  "Firefox"
  "VLC"
  "Git"
  "Node.js"
  "Python"
  "VS Code"
  "Discord"
  "7-Zip"
)

write_header "Smart Program Installer (Linux)"

BACKEND="$(choose_backend)"
echo "Detected installer backend: $BACKEND"
if [[ "$BACKEND" == "none" ]]; then
  echo "No supported package manager found (apt/dnf/pacman/flatpak/snap)."
  echo "This script will provide official download links as fallback."
fi

echo
for i in "${!PROGRAMS[@]}"; do
  printf "[%d] %s\n" "$((i+1))" "${PROGRAMS[$i]}"
done

echo "[0] Install All"
echo "[Q] Quit"
read -r -p "Enter selection (e.g. 1,3 or 0): " SELECTION

if [[ "${SELECTION^^}" == "Q" ]]; then
  echo "Cancelled."
  exit 0
fi

SELECTED=()
if [[ "$SELECTION" == "0" ]]; then
  SELECTED=("${PROGRAMS[@]}")
else
  IFS=',' read -r -a PARTS <<< "$SELECTION"
  for p in "${PARTS[@]}"; do
    idx="$(echo "$p" | xargs)"
    if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#PROGRAMS[@]} )); then
      SELECTED+=("${PROGRAMS[$((idx-1))]}")
    fi
  done
fi

if (( ${#SELECTED[@]} == 0 )); then
  echo "No valid selection."
  exit 1
fi

write_header "Installation Plan"
for prog in "${SELECTED[@]}"; do
  pkg="$(get_package_name "$prog" "$BACKEND")"
  if [[ -n "$pkg" && "$BACKEND" != "none" ]]; then
    echo "- $prog via $BACKEND ($pkg)"
  else
    echo "- $prog via manual fallback"
  fi
done

echo
if [[ "$SKIP_CONFIRMATION" == false && "$DRY_RUN" == false ]]; then
  read -r -p "Proceed? (Y/N): " ANSWER
  if [[ "${ANSWER^^}" != "Y" ]]; then
    echo "Cancelled."
    exit 0
  fi
fi

SUCCESS=0
FAILED=0
SKIPPED=0

write_header "Installing"
for prog in "${SELECTED[@]}"; do
  echo "Installing: $prog"

  if is_installed "$prog"; then
    echo "  Already installed"
    SKIPPED=$((SKIPPED+1))
    echo
    continue
  fi

  pkg="$(get_package_name "$prog" "$BACKEND")"
  if [[ "$BACKEND" != "none" ]] && install_with_backend "$BACKEND" "$pkg"; then
    echo "  Success"
    SUCCESS=$((SUCCESS+1))
  else
    website="$(get_website "$prog")"
    if [[ -n "$website" ]]; then
      echo "  Could not auto-install safely on this system."
      echo "  Official download: $website"
    else
      echo "  No known install source."
    fi
    FAILED=$((FAILED+1))
  fi
  echo
done

write_header "Summary"
echo "Success: $SUCCESS"
echo "Skipped: $SKIPPED"
echo "Failed: $FAILED"

