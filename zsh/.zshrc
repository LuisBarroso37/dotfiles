# PATH
export PATH="$HOME/.local/bin:$PATH"

# Undercurl inside herdr. herdr spawns every pane with TERM=xterm-256color, whose
# terminfo has no Smulx/Setulc — so neovim downgrades LSP diagnostics from a red
# squiggle to a plain underline, even though herdr's (ghostty-derived) emulator
# renders SGR 4:3 fine. Swap in the local entry that adds just those two caps
# (source + install step: dotfiles/terminfo/). Guarded on the compiled entry
# existing, so a machine that hasn't run install.sh yet just keeps xterm-256color.
if [[ -n "$HERDR_PANE_ID$HERDR_WORKSPACE_ID" && "$TERM" == "xterm-256color" ]] \
  && infocmp xterm-256color-undercurl &>/dev/null; then
  export TERM=xterm-256color-undercurl
fi

# Carapace completions
autoload -Uz compinit && compinit
export CARAPACE_BRIDGES='zsh,bash'
zstyle ':completion:*' format $'\e[2;37mCompleting %d\e[m'
command -v carapace &>/dev/null && source <(carapace _carapace)

# Sesh (tmux session manager) completion
command -v sesh &>/dev/null && eval "$(sesh completion zsh)"

# Pick a session and connect to it — the shell-side twin of the tmux `T` binding
# (Ctrl+b T — tmux keeps its stock prefix; Ctrl+a is herdr's). Uses plain fzf (not
# fzf-tmux) so it also works before tmux starts, which is the case this exists for.
s() {
  local sel
  sel="$(
    sesh list --icons | fzf \
      --no-sort --ansi --prompt '⚡  ' \
      --preview 'sesh preview {}' --preview-window 'right:55%'
  )" || return 0                      # fzf exits non-zero when you cancel
  [[ -n "$sel" ]] && sesh connect "$sel"
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

# Atuin shell history.
#
# The official curl installer drops a binary in ~/.atuin/bin and an env script
# that PREPENDS that directory to PATH — so on a machine where atuin also comes
# from brew/apt (which is what install.sh declares), the installer's copy can
# shadow the packaged one. The two then share ~/.local/share/atuin/history.db,
# and the moment the packaged atuin is upgraded it migrates that database past
# what the older shadow copy understands:
#   Error: migration <id> was previously applied but is missing in the resolved migrations
#
# So only fall back to the installer's copy when no packaged atuin exists — which
# is exactly the case install.linux.sh's own fallback hint creates on a distro
# that doesn't package atuin. Guarded, not deleted.
command -v atuin &>/dev/null \
  || { [ -s "$HOME/.atuin/bin/env" ] && . "$HOME/.atuin/bin/env" }
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

# --- Git worktrees + tmux / herdr ------------------------------------------
# Worktrees are subdirs named <parent>/<repo>/<branch-slug>; each gets a tmux
# session named <repo>/<branch-slug> (slashes are safe with the = exact-match
# prefix; '.' and ':' are not, so _wt_paths collapses them — see the note there).
# sesh (Ctrl+b T, tmux's stock prefix) browses tmux sessions; herdr (wth/wthr,
# under its own Ctrl+a prefix) manages the herdr workspaces.

# Resolve the repo's default branch from origin/HEAD, falling back to whichever
# of main/master exists on the remote. Repos that default to develop/trunk are
# then protected by the same guards as main-based ones.
_wt_default_branch() {
  local def b
  def="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
  def="${def#origin/}"
  if [[ -z "$def" ]]; then
    for b in main master; do
      git show-ref -q --verify "refs/remotes/origin/$b" && { def="$b"; break; }
    done
  fi
  print -r -- "${def:-main}"
}

# Shared guard for wtr/wthr: never tear down the worktree holding the branch the
# repo is based on. Also refuses main/master outright, so a repo that defaults to
# develop still protects them. $1 = branch, $2 = caller name for the message.
_wt_refuse_default() {
  [[ "$1" == (main|master) || "$1" == "$(_wt_default_branch)" ]] || return 0
  echo "$2: refusing to remove the default branch's worktree ($1)." >&2
  return 1
}

