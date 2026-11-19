#!/usr/bin/env bash
set -euo pipefail

# Resolve the repo from this script's own location, so the bootstrap works from a
# clone anywhere — not just ~/dotfiles.
DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# This script is macOS/Homebrew-only. On Linux, hand off to the native-package-
# manager bootstrap so nobody accidentally installs Homebrew-on-Linux.
if [ "$(uname -s)" != "Darwin" ]; then
  echo "install.sh is for macOS. On Linux, run ./install.linux.sh instead." >&2
  exit 1
fi

# Everything after the package step (stow, herdr, terminfo, TPM,
# sesh file, verification) is identical on both platforms and lives here, run by
# finish_install at the bottom. Sourced before anything touches $HOME: it runs
# the refuse-to-run-as-root check at source time and derives $BACKUP from $HOME.
# shellcheck source=install.common.sh
source "$DOTFILES/install.common.sh"

echo "==> Installing Homebrew (if missing)"
if ! command -v brew &>/dev/null; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# The installer does not put brew on PATH for the *current* shell, and on Apple
# Silicon /opt/homebrew/bin isn't on the default PATH at all — so the very next
# `brew install` would die with "command not found" on a fresh Mac. Load the
# environment explicitly, trying both prefixes.
if ! command -v brew &>/dev/null; then
  for _brew in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$_brew" ] && { eval "$("$_brew" shellenv)"; break; }
  done
  unset _brew
fi
command -v brew &>/dev/null || { echo "install.sh: brew not found after install" >&2; exit 1; }

echo "==> Installing packages"

# An array rather than one long `brew install` line, so the failure path below can
# retry the formulae one at a time and name the one that broke.
#
# jq is useful for querying JSON output from CLIs such as herdr and Worktrunk.
#
# The last four are yazi's preview backends, previously left to install.local.sh
# and therefore absent from every rebuild:
#   ffmpeg       → video thumbnails/preview
#   sevenzip     → archive previews
#   poppler      → PDF preview
#   imagemagick  → AVIF/HEIC/JXL image support
# Install the plain formulae, not the `-full` variants: those pull ~85 extra
# transitive deps (whisper-cpp, tesseract, vulkan-*, ghostscript) for previews
# that work fine without them.
#
# Machine-specific toolchains (embedded: arm-none-eabi-gdb, clang-format; JDKs;
# anything else) belong in install.local.sh, sourced at the bottom.
_formulae=(
  neovim
  tmux
  sesh
  starship
  atuin
  zoxide
  bat
  fzf
  fd
  ripgrep
  carapace
  stow
  lazygit
  gh
  git-delta
  yazi
  mise
  jq
  herdr
  worktrunk
  shellcheck
  ffmpeg
  sevenzip
  poppler
  imagemagick
)

# Formulae, deliberately NOT on the fatal path — for exactly the reason spelled
# out for the casks below.
#
# This was a single unguarded `brew install`, so any one formula failing (a bottle
# download blip, a source build that hasn't caught up with a just-released macOS —
# most likely on the four heavyweight preview backends at the end) took the whole
# script down at this line under `set -e`: nothing stowed, no terminfo, no TPM, no
# sesh.local.toml, no verification, and not even an error banner. The run simply
# ended. The config half of the bootstrap does not depend on any of these being
# present, so it gets to run regardless.
#
# The retry loop is not just for the error message: brew stops at the first
# formula it cannot install, so a failure in the middle of the list means the rest
# were never even attempted. Installing them individually picks those up. A
# formula whose binary is present afterwards is not recorded — brew exits non-zero
# for harmless reasons too (an already-installed keg it won't relink, say), and a
# working tool must not be reported as missing.
if ! brew install "${_formulae[@]}"; then
  echo "!! 'brew install' did not complete — retrying formula by formula to find out what failed." >&2
  for _formula in "${_formulae[@]}"; do
    brew install "$_formula" || have_tool "$_formula" || {
      FAILED_PKGS+=" $_formula"
      echo "!! formula '$_formula' did not install — continuing without it." >&2
    }
  done
  unset _formula
fi
unset _formulae

# Adopt identical existing apps. Continue after failures, but record them for verification.
# The font has no binary that verify_install can detect.
for _cask in ghostty font-jetbrains-mono-nerd-font; do
  brew install --cask --adopt "$_cask" || {
    FAILED_PKGS+=" $_cask"
    echo "!! cask '$_cask' did not install — continuing without it." >&2
  }
done
unset _cask

# Optional machine-specific steps live in the ignored install.local.sh.
if [ -f "$DOTFILES/install.local.sh" ]; then
  echo "==> Running install.local.sh (machine-specific)"
  # shellcheck source=/dev/null
  # || true: failures inside install.local.sh must not abort before finish_install
  # runs — without this, set -e would skip stow, terminfo, TPM, and verify_install.
  source "$DOTFILES/install.local.sh" || true
fi

finish_install
