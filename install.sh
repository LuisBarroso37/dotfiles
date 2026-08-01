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
# sesh file, verification) is identical on both platforms and lives here.
# Sourced before anything touches $HOME: it runs the refuse-to-run-as-root check
# at source time and derives $BACKUP from $HOME.
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
brew install \
  neovim \
  tmux \
  sesh \
  starship \
  atuin \
  zoxide \
  bat \
  fzf \
  fd \
  ripgrep \
  carapace \
  stow \
  lazygit \
  gh \
  git-delta \
  yazi \
  mise \
  jq \
  herdr \
  shellcheck \
  ffmpeg \
  sevenzip \
  poppler \
  imagemagick

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
# anything else) belong in install.local.sh, sourced below.

brew install --cask ghostty font-jetbrains-mono-nerd-font

# Optional per-machine install steps (extra packages, yazi's preview deps, etc.)
# live in an untracked install.local.sh next to this script — sourced here if it
# exists, so this tracked script stays portable. It's gitignored + stowignored.
if [ -f "$DOTFILES/install.local.sh" ]; then
  echo "==> Running install.local.sh (machine-specific)"
  # shellcheck source=/dev/null
  source "$DOTFILES/install.local.sh"
fi

run_shared_tail
verify_install
print_next_steps
