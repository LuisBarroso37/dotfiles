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

# neovim
move_config "$HOME/.config/nvim"              "$DOTFILES/nvim/.config/nvim"

# tmux
move_config "$HOME/.config/tmux/tmux.conf"   "$DOTFILES/tmux/.config/tmux/tmux.conf"

# sesh
move_config "$HOME/.config/sesh/sesh.toml"   "$DOTFILES/sesh/.config/sesh/sesh.toml"

# ghostty
move_config "$HOME/.config/ghostty"          "$DOTFILES/ghostty/.config/ghostty"

# fish
move_config "$HOME/.config/fish"             "$DOTFILES/fish/.config/fish"

# starship
move_config "$HOME/.config/starship.toml"    "$DOTFILES/starship/.config/starship.toml"

# atuin
move_config "$HOME/.config/atuin/config.toml" "$DOTFILES/atuin/.config/atuin/config.toml"

echo ""
echo "==> Installing stow (if missing)"
if ! command -v stow &>/dev/null; then
  brew install stow
fi

echo "==> Creating symlinks via stow"
cd "$DOTFILES"
PACKAGES=(nvim tmux sesh ghostty fish starship atuin)
for pkg in "${PACKAGES[@]}"; do
  echo "  -> stow $pkg"
  stow --target="$HOME" "$pkg"
done

echo ""
echo "Done! Your configs are now tracked in ~/dotfiles"
echo "Push to GitHub: cd ~/dotfiles && git init && git remote add origin <url> && git push -u origin main"
