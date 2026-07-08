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
  fish \
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

PACKAGES=(nvim tmux sesh ghostty fish starship atuin)

for pkg in "${PACKAGES[@]}"; do
  echo "  -> stow $pkg"
  stow --restow --target="$HOME" "$pkg"
done

echo "==> Setting fish as default shell (if not already)"
FISH_PATH="$(which fish)"
if ! grep -q "$FISH_PATH" /etc/shells; then
  echo "$FISH_PATH" | sudo tee -a /etc/shells
fi
if [ "$SHELL" != "$FISH_PATH" ]; then
  chsh -s "$FISH_PATH"
  echo "  Shell changed to fish — restart your terminal"
fi

echo ""
echo "Done! Restart your terminal to apply all changes."
