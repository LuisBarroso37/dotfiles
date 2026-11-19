# PATH lives in .zprofile for login shells. mise is activated here for prompts.

# Herdr panes use xterm-256color, which lacks the undercurl capabilities their
# emulator supports. Select our compiled variant only inside herdr.
if [[ -n "$HERDR_PANE_ID$HERDR_WORKSPACE_ID" && "$TERM" == "xterm-256color" ]] \
  && infocmp xterm-256color-undercurl &>/dev/null; then
  export TERM=xterm-256color-undercurl
fi

# Refresh the completion dump once daily, then use compinit's fast path.
autoload -Uz compinit
if () { setopt localoptions extended_glob
        [[ -n ${ZDOTDIR:-$HOME}/.zcompdump(#qN.mh+24) ]] }; then
  compinit -i
else
  compinit -C
fi
export CARAPACE_BRIDGES='zsh,bash'
zstyle ':completion:*' format $'\e[2;37mCompleting %d\e[m'
command -v carapace &>/dev/null && source <(carapace _carapace)

command -v sesh &>/dev/null && eval "$(sesh completion zsh)"

# Works outside tmux too; sesh's picker now provides the preview and filtering.
s() {
  command -v sesh &>/dev/null || return 1
  sesh picker --icons --preview
}

export FZF_DEFAULT_OPTS=" \
 --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
 --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
 --color=marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8 \
 --color=selected-bg:#45475a \
 --multi"
if command -v fd &>/dev/null; then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
fi
command -v fzf &>/dev/null && source <(fzf --zsh)

command -v starship &>/dev/null && eval "$(starship init zsh)"
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"

# Don't let an older ~/.atuin/bin copy shadow a packaged Atuin and its DB schema.
command -v atuin &>/dev/null \
  || { [ -s "$HOME/.atuin/bin/env" ] && . "$HOME/.atuin/bin/env"; }
command -v atuin &>/dev/null && eval "$(atuin init zsh)"

# Worktrunk owns Git worktrees, including path selection, cleanup, and branch
# deletion. Source its directory-switching wrapper after compinit so completions
# work; `wt switch` can then change this shell's current directory.
command -v wt &>/dev/null && eval "$(wt config shell init zsh)"

command -v mise &>/dev/null && eval "$(mise activate zsh)"

# Yazi — cd into last directory on exit.
function y() {
	local tmp cwd
	tmp="$(mktemp "${TMPDIR:-/tmp}/yazi-cwd.XXXXXX")" || return 1
	yazi "$@" --cwd-file="$tmp"
	if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
		builtin cd -- "$cwd"
	fi
	rm -f -- "$tmp"
}

# Machine/work-specific settings and toolchains live in this untracked file.
if [ -f "$HOME/.zshrc.local" ]; then
  source "$HOME/.zshrc.local"
fi
