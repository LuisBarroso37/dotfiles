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
  worktrunk

brew install --cask ghostty font-jetbrains-mono-nerd-font

echo "==> Initialising submodules"
cd "$DOTFILES"
git submodule update --init --recursive

# Stow BEFORE cloning TPM: this makes ~/.config/tmux a symlink into the repo, so the
# TPM clone below lands at ~/dotfiles/tmux/plugins/tpm (gitignored). Cloning first
# would create a real ~/.config/tmux directory and make `stow .` conflict on tmux.
echo "==> Stowing dotfiles"
stow --restow .               # ~/.config packages (nvim, tmux, sesh, ghostty, starship, atuin, worktrunk)
stow --restow --target="$HOME" zsh  # zsh dotfiles live in ~, not ~/.config

echo "==> Installing TPM (tmux plugin manager)"
if [ ! -d "$HOME/.config/tmux/plugins/tpm" ]; then
  git clone https://github.com/tmux-plugins/tpm "$HOME/.config/tmux/plugins/tpm"
fi

echo ""
echo "Done! Restart your terminal. In tmux run prefix+I to install plugins."