# Path of the worktree checked out on <branch>, asked of git rather than derived
# from the naming convention. Worktrees made by plain `git worktree add`, by
# herdr's own directory config, or under the pre-2026-08 naming scheme all live
# somewhere the convention wouldn't predict — deriving the path meant wtr/wthr
# failed with "not a working tree" on a worktree that plainly existed.
# Prints nothing when no worktree holds the branch; callers fall back.
_wt_dir_for_branch() {
  git worktree list --porcelain \
    | awk -v b="refs/heads/$1" '
        /^worktree /{p = substr($0, 10)}
        /^branch /  {if (substr($0, 8) == b) {print p; exit}}'
}

# Shared path derivation for wtc/wtr/wth/wthr. Assigns into the caller's scope
# (zsh dynamic scoping), so every caller declares the wt_* names `local` first —
# that keeps them out of the interactive shell. Returns 1 outside a git repo
# without printing, so each caller can name itself in the error.
#   wt_main    absolute path of the main checkout
#   wt_repo / wt_parent   its basename / parent dir
#   wt_sani    branch with '/', '.' and ':' collapsed to '-'
#   wt_dir     conventional worktree path  <parent>/<repo>/<slug>
#   wt_session tmux session name / herdr label  <repo>/<slug>
_wt_paths() {
  wt_main="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  wt_main="${wt_main%/.git}"
  wt_repo="${wt_main:t}"
  wt_parent="${wt_main:h}"
  # '.' and ':' are collapsed as well as '/', and not for cosmetics: tmux parses
  # '.' as the window.pane separator and ':' as session:window, so `-t "=$session"`
  # fails for any branch carrying one. The '=' exact-match prefix does NOT protect
  # against it — verified on an isolated socket, `tmux has-session -t
  # '=repo/release-1.2.0'` answers "can't find pane: 2.0". The visible damage was
  # in teardown: wtr removed the worktree, its kill-session silently failed, and
  # the resurrect snapshot then pointed at a directory that no longer existed.
  wt_sani="${${1//\//-}//[.:]/-}"
  wt_dir="$wt_parent/$wt_repo/$wt_sani"
  wt_session="$wt_repo/$wt_sani"
}

# Delete <branch> only if git can prove it is safe. Squash/rebase-merged branches
# have no ancestry to prove, so `-d` refuses them — `gh poi` sweeps those, asking
# the GitHub API whether the PR actually merged rather than guessing from local
# state (`gh extension install seachicken/gh-poi`).
#
# `git branch -d` alone is NOT the safety proof it looks like: it deletes a branch
# merged into *its own upstream*, not into the default branch. On a pushed branch
# whose PR is still open, git emits "warning: deleting branch 'x' that has been
# merged to 'refs/remotes/origin/x', but not yet merged to HEAD" and exits 0 — and
# the old `2>/dev/null` swallowed exactly that warning, so wtr reported
# "✓ deleted branch" while destroying work-in-progress. Hence the explicit
# ancestry check against the default branch before -d is allowed to run, and no
# redirect hiding what git says.
_wt_drop_branch() {
  local def ref out
  def="$(_wt_default_branch)"
  if git rev-parse --verify --quiet "origin/$def" >/dev/null 2>&1; then
    ref="origin/$def"
  elif git rev-parse --verify --quiet "$def" >/dev/null 2>&1; then
    ref="$def"
  else
    ref=""
  fi
  if [[ -n "$ref" ]] && ! git merge-base --is-ancestor "$1" "$ref" 2>/dev/null; then
    print -r -- "• kept branch '$1' (not merged into $ref — run 'gh poi' once its PR lands)"
    return 0
  fi
  if out="$(git branch -d "$1" 2>&1)"; then
    print -r -- "✓ deleted branch '$1'"
  else
    print -r -- "• kept branch '$1' (squash/rebase-merged — run 'gh poi' to clean up)"
    [[ -n "$out" ]] && print -r -- "  $out"
  fi
}

