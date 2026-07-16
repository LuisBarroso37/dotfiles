# PATH
export PATH="$HOME/.local/bin:$PATH"

# Carapace completions
autoload -Uz compinit && compinit
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

# --- Git worktrees + tmux --------------------------------------------------
# Worktrees are sibling dirs named <repo>.<branch> (e.g. portal.ICP-1234-desc
# next to portal); each gets a tmux session named <repo>-<branch> (hyphens, since
# '.' is the session.window separator in tmux -t targets). sesh (Ctrl+a T) browses
# them.

# Create (or switch to) a worktree for <branch> and jump into its tmux session.
wtc() {
  local branch="$1"
  if [[ -z "$branch" ]]; then
    echo "usage: wtc <branch-name>" >&2
    return 1
  fi
  local main
  main="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
    || { echo "wtc: not inside a git repository" >&2; return 1; }
  main="${main%/.git}"                        # main worktree path
  local repo="${main:t}" parent="${main:h}"   # repo name + its parent dir
  local sani="${branch//\//-}"                 # branch made path/target-safe ('/' -> '-')
  local dir="$parent/$repo.$sani"              # worktree dir: <repo>.<branch> (git sibling)
  local session="$repo-$sani"                  # tmux session: hyphens only ('.' breaks -t targets)
  if [[ ! -d "$dir" ]]; then
    git worktree add -b "$branch" "$dir" 2>/dev/null \
      || git worktree add "$dir" "$branch" \
      || { echo "wtc: could not create worktree at $dir" >&2; return 1; }
  fi
  tmux has-session -t "=$session" 2>/dev/null \
    || tmux new-session -d -s "$session" -c "$dir"
  if [[ -n "$TMUX" ]]; then
    tmux switch-client -t "=$session"         # already in tmux: move client (no nesting)
  else
    tmux attach -t "=$session"
  fi
}

# Remove a worktree, its tmux session, and its branch (only if already merged).
# Defaults to the current branch; refuses when run from inside the session it
# would kill — run it from another session (e.g. your main worktree).
wtr() {
  local branch="${1:-$(git branch --show-current 2>/dev/null)}"
  if [[ -z "$branch" ]]; then
    echo "usage: wtr [branch-name]   (defaults to current branch)" >&2
    return 1
  fi
  if [[ "$branch" == (main|master) ]]; then
    echo "wtr: refusing to remove the main worktree ($branch)." >&2
    return 1
  fi
  local main
  main="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
    || { echo "wtr: not inside a git repository" >&2; return 1; }
  main="${main%/.git}"
  local repo="${main:t}" parent="${main:h}"
  local sani="${branch//\//-}"
  local dir="$parent/$repo.$sani"              # worktree dir: <repo>.<branch> (git sibling)
  local session="$repo-$sani"                  # tmux session: hyphens only ('.' breaks -t targets)
  if [[ -n "$TMUX" && "$(tmux display-message -p '#{session_name}')" == "$session" ]]; then
    echo "wtr: refusing — '$session' is the session you're in." >&2
    echo "     Run it from another session (e.g. your main worktree)." >&2
    return 1
  fi
  git worktree remove "$dir" || return 1
  git branch -d "$branch" 2>/dev/null         # deletes only if merged; keeps unmerged
  tmux kill-session -t "=$session" 2>/dev/null
  echo "✓ removed worktree $dir (session '$session')"
}

# Machine/work-specific settings (Node/NVM, Angular CLI, and language SDKs like
# pyenv, SDKMAN, Java, Go, Docker, Rust, …) live in an untracked ~/.zshrc.local,
# so this tracked config stays portable and a fresh machine starts clean. Sourced
# LAST so tools such as SDKMAN that must initialise at the end of .zshrc still do.
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
