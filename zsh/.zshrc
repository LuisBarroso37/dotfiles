# NVM
# nvm is installed at ~/.nvm here. Don't use the XDG-conditional NVM_DIR snippet:
# once .zshenv exports XDG_CONFIG_HOME it resolves to ~/.config/nvm (which doesn't
# exist), so nvm.sh never loads and node/npm vanish from PATH.
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Pyenv
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
command -v pyenv &>/dev/null && eval "$(pyenv init - zsh)"

# SDKMAN
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

# STM32
export STM32_PRG_PATH=/Applications/STMicroelectronics/STM32Cube/STM32CubeProgrammer/STM32CubeProgrammer.app/Contents/MacOs/bin

# Angular CLI autocompletion
command -v ng &>/dev/null && source <(ng completion script)

# Java
export JAVA_HOME=$(/usr/libexec/java_home -v 25 2>/dev/null)
export PATH=$JAVA_HOME/bin:$PATH

# Docker
export DOCKER_HOST=unix://$HOME/.docker/run/docker.sock

# PATH
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/go/bin:$PATH"

# Carapace completions
autoload -U compinit && compinit
export CARAPACE_BRIDGES='zsh,fish,bash,inshellisense'
zstyle ':completion:*' format $'\e[2;37mCompleting %d\e[m'
command -v carapace &>/dev/null && source <(carapace _carapace)

# Sesh (tmux session manager) completion
command -v sesh &>/dev/null && eval "$(sesh completion zsh)"

# Pick a session with fzf and connect to it
alias s='sesh connect $(sesh list | fzf)'

# fzf
export FZF_DEFAULT_OPTS=" \
--color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
--color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
--color=marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8 \
--color=selected-bg:#45475a \
--multi"
command -v fzf &>/dev/null && source <(fzf --zsh)

# Starship prompt
command -v starship &>/dev/null && eval "$(starship init zsh)"

# Zoxide (smart cd)
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"

# Atuin shell history
[ -s "$HOME/.atuin/bin/env" ] && . "$HOME/.atuin/bin/env"
command -v atuin &>/dev/null && eval "$(atuin init zsh)"

if command -v wt >/dev/null 2>&1; then eval "$(command wt config shell init zsh)"; fi

# worktrunk's `sanitize` filter (used in config.toml hooks to name the tmux session)
# replaces "/" with "-" and leaves ICP-*/poc-* branch names otherwise unchanged. Keep
# this in sync so the session we target matches the one the hooks create/kill.
_wt_session() { print -r -- "${1//\//-}"; }

# Create (or switch to) a worktree and jump into its tmux session.
# The [pre-start] hook in config.toml creates the detached session; this attaches to it
# (switch-client when already inside tmux, so sessions don't nest).
wtc() {
  local branch="$1"
  if [[ -z "$branch" ]]; then
    echo "usage: wtc <branch-name>" >&2
    return 1
  fi
  local session; session="$(_wt_session "$branch")"
  if [[ -n "$TMUX" ]]; then
    wt switch --create "$branch" -x tmux -- switch-client -t "$session"
  else
    wt switch --create "$branch" -x tmux -- attach -t "$session"
  fi
}

# Remove a worktree (and, via the [pre-remove] hook, its tmux session).
# Refuses when run from inside the very session it would kill — that would tear down
# this shell mid-removal. Run it from another session (e.g. your main worktree) instead.
wtr() {
  if [[ -n "$TMUX" ]]; then
    local cur; cur="$(tmux display-message -p '#{session_name}')"
    local -a targets; local had_branch_arg=false a
    for a in "$@"; do
      [[ "$a" == -* ]] && continue          # skip flags; only branch/path args name sessions
      had_branch_arg=true
      targets+=("$(_wt_session "$a")")
    done
    if [[ "$had_branch_arg" == false ]]; then
      # No branch given -> removes current worktree, whose session is the sanitized branch.
      local b; b="$(git branch --show-current 2>/dev/null)"
      [[ -n "$b" ]] && targets+=("$(_wt_session "$b")")
    fi
    if (( ${targets[(Ie)$cur]} )); then
      echo "wtr: refusing — 'wt remove' would kill tmux session '$cur', the one you're in." >&2
      echo "     Run it from another session (e.g. your main worktree)." >&2
      return 1
    fi
  fi
  wt remove "$@"
}
