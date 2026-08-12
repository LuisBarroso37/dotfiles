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

# Everything after the package step (submodules, stow, herdr, terminfo, TPM,
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
# jq is NOT optional: zsh/.zshrc's _herdr_ws_at / wth / wthr parse `herdr
# workspace list` through it. herdr likewise — the tracked .zshrc defines wth and
# wthr against it, so a machine without the binary gets dead functions.
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

# GUI apps, deliberately NOT on the fatal path.
#
# `brew install --cask ghostty` exits non-zero when /Applications/Ghostty.app
# already exists outside brew's control — which is the normal order of events,
# since you need a terminal before you can clone this repo. Under `set -e` that
# aborted the whole script at this line, so nothing was ever stowed and the run
# ended with no error banner.
#
# --adopt makes brew take ownership of an identical existing app instead of
# refusing. If it still fails (say the installed app is a different version),
# warn and carry on: a terminal emulator or a font is not worth abandoning the
# config bootstrap for, and the verification at the end reports the real state.
#
# Tolerating the failure is right; forgetting about it was not. Nothing re-checked
# these afterwards, so a font-jetbrains-mono-nerd-font that never landed still
# ended in "✓ all checks passed" and exit 0 while the prompt, tmux status line and
# yazi UI were full of tofu — a font has no binary for verify_install to look for.
# Recording it in FAILED_PKGS is how verification learns about it.
for _cask in ghostty font-jetbrains-mono-nerd-font karabiner-elements rectangle; do
  brew install --cask --adopt "$_cask" || {
    FAILED_PKGS+=" $_cask"
    echo "!! cask '$_cask' did not install — continuing without it." >&2
  }
done
unset _cask

# Karabiner-Elements: ~/.config/karabiner/ must stay a real directory — Karabiner
# writes runtime state (automatic_backups/, assets/, log/) into it at startup, so
# stow cannot own the directory. Symlink only the config file.
echo "==> Wiring karabiner config"
mkdir -p "$HOME/.config/karabiner"
ln -sfn "$DOTFILES/macos/karabiner/karabiner.json" "$HOME/.config/karabiner/karabiner.json" \
  || { FAILED_PKGS+=" karabiner-config"; echo "!! failed to link karabiner.json" >&2; }

# Rectangle: RectangleConfig.json is Rectangle's own export format, not a standard
# plist — defaults import does not apply. Import via the URL scheme instead; open
# launches Rectangle in the background (-g) if it is not already running.
echo "==> Importing Rectangle config"
open -g "rectangle://import?url=file://$DOTFILES/macos/rectangle/RectangleConfig.json"

# Optional per-machine install steps (extra packages, yazi's preview deps, etc.)
# live in an untracked install.local.sh next to this script — sourced here if it
# exists, so this tracked script stays portable. It's gitignored + stowignored.
if [ -f "$DOTFILES/install.local.sh" ]; then
  echo "==> Running install.local.sh (machine-specific)"
  # shellcheck source=/dev/null
  source "$DOTFILES/install.local.sh"
fi

finish_install
