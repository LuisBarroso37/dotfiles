#!/usr/bin/env bash
# Run this ONCE on your current machine to move configs into the dotfiles repo.
# After this, install.sh handles everything on new machines.
set -e

DOTFILES="$HOME/dotfiles"

move_config() {
  local src="$1"
  local dest="$2"
  if [ -e "$src" ] && [ ! -L "$src" ]; then
    mkdir -p "$(dirname "$dest")"
    mv "$src" "$dest"
    echo "  moved: $src -> $dest"
  else
    echo "  skip:  $src (missing or already a symlink)"
  fi
}

echo "==> Moving configs into dotfiles repo"

# ~/.config packages
move_config "$HOME/.config/nvim"              "$DOTFILES/nvim"
move_config "$HOME/.config/tmux"              "$DOTFILES/tmux"
move_config "$HOME/.config/sesh"              "$DOTFILES/sesh"
move_config "$HOME/.config/ghostty"           "$DOTFILES/ghostty"
move_config "$HOME/.config/starship.toml"     "$DOTFILES/starship.toml"

# atuin config.toml only (keep the rest of ~/.config/atuin/ intact)
if [ -f "$HOME/.config/atuin/config.toml" ] && [ ! -L "$HOME/.config/atuin/config.toml" ]; then
  mkdir -p "$DOTFILES/atuin"
  mv "$HOME/.config/atuin/config.toml" "$DOTFILES/atuin/config.toml"
  echo "  moved: ~/.config/atuin/config.toml -> $DOTFILES/atuin/config.toml"
fi

# zsh dotfiles (live in ~, not ~/.config)
mkdir -p "$DOTFILES/zsh"
move_config "$HOME/.zshrc"   "$DOTFILES/zsh/.zshrc"
move_config "$HOME/.zprofile" "$DOTFILES/zsh/.zprofile"
move_config "$HOME/.zshenv"  "$DOTFILES/zsh/.zshenv"

echo ""
echo "==> Installing stow (if missing)"
if ! command -v stow &>/dev/null; then
  brew install stow
fi

echo "==> Creating symlinks via stow"
cd "$DOTFILES"
stow .                        # ~/.config packages
stow --target="$HOME" zsh     # zsh dotfiles

echo ""
echo "Done! Your configs are now tracked in ~/dotfiles"
