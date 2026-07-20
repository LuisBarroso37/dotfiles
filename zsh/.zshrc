# PATH
export PATH="$HOME/.local/bin:$PATH"

# Carapace completions
autoload -Uz compinit && compinit
export CARAPACE_BRIDGES='zsh,bash'
zstyle ':completion:*' format $'\e[2;37mCompleting %d\e[m'
command -v carapace &>/dev/null && source <(carapace _carapace)

# Sesh (tmux session manager) completion
command -v sesh &>/dev/null && eval "$(sesh completion zsh)"

# Pick a session and connect to it — the shell-side twin of the tmux `T` binding
# (Ctrl+a T). Uses plain fzf (not fzf-tmux) so it also works before tmux starts.
s() {
  sesh connect "$(
    sesh list --icons | fzf \
      --no-sort --ansi --prompt '⚡  ' \
      --preview 'sesh preview {}' --preview-window 'right:55%'
  )"
}

# fzf
export FZF_DEFAULT_OPTS=" \
--color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
--color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
--color=marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8 \
--color=selected-bg:#45475a \
--multi"
# Use fd for fzf's scans so it respects .gitignore and includes hidden files —
# bare `fzf` and Ctrl-T otherwise fall back to `find` (no gitignore, no hidden).
# Ctrl-T = files, Alt-C = cd into dir. Guarded so a machine without fd still works.
if command -v fd &>/dev/null; then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
fi
command -v fzf &>/dev/null && source <(fzf --zsh)

# Starship prompt
command -v starship &>/dev/null && eval "$(starship init zsh)"

# Zoxide (smart cd)
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"

# Atuin shell history
[ -s "$HOME/.atuin/bin/env" ] && . "$HOME/.atuin/bin/env"
command -v atuin &>/dev/null && eval "$(atuin init zsh)"

# mise — unified runtime/version manager (node, java, python, …). Activating it
# is tracked & portable; the *languages* are chosen per machine and live in the
# untracked ~/.config/mise/config.toml (write it with e.g. `mise use -g node@lts
# java@corretto-25`). A fresh clone therefore starts language-free. Guarded so a
# machine without mise is a no-op.
command -v mise &>/dev/null && eval "$(mise activate zsh)"

# Language-tool bin dirs (portable, guarded no-ops when absent). The toolchains
# come from mise (go) and rustup (rust); these just expose the CLIs those tools
# install: `go install` → ~/go/bin, `cargo install` → ~/.cargo/bin.
[ -d "$HOME/go/bin" ] && export PATH="$HOME/go/bin:$PATH"
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

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
  # Delete the branch, being clever about *how* it was merged:
  #   • plain merge → it's an ancestor of main, so `git branch -d` succeeds.
  #   • squash/rebase merge (our repo's style) → the tip is NOT an ancestor, so
  #     `-d` fails. Ask GitHub if the PR merged; if so, force-delete (`-D`).
  #   • no merged PR → keep the branch (unmerged work is never force-deleted).
  if git branch -d "$branch" 2>/dev/null; then
    echo "✓ deleted branch '$branch' (merged into local base)"
  elif command -v gh >/dev/null 2>&1 \
    && gh pr list --head "$branch" --state merged --limit 1 --json number \
         --jq '.[0].number' 2>/dev/null | grep -q .; then
    git branch -D "$branch"
    echo "✓ force-deleted branch '$branch' (PR was squash/rebase-merged on GitHub)"
  else
    echo "• kept branch '$branch' (not merged anywhere — nothing lost)"
  fi
  tmux kill-session -t "=$session" 2>/dev/null
  echo "✓ removed worktree $dir (session '$session')"
  # Destroying a session from inside an attached client leaves tmux waiting for
  # the next input event before it repaints — so the output above (and the
  # returned prompt) wouldn't show until you pressed a key. Force the redraw.
  [[ -n "$TMUX" ]] && tmux refresh-client 2>/dev/null || true
}

# Rebase the current branch onto the latest default branch (main/master).
# Fetches first, so you rebase onto a fresh origin/<default>; auto-stashes
# uncommitted changes for the duration. After a successful rebase it also
# fast-forwards the main worktree's checkout — but only when that worktree is on
# <default> with a clean tree (it never rewrites and never touches a dirty or
# other-branch worktree).
wtrebase() {
  local def
  def="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"; def="${def#origin/}"
  if [[ -z "$def" ]]; then
    local b
    for b in main master; do
      git show-ref -q --verify "refs/remotes/origin/$b" && { def="$b"; break; }
    done
  fi
  def="${def:-main}"
  local cur; cur="$(git branch --show-current 2>/dev/null)"
  if [[ -z "$cur" ]]; then
    echo "wtrebase: detached HEAD or not a git repository" >&2
    return 1
  fi
  echo "Fetching origin…"
  git fetch --prune origin || return 1
  if [[ "$cur" == "$def" ]]; then
    echo "On $def — fast-forwarding to origin/$def."
    git merge --ff-only "origin/$def"
    return
  fi
  echo "Rebasing $cur onto origin/$def…"
  git rebase --autostash "origin/$def" || return 1
  # Also bring the main worktree's <default> checkout up to date, when it's safe.
  local main_wt; main_wt="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; main_wt="${main_wt%/.git}"
  local main_branch; main_branch="$(git -C "$main_wt" branch --show-current 2>/dev/null)"
  if [[ "$main_branch" != "$def" ]]; then
    echo "Note: main worktree is on '$main_branch', not '$def' — left it untouched."
  elif [[ -n "$(git -C "$main_wt" status --porcelain)" ]]; then
    echo "Note: main worktree has local changes — left '$def' untouched."
  else
    git -C "$main_wt" merge --ff-only "origin/$def" >/dev/null 2>&1 \
      && echo "Also fast-forwarded '$def' in $main_wt." \
      || echo "Note: '$def' in $main_wt could not fast-forward (diverged) — left untouched."
  fi
}

# Yazi — cd into last directory on exit
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	yazi "$@" --cwd-file="$tmp"
	if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
		builtin cd -- "$cwd"
	fi
	rm -f -- "$tmp"
}

# Machine/work-specific settings (Angular CLI completion, Docker host, STM32,
# and any toolchains not yet under mise like Go/Rust) live in an untracked
# ~/.zshrc.local, so this tracked config stays portable and a fresh machine
# starts clean. Language runtimes are handled by mise (activated above); pick
# versions per machine with `mise use -g`. Sourced LAST so anything here can
# still override earlier setup.
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
