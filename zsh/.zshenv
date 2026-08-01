# Make XDG the source of truth for config locations. Everything in this repo is
# stowed to ~/.config, and this also redirects tools that default to
# ~/Library/Application Support on macOS (e.g. lazygit) into ~/.config.
export XDG_CONFIG_HOME="$HOME/.config"

# Keep PATH unique. .zshrc prepends entries and runs for *every* interactive
# shell, so without this a nested shell inherits the parent's PATH and prepends
# them again — three levels deep meant three copies of each entry.
typeset -U path PATH