# Keep nested worktrees out of the main checkout's `git status`.
#
# wtc/wth place worktrees at <parent>/<repo>/<slug> — i.e. INSIDE the main
# checkout — so git reports each one as untracked, and `git add -A` there would
# stage a bogus gitlink. Nesting is deliberate (it is what lets Neovim's 'exrc'
# find the repo's .nvim.lua from inside a worktree), so the directories have to be
# ignored instead of moved.
#
# The list is regenerated from `git worktree list` rather than appended to, so it
# needs no manual upkeep: it is idempotent, drops entries when worktrees go away,
# and picks up worktrees made with a raw `git worktree add`. Everything is confined
# to a marked block, so the rest of info/exclude is untouched. info/exclude lives
# in the *common* git dir, so one block covers every worktree of the repo.
_wt_sync_excludes() {
  local common main ex
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 0
  main="${common%/.git}"
  ex="$common/info/exclude"
  mkdir -p "$common/info" 2>/dev/null || return 0

  local begin="# >>> nested worktrees (managed by wtc/wth — do not edit) >>>"
  local end="# <<< nested worktrees <<<"

  local -a entries=()
  local wt rel
  while IFS= read -r wt; do
    [[ "$wt" == "$main" ]] && continue
    # "$main" quoted inside the pattern: unquoted, a repo path containing glob
    # metacharacters ([ ? *) would be matched as a pattern instead of literally.
    rel="${wt#"$main"/}"
    [[ "$rel" == "$wt" ]] && continue          # not nested under the main checkout
    entries+=("/${rel%%/*}/")                  # top-level dir only, anchored
  done < <(git worktree list --porcelain | sed -n 's/^worktree //p')
  entries=("${(@u)entries}")

  local tmp="${ex}.wt.$$"
  if [[ -f "$ex" ]]; then
    awk -v b="$begin" -v e="$end" '
      $0 == b { skip = 1 }
      !skip   { print }
      $0 == e { skip = 0 }
    ' "$ex" > "$tmp" || { rm -f "$tmp"; return 0; }
  else
    : > "$tmp"
  fi
  if (( ${#entries} )); then
    {
      print -r -- "$begin"
      printf '%s\n' "${entries[@]}"
      print -r -- "$end"
    } >> "$tmp"
  fi
  mv -f "$tmp" "$ex" 2>/dev/null || rm -f "$tmp"
}

# Re-save the tmux-resurrect snapshot. Called after a session is killed: the last
# snapshot still lists it, so a fresh tmux server would resurrect a session whose
# directory is gone (tmux silently falls back to $HOME) and it would linger in
# `sesh list -t` forever. Overwriting the snapshot with current state is the fix.
# No-op when resurrect isn't installed or no server is running.
_wt_resurrect_save() {
  local save="$HOME/.config/tmux/plugins/tmux-resurrect/scripts/save.sh"
  [[ -x "$save" ]] || return 0
  tmux has-session 2>/dev/null || return 0    # no server → nothing to snapshot
  "$save" quiet >/dev/null 2>&1 || true
}

# Refuse to remove the worktree the caller is standing in, or whose tmux session
# is the current one. Both halves matter for different hosts: the cwd check covers
# herdr panes and bare terminals (where $TMUX is unset), the session check covers
# tmux.
#
# This lives in a shared helper because it did not start that way. wtr grew both
# guards; wthr had NEITHER, so from a herdr pane whose cwd was the worktree,
# `wthr --force` resolved the branch from the current shell, passed the
# default-branch guard, and handed the id straight to `herdr worktree remove
# --force` — deleting the checkout under the user's feet, discarding uncommitted
# changes with no confirmation, and leaving the shell in a deleted directory.
# cheatsheet.md meanwhile promised the two commands were symmetric.
_wt_refuse_self() {
  local dir="$1" session="$2" who="$3"
  local here; here="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [[ -n "$here" && "${here:A}" == "${dir:A}" ]]; then
    echo "$who: you are inside $dir — cd out first." >&2
    return 1
  fi
  if [[ -n "$TMUX" && "$(tmux display-message -p '#{session_name}' 2>/dev/null)" == "$session" ]]; then
    echo "$who: refusing — '$session' is the session you're in." >&2
    echo "     Run it from another session (e.g. your main worktree)." >&2
    return 1
  fi
  return 0
}

# Create (or switch to) a worktree for <branch> and jump into its tmux session.
# Directory convention (matches herdr): <parent>/<repo>/<branch-slug>
# Session name: <repo>/<branch-slug>  (= prefix gives tmux exact-match, slashes are safe)
wtc() {
  local branch="$1"
  if [[ -z "$branch" ]]; then
    echo "usage: wtc <branch-name>" >&2
    return 1
  fi
  local wt_main wt_repo wt_parent wt_sani wt_dir wt_session
  _wt_paths "$branch" \
    || { echo "wtc: not inside a git repository" >&2; return 1; }
  local dir="$wt_dir" session="$wt_session"
  # Ask git where the branch is checked out before deciding anything. Testing the
  # conventional path instead broke both ways: a worktree created by a raw
  # `git worktree add`, by herdr, or under the pre-2026-08 layout made wtc die with
  # "could not create worktree" on a worktree wtr resolves fine; and a leftover
  # plain directory at $dir (a worktree rm -rf'd without `git worktree prune`) made
  # the -d test true, so wtc skipped creation and opened a session in a directory
  # git has no worktree for.
  local existing; existing="$(_wt_dir_for_branch "$branch")"
  if [[ -n "$existing" ]]; then
    dir="$existing"
  elif [[ ! -d "$dir" ]]; then
    # Order matters. `git worktree add -b <branch> <dir>` ALWAYS succeeds by
    # branching from the current HEAD, so trying it first made the tracking form
    # below unreachable: `wtc someone-elses-branch` silently gave you a fresh empty
    # branch off your own HEAD, with no upstream, instead of their work — you then
    # committed on the wrong base and the first push rejected or clobbered. The
    # DWIM form goes first so an existing remote branch is tracked; -b is the
    # fallback for a genuinely new branch.
    git worktree add "$dir" "$branch" 2>/dev/null \
      || git worktree add -b "$branch" "$dir" \
      || { echo "wtc: could not create worktree at $dir" >&2; return 1; }
  fi
  _wt_sync_excludes
  tmux has-session -t "=$session" 2>/dev/null \
    || tmux new-session -d -s "$session" -c "$dir"
  if [[ -n "$TMUX" ]]; then
    tmux switch-client -t "=$session"
  else
    tmux attach -t "=$session"
  fi
}

# Remove a worktree and its tmux session. Deletes the branch if git considers it
# merged (fast-forward / merge commit); leaves it in place for squash/rebase-merged
# branches — run `gh poi` afterwards to bulk-remove those.
# Defaults to the current branch; refuses when run from inside the session it
# would kill — run it from another session (e.g. your main worktree).
# `--force` discards a dirty checkout, matching wthr.
wtr() {
  local -a flags=()
  while [[ "$1" == -* ]]; do flags+=("$1"); shift; done
  local branch="${1:-$(git branch --show-current 2>/dev/null)}"
  [[ $# -gt 0 ]] && shift
  flags+=("$@")
  if [[ -z "$branch" ]]; then
    echo "usage: wtr [branch-name] [--force]   (branch defaults to current)" >&2
    return 1
  fi
  _wt_refuse_default "$branch" wtr || return 1
  local wt_main wt_repo wt_parent wt_sani wt_dir wt_session
  _wt_paths "$branch" \
    || { echo "wtr: not inside a git repository" >&2; return 1; }
  local session="$wt_session"
  local dir; dir="$(_wt_dir_for_branch "$branch")"
  if [[ -z "$dir" ]]; then
    echo "wtr: no worktree is checked out on '$branch'." >&2
    return 1
  fi
  _wt_refuse_self "$dir" "$session" wtr || return 1
  git worktree remove "${flags[@]}" "$dir" || return 1
  _wt_sync_excludes
  _wt_drop_branch "$branch"
  tmux kill-session -t "=$session" 2>/dev/null
  # Overwrite the resurrect snapshot now that the session is gone, so a fresh
  # tmux server doesn't bring it back pointing at a deleted directory.
  _wt_resurrect_save
  echo "✓ removed worktree $dir (session '$session')"
  [[ -n "$TMUX" ]] && tmux refresh-client 2>/dev/null || true
  return 0
}

# --- herdr's ambient repo scoping (why the two helpers below exist) ---------
# herdr decides which repo a worktree action applies to from the *focused
# workspace's* cwd, not from the shell's cwd and not from --path — --path only
# selects among the focused repo's worktrees. So:
#   * `herdr worktree list` returns the focused repo's worktrees wherever you are,
#     which made a branch lookup silently return nothing (or, worse, match a
#     same-named branch in the wrong repo);
#   * `herdr worktree open|create` fail unless the focused workspace sits on the
#     target repo's *main* checkout — observed on 0.7.5:
#       focused on a linked worktree   → linked_worktree_source
#       focused outside any git repo   → not_git_worktree
#       focused on another repo's main → worktree_not_found
#   * `herdr worktree remove --workspace <id>` is exempt; it resolves from the id.
# So wth/wthr look workspaces up through `herdr workspace list`, which is global,
# and match on the worktree's checkout *path* rather than the branch name — two
# repos can share a branch name, a path is unique.

# Print the id of the open workspace whose worktree checkout is exactly $1.
_herdr_ws_at() {
  herdr workspace list 2>/dev/null \
    | jq -r --arg p "$1" '.result.workspaces[]
        | select(.worktree.checkout_path == $p) | .workspace_id' \
    | head -1
}

# Focus a workspace sitting on the main checkout $1 — the precondition for
# `herdr worktree open|create`. Creates one if none is open: a bare
# `workspace create` starts with no worktree metadata, but herdr upgrades it to a
# proper repo-parent workspace as soon as a worktree action runs from it, so the
# lookup above finds it next time and duplicates don't accumulate.
#
# Never close this workspace to "tidy up": the repo parent owns the space, and
# closing it cascades — every linked-worktree workspace under it is closed too.
_herdr_anchor() {
  local main="$1" id
  id="$(_herdr_ws_at "$main")"
  if [[ -n "$id" ]]; then
    herdr workspace focus "$id" >/dev/null
  else
    herdr workspace create --cwd "$main" --label "${main:t}" --focus >/dev/null
  fi
}

# Create (or switch to) a herdr workspace for <branch>. Three cases:
#   1. herdr workspace already open for the worktree path → focus it
#   2. git worktree exists at the sibling path (e.g. created by wtc) → open in herdr
#   3. neither → create the git worktree and open in herdr
# Path convention matches wtc; herdr's directory config is never consulted.
wth() {
  local branch="$1"
  if [[ -z "$branch" ]]; then
    echo "usage: wth <branch-name>" >&2
    return 1
  fi
  command -v jq &>/dev/null \
    || { echo "wth: jq is required (brew install jq)" >&2; return 1; }
  local wt_main wt_repo wt_parent wt_sani wt_dir wt_session
  _wt_paths "$branch" \
    || { echo "wth: not inside a git repository" >&2; return 1; }
  local main="$wt_main" dir="$wt_dir" label="$wt_session"

  local workspace_id
  workspace_id="$(_herdr_ws_at "$dir")"
  if [[ -z "$workspace_id" ]]; then
    local out
    _herdr_anchor "$main" \
      || { echo "wth: could not focus a herdr workspace on $main" >&2; return 1; }
    if [[ -d "$dir" ]]; then
      out=$(herdr worktree open --path "$dir" --label "$label" 2>&1)
    else
      out=$(herdr worktree create --branch "$branch" --path "$dir" --label "$label" 2>&1)
    fi
    workspace_id=$(print -r -- "$out" | jq -r '.result.workspace.workspace_id // empty' 2>/dev/null)
    if [[ -z "$workspace_id" ]]; then
      echo "wth: herdr could not open a workspace for '$branch'" >&2
      print -r -- "$out" >&2
      return 1
    fi
  fi
  _wt_sync_excludes
  herdr workspace focus "$workspace_id" >/dev/null
}

# Remove a herdr worktree by branch name. Resolves the workspace from the
# worktree's checkout path (see the scoping note above — a branch lookup via
# `herdr worktree list` finds nothing unless that repo happens to be focused),
# then:
#   1. herdr worktree remove  — runs git worktree remove + closes herdr workspace
#      (pass --force if the checkout is dirty and you want to discard changes)
#   2. git branch -d          — branch deletion is separate; herdr never touches it
wthr() {
  # Split leading flags from the branch argument, so both `wthr --force` and
  # `wthr <branch> --force` work. Previously a leading --force was consumed as
  # the branch name and the lookup always failed.
  local -a flags=()
  while [[ "$1" == -* ]]; do flags+=("$1"); shift; done
  local branch="${1:-$(git branch --show-current 2>/dev/null)}"
  [[ $# -gt 0 ]] && shift
  flags+=("$@")
  if [[ -z "$branch" ]]; then
    echo "usage: wthr [branch-name] [--force]   (branch defaults to current)" >&2
    return 1
  fi
  _wt_refuse_default "$branch" wthr || return 1
  command -v jq &>/dev/null \
    || { echo "wthr: jq is required (brew install jq)" >&2; return 1; }
  local wt_main wt_repo wt_parent wt_sani wt_dir wt_session
  _wt_paths "$branch" \
    || { echo "wthr: not inside a git repository" >&2; return 1; }
  # Prefer the path git actually has on record; fall back to the convention so a
  # workspace whose checkout was already removed can still be matched and closed.
  local dir; dir="$(_wt_dir_for_branch "$branch")"
  [[ -n "$dir" ]] || dir="$wt_dir"
  local workspace_id
  workspace_id="$(_herdr_ws_at "$dir")"
  if [[ -z "$workspace_id" ]]; then
    echo "wthr: no open herdr workspace found for '$wt_session' ($dir)" >&2
    return 1
  fi
  _wt_refuse_self "$dir" "$wt_session" wthr || return 1
  herdr worktree remove --workspace "$workspace_id" "${flags[@]}" || return 1
  _wt_sync_excludes
  _wt_drop_branch "$branch"
  return 0
}

# Rebase the current branch onto the latest default branch (main/master).
# Fetches first, so you rebase onto a fresh origin/<default>; auto-stashes
# uncommitted changes for the duration. After a successful rebase it also
# fast-forwards the main worktree's checkout — but only when that worktree is on
# <default> with a clean tree (it never rewrites and never touches a dirty or
# other-branch worktree).
wtrebase() {
  local def; def="$(_wt_default_branch)"
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
  local wt_main wt_repo wt_parent wt_sani wt_dir wt_session
  _wt_paths "$cur" || return 0
  local main_wt="$wt_main"
  local main_branch; main_branch="$(git -C "$main_wt" branch --show-current 2>/dev/null)"
  if [[ "$main_branch" != "$def" ]]; then
    echo "Note: main worktree is on '$main_branch', not '$def' — left it untouched."
  # --untracked-files=no matters: worktrees are nested *inside* the main checkout
  # (<parent>/<repo>/<slug>), so the main worktree permanently reports them as
  # untracked. Counting those as "local changes" made this branch always taken,
  # and the fast-forward below therefore never ran.
  elif [[ -n "$(git -C "$main_wt" status --porcelain --untracked-files=no)" ]]; then
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
# An `if` rather than `[ -f … ] && source …`: this is the LAST line of the file,
# so its status becomes .zshrc's, and the && form leaves a non-zero one behind on
# every machine without the (untracked, usually absent) local file. That made
# `zsh -i -c exit` return 1 — breaking any caller that checks whether shell
# startup succeeded, check.sh's C8 gate among them. The if form returns 0 when
# the file simply isn't there, while still propagating a real failure inside it.
if [ -f "$HOME/.zshrc.local" ]; then
  source "$HOME/.zshrc.local"
fi
