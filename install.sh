#!/usr/bin/env bash
set -e

DOTFILES="$HOME/dotfiles"

echo "==> Installing Homebrew (if missing)"
if ! command -v brew &>/dev/null; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

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
  mise

# Yazi optional dependencies — install per machine in install.local.sh:
#   brew install ffmpegthumbnailer ffmpeg sevenzip jq poppler imagemagick
#   ffmpegthumbnailer + ffmpeg  → video thumbnails/preview
#   sevenzip                    → archive previews
#   jq                          → JSON preview formatting
#   poppler                     → PDF preview
#   imagemagick                 → AVIF/HEIC/JXL image support

brew install --cask ghostty font-jetbrains-mono-nerd-font

echo "==> Initialising submodules"
cd "$DOTFILES"
git submodule update --init --recursive

# Stow BEFORE cloning TPM: this makes ~/.config/tmux a symlink into the repo, so the
# TPM clone below lands at ~/dotfiles/tmux/plugins/tpm (gitignored). Cloning first
# would create a real ~/.config/tmux directory and make `stow .` conflict on tmux.
echo "==> Stowing dotfiles"
stow --restow .               # ~/.config packages (nvim, tmux, sesh, ghostty, starship, atuin)
stow --restow --target="$HOME" zsh  # zsh dotfiles live in ~, not ~/.config

echo "==> Installing TPM (tmux plugin manager)"
if [ ! -d "$HOME/.config/tmux/plugins/tpm" ]; then
  git clone https://github.com/tmux-plugins/tpm "$HOME/.config/tmux/plugins/tpm"
fi

# sesh/sesh.toml imports a machine-specific session file; sesh errors if the
# import target is missing, so guarantee it exists (empty is fine). Put work/
# client project sessions here — it stays untracked, outside the dotfiles repo.
echo "==> Ensuring machine-specific sesh session file exists"
[ -f "$HOME/.config/sesh.local.toml" ] || touch "$HOME/.config/sesh.local.toml"

echo ""
echo "Done! Restart your terminal. In tmux run prefix+I to install plugins."
# gh needs a one-time interactive login before wtr's PR-merge cleanup works:
#   gh auth login
echo "Next: run 'gh auth login' so wtr can detect merged PRs."
