# Make XDG the source of truth for config locations. Everything in this repo is
# stowed to ~/.config, and this also redirects tools that default to
# ~/Library/Application Support on macOS (e.g. lazygit) into ~/.config.
export XDG_CONFIG_HOME="$HOME/.config"

# Keep the search arrays unique. .zprofile/.zshrc prepend entries and run for
# *every* login/interactive shell, so without this a nested shell inherits the
# parent's values and prepends them again — three levels deep meant three copies
# of each entry.
#
# fpath matters as much as PATH and is easy to miss: `brew shellenv` (run from
# .zprofile) prepends /opt/homebrew/share/zsh/site-functions to fpath on every
# login shell, and tmux/herdr panes are login shells. Measured 6 → 7 → 8 fpath
# entries at one/two/three levels of nesting, with the brew dir duplicated — and
# every duplicate is another directory compinit has to scan.
typeset -U path PATH fpath FPATH manpath MANPATH

# Silence Apple's /etc/zshrc_Apple_Terminal shell-session save/restore. It prints
# "Restored session:" / "Saving session..." into every interactive zsh (which
# corrupts the output of anything that captures a shell's stdout) and had grown
# ~/.zsh_sessions to 35 files. atuin owns shell history here, so the feature buys
# us nothing.
export SHELL_SESSIONS_DISABLE=1
