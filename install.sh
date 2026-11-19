#!/usr/bin/env bash
set -euo pipefail

# Resolve the repo from this script, regardless of the clone location.
DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Keep Homebrew installation limited to macOS.
if [ "$(uname -s)" != "Darwin" ]; then
  echo "install.sh is for macOS. On Linux, run ./install.linux.sh instead." >&2
  exit 1
fi

# Source shared steps before touching $HOME so the root guard runs first.
# shellcheck source=install.common.sh
source "$DOTFILES/install.common.sh"

echo "==> Installing Homebrew (if missing)"
if ! command -v brew &>/dev/null; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Load Homebrew into the current shell, trying both installation prefixes.
if ! command -v brew &>/dev/null; then
  for _brew in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$_brew" ] && { eval "$("$_brew" shellenv)"; break; }
  done
  unset _brew
fi
command -v brew &>/dev/null || { echo "install.sh: brew not found after install" >&2; exit 1; }

echo "==> Installing packages"

# Keep an array so failed installs can retry each formula separately.
# The last four provide yazi previews. Plain variants avoid unnecessary dependencies.
# Machine-specific toolchains belong in install.local.sh.
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
  chezmoi
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

# Homebrew stops at the first failure. Retry every formula and continue to chezmoi.
# Record only tools that remain missing, since a non-zero exit can leave a usable binary.
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
  # Continue to shared steps and verification even if local installation fails.
  source "$DOTFILES/install.local.sh" || true
fi

finish_install
