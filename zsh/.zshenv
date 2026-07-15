# Make XDG the source of truth for config locations. Everything in this repo is
# stowed to ~/.config, and this also redirects tools that default to
# ~/Library/Application Support on macOS (e.g. lazygit) into ~/.config.
export XDG_CONFIG_HOME="$HOME/.config"

. "$HOME/.cargo/env"
