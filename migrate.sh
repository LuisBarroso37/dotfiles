#!/usr/bin/env bash
# Run this ONCE on your current machine to move configs into the dotfiles repo.
# After this, install.sh handles everything on new machines.
set -e

DOTFILES="$HOME/dotfiles"
SCRATCH=$(mktemp -d)

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

move_config "$HOME/.config/nvim"              "$DOTFILES/nvim"
move_config "$HOME/.config/tmux"              "$DOTFILES/tmux"
move_config "$HOME/.config/sesh"              "$DOTFILES/sesh"
move_config "$HOME/.config/ghostty"           "$DOTFILES/ghostty"
move_config "$HOME/.config/fish"              "$DOTFILES/fish"
move_config "$HOME/.config/starship.toml"     "$DOTFILES/starship.toml"
move_config "$HOME/.config/atuin/config.toml" "$SCRATCH/atuin_config.toml"
if [ -f "$SCRATCH/atuin_config.toml" ]; then
  mkdir -p "$DOTFILES/atuin"
  mv "$SCRATCH/atuin_config.toml" "$DOTFILES/atuin/config.toml"
  echo "  moved: ~/.config/atuin/config.toml -> $DOTFILES/atuin/config.toml"
fi

echo ""
echo "==> Installing stow (if missing)"
if ! command -v stow &>/dev/null; then
  brew install stow
fi

echo "==> Creating symlinks via stow"
cd "$DOTFILES"
stow .

echo ""
echo "Done! Your configs are now tracked in ~/dotfiles"
echo "Push to GitHub: cd ~/dotfiles && git init && git remote add origin <url> && git push -u origin main"
