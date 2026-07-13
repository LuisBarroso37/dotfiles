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

echo "==> Installing TPM"
if [ ! -d "$HOME/.config/tmux/plugins/tpm" ]; then
  git clone https://github.com/tmux-plugins/tpm "$HOME/.config/tmux/plugins/tpm"
fi

echo "==> Stowing dotfiles"
stow .                        # ~/.config packages (nvim, tmux, sesh, ghostty, starship, atuin)
stow --target="$HOME" zsh     # zsh dotfiles live in ~, not ~/.config

echo ""
echo "Done! Restart your terminal. In tmux run prefix+I to install plugins."
