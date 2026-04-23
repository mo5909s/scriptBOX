#!/usr/bin/env bash
# -----------------------------------------------
# driverUpdate.sh - Trusted Driver/Firmware Update Check
# -----------------------------------------------
# Safe strategy:
# 1) fwupd / fwupdmgr for firmware supplied through LVFS
# 2) ubuntu-drivers for Ubuntu proprietary driver recommendations
# 3) distro package manager for installed driver-related package updates

set -u

DRY_RUN=false
AUTO_YES=false
LIST_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|-n)
      DRY_RUN=true
      shift
      ;;
    --yes|-y)
      AUTO_YES=true
      shift
      ;;
    --list-only)
      LIST_ONLY=true
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: ./src/driverUpdate.sh [--dry-run] [--yes] [--list-only]"
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

prompt_yes_no() {
  local message="$1"
  if [[ "$AUTO_YES" == true ]]; then
    return 0
  fi
  read -r -p "$message (Y/N): " answer
  [[ "${answer^^}" == "Y" ]]
}

detect_backend() {
  if command_exists apt-get; then echo "apt"; return; fi
  if command_exists dnf; then echo "dnf"; return; fi
  if command_exists pacman; then echo "pacman"; return; fi
  echo "none"
}

DRIVER_PATTERN='(nvidia|mesa|linux-firmware|firmware-|xserver-xorg-video|amdgpu|intel-media|intel-gpu|broadcom|realtek|rtl|iwlwifi|vulkan|libdrm|xf86-video|radeon)'

list_driver_package_updates() {
  local backend="$1"

  case "$backend" in
    apt)
      apt list --upgradable 2>/dev/null | tail -n +2 | grep -Ei "$DRIVER_PATTERN" || true
      ;;
    dnf)
      dnf check-update --refresh 2>/dev/null | grep -Ei "$DRIVER_PATTERN" || true
      ;;
    pacman)
      if command_exists checkupdates; then
        checkupdates 2>/dev/null | grep -Ei "$DRIVER_PATTERN" || true
      else
        pacman -Qu 2>/dev/null | grep -Ei "$DRIVER_PATTERN" || true
      fi
      ;;
    *)
      return 0
      ;;
  esac
}

extract_package_names() {
  local backend="$1"
  case "$backend" in
    apt)
      sed 's#/.*##' | awk 'NF'
      ;;
    dnf|pacman)
      awk '{print $1}' | awk 'NF'
      ;;
    *)
      cat
      ;;
  esac
}

install_driver_packages() {
  local backend="$1"
  shift
  local packages=("$@")

  if (( ${#packages[@]} == 0 )); then
    return 1
  fi

  if [[ "$DRY_RUN" == true ]]; then
    echo "  [DryRun] Would update packages via $backend: ${packages[*]}"
    return 0
  fi

  case "$backend" in
    apt)
      sudo apt-get update && sudo apt-get install --only-upgrade -y "${packages[@]}"
      ;;
    dnf)
      sudo dnf upgrade -y "${packages[@]}"
      ;;
    pacman)
      sudo pacman -Syu --noconfirm "${packages[@]}"
      ;;
    *)
      return 1
      ;;
  esac
}

write_header "Trusted Driver / Firmware Update Check"
echo "This script uses trusted Linux update channels only: fwupd, ubuntu-drivers, and your distro package manager."
echo "It does not scrape random driver download websites."

BACKEND="$(detect_backend)"
PACKAGE_UPDATE_LINES="$(list_driver_package_updates "$BACKEND")"
PACKAGE_NAMES=()
if [[ -n "$PACKAGE_UPDATE_LINES" ]]; then
  while IFS= read -r name; do
    [[ -n "$name" ]] && PACKAGE_NAMES+=("$name")
  done < <(printf '%s
' "$PACKAGE_UPDATE_LINES" | extract_package_names "$BACKEND" | awk '!seen[$0]++')
fi

FWUPD_OUTPUT=""
if command_exists fwupdmgr; then
  FWUPD_OUTPUT="$(fwupdmgr get-updates 2>&1 || true)"
fi

UBUNTU_DRIVERS_OUTPUT=""
if command_exists ubuntu-drivers; then
  UBUNTU_DRIVERS_OUTPUT="$(ubuntu-drivers list 2>/dev/null || true)"
fi

write_header "Detected Update Sources"
echo "Package backend : $BACKEND"
echo "fwupdmgr       : $(if command_exists fwupdmgr; then echo yes; else echo no; fi)"
echo "ubuntu-drivers : $(if command_exists ubuntu-drivers; then echo yes; else echo no; fi)"

FOUND_ANY=false

if [[ -n "$FWUPD_OUTPUT" && ! "$FWUPD_OUTPUT" =~ No[[:space:]]updatable[[:space:]]devices ]]; then
  FOUND_ANY=true
  write_header "Firmware Updates via fwupdmgr"
  echo "$FWUPD_OUTPUT"
fi

if [[ -n "$UBUNTU_DRIVERS_OUTPUT" ]]; then
  FOUND_ANY=true
  write_header "Ubuntu Driver Recommendations"
  echo "$UBUNTU_DRIVERS_OUTPUT"
  echo
  echo "If you proceed, the script uses: sudo ubuntu-drivers autoinstall"
fi

if (( ${#PACKAGE_NAMES[@]} > 0 )); then
  FOUND_ANY=true
  write_header "Driver-Related Package Updates"
  printf '%s
' "$PACKAGE_UPDATE_LINES"
fi

if [[ "$FOUND_ANY" == false ]]; then
  echo
  echo "No trusted driver or firmware updates were detected by the available tools."
  echo "Some hardware vendors may still provide updates via their own repositories or OEM utilities."
  exit 0
fi

if [[ "$LIST_ONLY" == true ]]; then
  echo
  echo "List-only mode enabled. No installation started."
  exit 0
fi

if [[ -n "$FWUPD_OUTPUT" && ! "$FWUPD_OUTPUT" =~ No[[:space:]]updatable[[:space:]]devices ]]; then
  if prompt_yes_no "Install firmware updates from fwupdmgr"; then
    if [[ "$DRY_RUN" == true ]]; then
      echo "  [DryRun] Would run: sudo fwupdmgr update"
    else
      sudo fwupdmgr update
    fi
  fi
fi

if [[ -n "$UBUNTU_DRIVERS_OUTPUT" ]]; then
  if prompt_yes_no "Apply Ubuntu recommended driver changes"; then
    if [[ "$DRY_RUN" == true ]]; then
      echo "  [DryRun] Would run: sudo ubuntu-drivers autoinstall"
    else
      sudo ubuntu-drivers autoinstall
    fi
  fi
fi

if (( ${#PACKAGE_NAMES[@]} > 0 )); then
  if prompt_yes_no "Install driver-related package updates from $BACKEND"; then
    install_driver_packages "$BACKEND" "${PACKAGE_NAMES[@]}"
  fi
fi

write_header "Finished"
echo "Driver update workflow completed. Reboot if your package manager or firmware tool asks for it."

