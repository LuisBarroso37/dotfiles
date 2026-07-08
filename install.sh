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
  stow \
  ghostty

echo "==> Stowing dotfiles"
cd "$DOTFILES"
stow .                        # ~/.config packages (nvim, tmux, sesh, ghostty, starship, atuin)
stow --target="$HOME" zsh     # zsh dotfiles live in ~, not ~/.config

echo ""
echo "Done! Restart your terminal to apply all changes."
