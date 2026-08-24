#!/usr/bin/env bash
# check.sh — the pass/fail gate for this repo's health criteria.
#
# Why this exists: "review the dotfiles for anything that could be better" has no
# passing state, so every review of that shape returns a non-empty list whether
# or not anything is actually wrong. This script is the half of that question
# that CAN pass. Everything here is binary and mechanical: it either exits 0 or
# it names a specific broken thing. Judgement calls — dead config, deprecated
# keys, whether a design could be simpler — these are not scriptable and belong
# in a review session, not in an automated gate.
#
# Deliberately NOT duplicated here:
#   * link/deploy health per stow class → the `dotfiles-doctor` skill owns that
#     model (folded vs unfolded vs hand-wired) and it is too nuanced for a gate.
#   * binary + config-reachability checks → install.common.sh's verify_install
#     already does them; this script sources and calls it rather than restating
#     it, so the two can never drift apart.
#
# Every list is DERIVED from the repo at run time. A list hardcoded here goes
# stale silently and then reports healthy things as broken, which is worse than
# not checking at all.
#
# Usage:
#   ./check.sh              all checks
#   ./check.sh --offline    skip the checks that need the network
#   ./check.sh --quick      skip network + the slow editor/startup probes
#   ./check.sh -v           show output from probes that passed
#
# Exit status: 0 = every check passed (warnings allowed), 1 = at least one FAIL.

set -uo pipefail

# Normally the repo is this script's own directory, so the gate works from a
# clone anywhere. Overridable so it can be run against a repo it does not sit in.
: "${DOTFILES:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
export DOTFILES

OFFLINE=0
QUICK=0
VERBOSE=0
for arg in "$@"; do
  case "$arg" in
    --offline) OFFLINE=1 ;;
    --quick)   QUICK=1; OFFLINE=1 ;;
    -v|--verbose) VERBOSE=1 ;;
    -h|--help) sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "check.sh: unknown option '$arg' (try --help)" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

if [ -t 1 ]; then
  C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_FAIL=$'\033[31m'
  C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'; C_OFF=$'\033[0m'
else
  C_OK=''; C_WARN=''; C_FAIL=''; C_DIM=''; C_BOLD=''; C_OFF=''
fi

FAILS=0
WARNS=0
SKIPS=0
# Failure messages are also collected, so the closing summary can restate them.
# The output of this script is routinely read through `| tail`, and a run whose
# ✗ line scrolled out of view is a failure you cannot act on — that happened,
# and cost the diagnosis of a one-in-ten flake that has not recurred since.
FAILED_CHECKS=()

criterion() { printf '\n%s%s%s\n' "$C_BOLD" "$1" "$C_OFF"; }
ok()   { printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$1"; }
warn() { printf '  %s!%s %s\n' "$C_WARN" "$C_OFF" "$1"; WARNS=$((WARNS + 1)); }
fail() { printf '  %s✗%s %s\n' "$C_FAIL" "$C_OFF" "$1"; FAILS=$((FAILS + 1)); FAILED_CHECKS+=("$1"); }
skip() { printf '  %s- %s (skipped: %s)%s\n' "$C_DIM" "$1" "$2" "$C_OFF"; SKIPS=$((SKIPS + 1)); }
detail() { [ "$VERBOSE" -eq 1 ] && printf '    %s%s%s\n' "$C_DIM" "$1" "$C_OFF"; return 0; }

# Run a command in a pseudo-terminal. TUI apps gate real work on UIEnter, so a
# headless run reports plugins as unloaded on a perfectly healthy config — the
# probe has to look like a terminal or it answers a different question than the
# one asked. The two `script` invocations are not compatible between platforms.
# stdin is redirected from /dev/null, and that is the whole ballgame on macOS:
# script(1) calls tcgetattr on its OWN stdin before it runs anything, so when it
# inherits something that isn't a terminal-like fd — a socket, as happens under an
# agent harness, cron, or some CI runners — it dies with
#   script: tcgetattr/ioctl: Operation not supported on socket
# and exits 1 having never started the command. The probe then looked like the
# thing it was probing had failed: C2 reported "zsh -i exited 1" on a healthy
# shell, and the nvim probe silently produced no output. Both presented as
# intermittent, because whether stdin happened to be a socket varied per
# invocation — /dev/null and pipes both work fine, which is why most runs passed.
# Pinning stdin makes the probes independent of however they were invoked.
in_pty() {
  if [ "$(uname -s)" = "Darwin" ]; then
    # -e: propagate the child's exit status (supported on macOS script since
    # Monterey; without it $? is always 0 — hung-process checks never fire).
    script -qe /dev/null "$@" </dev/null 2>&1
  else
    script -qec "$*" /dev/null </dev/null 2>&1
  fi
}

# A gate that can hang is a gate nobody runs, but bounding a pty probe took two
# tries to get right and both failures are worth keeping written down.
#
# First: do NOT background `script` and poll it. Backgrounding puts it in a
# background process group, where touching the tty raises SIGTTIN and STOPS the
# process — it never exits, so a poll-and-kill watchdog reports a hang on a config
# that is perfectly healthy. (Observed: nvim "did not exit within 60s"
# backgrounded, exit 0 in the foreground.) The pty command always runs in the
# FOREGROUND.
#
# Second: the timeout goes INSIDE the pty, not around it. A `guarded()` wrapper
# that ran `timeout <secs> in_pty …` could never work — timeout(1) is an external
# binary and execve's its argument, so a shell function is unresolvable and it
# died with 127. That is not 124, so callers checking only for the timeout status
# fell through to their success branch and passed a probe that never started. Each
# probe therefore builds its own argv with the timeout as the innermost command;
# `script` runs it through sh, which resolves a real binary fine.
#
# macOS ships no timeout; coreutils provides gtimeout. Without either, the probes
# still self-terminate — the nvim probe quits itself, `zsh -i -c exit` exits on its
# own — so the only thing lost is protection against a config that blocks on input.
TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"

# ---------------------------------------------------------------------------
# Derived inventories — computed, never written down
# ---------------------------------------------------------------------------

cd "$DOTFILES" || { echo "check.sh: cannot cd to $DOTFILES" >&2; exit 2; }

# The formulae install.sh installs, read out of its `_formulae=( … )` array.
# sed per line, NOT `tr -d '[:space:]'` — tr has no concept of lines and eats the
# newlines too, collapsing 24 formulae into one 200-character token that then
# "resolves to no binary". One word-list, one line each.
BREW_PKGS="$(awk '/^_formulae=\(/{f=1;next} f&&/^\)/{exit} f{print}' install.sh \
  | sed -e 's/#.*//' -e 's/[[:space:]\\]//g' | grep -v '^$' || true)"

STOW_TARGET="$(sed -n 's/^--target=//p' .stowrc | sed "s|^~|$HOME|" || true)"

# What stow actually deploys, asked of stow itself: a dry run into a PRISTINE
# empty target prints one LINK line per entry it would create.
#
# This is derived this way on purpose. The first version compared each top-level
# entry against `.stowrc`'s --ignore patterns, which silently assumed .stowrc was
# the whole ignore list. It is not: stow carries a BUILT-IN list (.git, README.*,
# LICENSE.*, *~ and friends) that --ignore only adds to. So the moment three
# redundant --ignore lines were correctly deleted from .stowrc, this check started
# reporting README.md as an undeployed package. Asking stow cannot drift from
# stow.
stow_deploys() {
  local probe rc
  probe="$(mktemp -d)" || return 1
  stow -n -v -d "$DOTFILES" -t "$probe" . 2>&1 \
    | sed -n 's/^LINK: \([^ ]*\) =>.*/\1/p'
  rc=$?
  rmdir "$probe" 2>/dev/null || rm -rf "$probe"
  return $rc
}

# A derivation that silently returns nothing is worse than no check: it reports
# a clean pass over an empty set. Both lists above are computed from files this
# repo edits, so both can break exactly that way — and one did, when install.sh's
# `brew install \` block became an array and the old awk pattern matched nothing,
# yielding a cheerful "all 0 derived formulae resolve". Assert non-empty.
derived_or_fail() {
  local name="$1" value="$2"
  if [ -z "$value" ]; then
    fail "derivation for $name returned nothing — check.sh is out of date with the repo"
    return 1
  fi
  return 0
}

# Things this repo has deliberately removed. Any reappearance is a regression,
# not a new opinion — every entry here was deleted on purpose and the commit
# message says why. Keep the list short and only add things whose removal was
# intentional and final.
# Note: `diffview` was removed (c582fa7) and added to this list, but
# `diffview-plus.nvim` (dlyongemallo/diffview-plus.nvim) was subsequently
# added intentionally (f0d5ab5) as a maintained fork. The token `diffview`
# matched both and caused a false positive on the cheatsheet and lazy-lock.json.
# Removed from REMOVED_TOKENS — a diffview variant is back by design.
REMOVED_TOKENS="pyenv wtclean migrate.sh"

# Files that must never be tracked: machine-local, secret, or runtime state.
# The repo promises these are gitignored; this asserts the promise.
MUST_NOT_TRACK="install.local.sh sesh.local.toml .DS_Store
tmux/plugins/tpm herdr/session.json"

printf '%s%s%s\n' "$C_BOLD" "check.sh — $DOTFILES @ $(git rev-parse --short HEAD 2>/dev/null || echo '?')" "$C_OFF"
[ "$OFFLINE" -eq 1 ] && printf '%s(offline mode)%s\n' "$C_DIM" "$C_OFF"

# ---------------------------------------------------------------------------
# C2 — Startup health is silent
# ---------------------------------------------------------------------------
# An interactive shell, an editor and a multiplexer that all load without a
# single word on stderr. This is the check that catches the most regressions per
# line, because almost every config mistake announces itself here first.

criterion "C2 — startup health"

if command -v zsh >/dev/null 2>&1; then
  # Under a pty, and this is not optional. `zsh -i -c exit` with no tty emits
  # `(eval):1: can't change option: zle` from fzf's shell integration — an
  # artefact of the probe, not a fault in the config, and a gate that fails on
  # it would be trained-to-ignore within a week. `script` merges stderr into the
  # pty stream, so this matches error patterns rather than asserting stderr is
  # empty; anything else unexpected is surfaced as a warning, not a failure.
  # The timeout goes INSIDE the pty, not around it. `guarded 30 in_pty …` could
  # never work: guarded execs timeout(1), an external binary, and in_pty is a
  # shell function it cannot resolve — so timeout died with "failed to run
  # command 'in_pty'" and C2 reported "zsh -i exited 127" no matter what .zshrc
  # did, masking the real startup status. script(1) runs its command through sh,
  # which resolves timeout fine.
  pty_cmd=(zsh -i -c exit)
  [ -n "$TIMEOUT_BIN" ] && pty_cmd=("$TIMEOUT_BIN" -k 5 30 "${pty_cmd[@]}")
  zsh_out="$(in_pty "${pty_cmd[@]}")"
  zsh_rc=$?
  # Strip CRs, ANSI escapes, and the `^D` that script(1) echoes when the shell
  # reads EOF — all three are the harness talking, not the config.
  zsh_clean="$(printf '%s' "$zsh_out" | tr -d '\r\004' \
    | sed $'s/\033\[[0-9;?]*[a-zA-Z]//g' | sed 's/\^D//g' \
    | grep -v '^[[:space:]]*$' || true)"
  zsh_errs="$(printf '%s\n' "$zsh_clean" \
    | grep -iE 'not found|no such file|parse error|bad pattern|permission denied|insecure director|error:|failed|cannot' || true)"
  if [ "$zsh_rc" -eq 124 ]; then
    fail "zsh -i hung (killed after 30s)"
  elif [ "$zsh_rc" -ne 0 ]; then
    fail "zsh -i exited $zsh_rc"
    printf '%s\n' "$zsh_clean" | head -10 | sed 's/^/      /'
  elif [ -n "$zsh_errs" ]; then
    fail "zsh interactive startup reported errors"
    printf '%s\n' "$zsh_errs" | head -10 | sed 's/^/      /'
  elif [ -n "$(printf '%s' "$zsh_clean" | tr -d '[:cntrl:][:space:]')" ]; then
    # Decide on printable content only. A pty session leaves stray control bytes
    # that survive the escape-stripping above, and warning about those is
    # warning about the harness.
    warn "zsh interactive startup was not silent (no error pattern matched)"
    printf '%s\n' "$zsh_clean" | head -10 | sed 's/^/      /'
  else
    ok "zsh -i starts clean and silent (under a pty)"
  fi

  # Startup cost is a warning, never a failure — it is a preference with a number
  # attached, not a defect. Measured without the pty wrapper, since `script`'s own
  # overhead would be counted as the shell's. `date +%s` is whole seconds
  # everywhere (macOS date has no %N), so this averages 10 runs: resolution is
  # ~100ms, which is enough to catch a 3x regression and not enough to police 40ms.
  if [ "$QUICK" -eq 0 ]; then
    t_start=$(date +%s)
    for _ in 1 2 3 4 5 6 7 8 9 10; do zsh -i -c exit >/dev/null 2>&1; done
    t_end=$(date +%s)
    ms=$(( (t_end - t_start) * 100 ))
    if [ "$ms" -gt 800 ]; then
      warn "zsh startup ~${ms}ms averaged over 10 runs (over the 800ms threshold)"
    else
      ok "zsh startup ~${ms}ms averaged over 10 runs"
    fi
  else
    skip "zsh startup timing" "--quick"
  fi
else
  fail "zsh not installed"
fi

if command -v nvim >/dev/null 2>&1; then
  # Headless first, always. It cannot see plugin errors gated on UIEnter, but it
  # exits reliably and catches the common regression: a Lua error or a bad plugin
  # spec on the eager path.
  nv_out="$(nvim --headless "+qa" 2>&1)"
  nv_hrc=$?
  if [ "$nv_hrc" -ne 0 ]; then
    fail "nvim --headless +qa exited $nv_hrc"
    printf '%s\n' "$nv_out" | head -20 | sed 's/^/      /'
  elif [ -n "$nv_out" ]; then
    fail "nvim --headless +qa wrote output"
    printf '%s\n' "$nv_out" | head -20 | sed 's/^/      /'
  else
    ok "nvim --headless +qa is silent (eager path clean)"
  fi

  # The pty probe is the only way to see UIEnter/VeryLazy-gated plugin errors,
  # but it is opt-in and needs a timeout binary, for a reason worth writing down:
  # with its output redirected it blocks indefinitely (nvim waiting on a modal
  # prompt the deferred timer never gets to service), and killing the `script`
  # parent orphans the nvim child. A gate that leaves stray editors behind is
  # not a gate. So: run it only when it can be bounded, and say so when skipped
  # rather than letting the silence read as coverage.
  if [ "$QUICK" -eq 1 ]; then
    skip "nvim plugin-load probe" "--quick"
  elif [ "${CHECK_NVIM_PTY:-0}" != "1" ]; then
    skip "nvim plugin-load probe (UIEnter-gated errors)" "set CHECK_NVIM_PTY=1 to enable"
  elif [ -z "$TIMEOUT_BIN" ]; then
    skip "nvim plugin-load probe" "needs timeout(1) or gtimeout — brew install coreutils"
  else
    # Under a pty so UIEnter/VeryLazy fire and lazy-loaded plugins actually
    # load. Errors are collected from :messages rather than stdout, because a
    # real terminal fills stdout with escape sequences.
    # The sentinel first line is load-bearing: `:messages` is legitimately EMPTY on
    # a healthy config, so an empty file cannot distinguish "nothing to report" from
    # "the probe never ran". With the marker, presence proves the probe completed
    # and its absence is a real failure.
    probe="$(mktemp)"; out="$(mktemp)"
    cat >"$probe" <<'LUA'
vim.defer_fn(function()
  local msgs = vim.api.nvim_exec2("messages", { output = true }).output or ""
  local f = io.open(vim.env.NVIM_PROBE_OUT, "w")
  f:write("PROBE-COMPLETED\n" .. msgs)
  f:close()
  vim.cmd("qa!")
end, 3000)
LUA
    # Plain `nvim`, deliberately: not --clean, not -u. The question is whether
    # the config the user actually gets loads cleanly, so the probe has to load
    # it the same way they do.
    export NVIM_PROBE_OUT="$out"
    # Timeout INSIDE the pty, for the same reason as C2's zsh probe: timeout(1) is
    # an external binary and cannot execve a shell function, so wrapping `in_pty`
    # in it died with 127 rather than running anything. This path is opt-in, so it
    # outlived the C2 fix — and 127 is not 124, so it fell through to the success
    # branch below and grepped an empty file: a clean "nvim loads without errors"
    # for a probe that never started. An unexpected status is now a failure, not a
    # pass.
    nv_cmd=(nvim -S "$probe")
    [ -n "$TIMEOUT_BIN" ] && nv_cmd=("$TIMEOUT_BIN" -k 5 60 "${nv_cmd[@]}")
    in_pty "${nv_cmd[@]}" >/dev/null 2>&1
    nv_rc=$?
    unset NVIM_PROBE_OUT
    if [ "$nv_rc" -eq 124 ]; then
      fail "nvim did not exit within 60s (config may be prompting or hung)"
    elif ! grep -q '^PROBE-COMPLETED$' "$out" 2>/dev/null; then
      fail "nvim probe never completed (exit $nv_rc) — it did not reach its own exit path"
    else
      # E1568 is the pty answering no DSR query for the background colour — an
      # artefact of script(1), raised on a healthy config, so it is exempt. Any
      # other E-code is real.
      msgs="$(grep -iE '^(E[0-9]+:|.*\berror\b|.*stack traceback)' "$out" 2>/dev/null \
        | grep -v 'E1568' || true)"
      if [ -n "$msgs" ]; then
        fail "nvim reported errors on load"
        printf '%s\n' "$msgs" | head -20 | sed 's/^/      /'
      else
        ok "nvim loads without errors (pty, plugins loaded)"
        detail "$(wc -l <"$out" | tr -d ' ') lines of :messages, none matching an error pattern"
      fi
    fi
    rm -f "$probe" "$out"
    # Belt and braces: if the timeout killed `script`, the nvim child can survive
    # it. Reap anything still holding this run's probe file.
    pkill -9 -f "nvim -S $probe" 2>/dev/null || true
  fi
else
  fail "nvim not installed"
fi

if command -v tmux >/dev/null 2>&1; then
  # A throwaway socket (-L) so this cannot touch live sessions. Never use
  # source-file against the default socket here.
  tmux_out="$(tmux -f "$DOTFILES/tmux/tmux.conf" -L dotfiles_check \
    start-server \; kill-server 2>&1)" || true
  if [ -n "$tmux_out" ]; then
    fail "tmux.conf produced messages on load"
    printf '%s\n' "$tmux_out" | head -20 | sed 's/^/      /'
  else
    ok "tmux.conf parses clean ($(tmux -V))"
  fi
else
  fail "tmux not installed"
fi

# ---------------------------------------------------------------------------
# C3 — Stow closure
# ---------------------------------------------------------------------------
# Dry runs of the exact commands install.common.sh issues. Anything stow
# objects to now is something the installer would have to back up and retry,
# which means the running machine and a fresh install disagree.

criterion "C3 — stow closure"

if command -v stow >/dev/null 2>&1; then
  mkdir -p "$STOW_TARGET" 2>/dev/null || true
  mkdir -p "$HOME/.local/bin" 2>/dev/null || true
  for spec in "$STOW_TARGET|." "$HOME|zsh" "$HOME/.local/bin|bin"; do
    tgt="${spec%%|*}"; pkg="${spec##*|}"
    out="$(stow --no --restow --target="$tgt" "$pkg" 2>&1)" || true
    conflicts="$(printf '%s\n' "$out" | grep -E 'existing target|cannot stow' || true)"
    if [ -n "$conflicts" ]; then
      fail "stow conflicts for package '$pkg' → $tgt"
      printf '%s\n' "$conflicts" | head -10 | sed 's/^/      /'
    else
      ok "stow --restow '$pkg' → $tgt predicts no conflicts"
    fi
  done

  # An entry that is neither stowignored nor present in the target is config the
  # user believes is deployed and is not.
  deployed="$(stow_deploys)"
  if derived_or_fail "stow deploy set" "$deployed"; then
    undeployed=""
    for entry in $deployed; do
      [ -e "$STOW_TARGET/$entry" ] || undeployed="$undeployed $entry"
    done
    if [ -n "$undeployed" ]; then
      fail "entries stow would deploy but that are absent at $STOW_TARGET:$undeployed"
    else
      ok "all $(printf '%s\n' "$deployed" | grep -c .) entries stow deploys are present at $STOW_TARGET"
    fi
  fi
else
  fail "stow not installed"
fi

# ---------------------------------------------------------------------------
# C4 — Reference closure
# ---------------------------------------------------------------------------
# verify_install owns the "is every tool here, is every config linked" half.
# Sourcing it means this gate cannot drift from the installer's own definition
# of a good machine. Only verify_install is called — run_shared_tail mutates.

criterion "C4 — reference closure"

if [ -f "$DOTFILES/install.common.sh" ]; then
  # shellcheck source=install.common.sh
  if source "$DOTFILES/install.common.sh" 2>/dev/null; then
    if verify_out="$(verify_install 2>&1)"; then
      ok "install.common.sh verify_install passes"
      detail "$(printf '%s' "$verify_out" | grep -c '✓' || true) affirmative lines"
    else
      fail "install.common.sh verify_install reports problems"
      printf '%s\n' "$verify_out" | grep -E '✗|!' | sed 's/^/      /'
    fi
  else
    fail "could not source install.common.sh"
  fi

  # verify_install checks a hardcoded subset of the formulae install.sh
  # installs. Deriving the full list catches the drift case: a formula added to
  # install.sh but never added to the verify list, so a machine missing it
  # still reports a clean install.
  if [ "$(uname -s)" != "Darwin" ]; then
    skip "BREW_PKGS check (install.sh is macOS-only — formula names differ on Linux)"
  elif derived_or_fail "install.sh formula list" "$BREW_PKGS"; then
    missing=""
    for pkg in $BREW_PKGS; do
      # Prefer install.common.sh's own have_tool when it exists: it knows about
      # tools that ship under either of two binary names (sevenzip → 7zz or 7z).
      if command -v have_tool >/dev/null 2>&1 || type have_tool >/dev/null 2>&1; then
        have_tool "$pkg" >/dev/null 2>&1 || missing="$missing $pkg"
      else
        b="$(bin_name "$pkg" 2>/dev/null || echo "$pkg")"
        command -v "$b" >/dev/null 2>&1 || missing="$missing $pkg"
      fi
    done
    if [ -n "$missing" ]; then
      warn "installed by install.sh but not on PATH:$missing"
    else
      ok "all $(printf '%s\n' "$BREW_PKGS" | grep -c . ) derived formulae resolve to a binary"
    fi
  fi
else
  fail "install.common.sh missing"
fi

# On macOS only: verify the karabiner config symlink. It is not stowed — stow
# cannot own a directory Karabiner writes runtime state into — so install.sh
# links ~/.config/karabiner by hand and neither stow_deploys nor verify_install
# covers it. Guarded on Darwin so Linux C4 runs are unaffected (Linux machines
# never have this path).
#
# Assert on the DIRECTORY, not karabiner.json. Karabiner saves via rename(2),
# which replaces a file-level symlink with a regular file; the old check tested
# the one thing Karabiner was guaranteed to destroy, and it passed at install
# time right before the first UI write orphaned the repo copy. -L on the
# directory is the durable invariant — a rename inside it cannot clear this.
if [ "$(uname -s)" = "Darwin" ]; then
  if [ -L "$HOME/.config/karabiner" ]; then
    _kara_real="$(readlink -f "$HOME/.config/karabiner" 2>/dev/null)"
    case "$_kara_real" in
      "$DOTFILES"/*) ok "$HOME/.config/karabiner → repo" ;;
      *) fail "$HOME/.config/karabiner resolves outside the repo ($_kara_real)" ;;
    esac
    # The link can be right while the file it should expose is missing.
    [ -f "$HOME/.config/karabiner/karabiner.json" ] \
      || fail "$HOME/.config/karabiner/karabiner.json missing"
  elif [ -d "$HOME/.config/karabiner" ]; then
    fail "$HOME/.config/karabiner is a real directory, not a symlink — Karabiner edits are not reaching the repo (run ./install.sh)"
  else
    fail "$HOME/.config/karabiner missing (run ./install.sh)"
  fi
fi

# On macOS only: verify the Rectangle config actually landed in Rectangle's
# preference domain. This had no coverage at all, which is how a dead import
# survived: install.sh was calling a rectangle:// URL that Rectangle's scheme
# handler does not implement, `open` exited 0 anyway, and nothing downstream ever
# looked at the result. Same failure shape as the font cask that "installed"
# without producing a binary — a no-op that reports success needs an assertion on
# the effect, not on the command.
#
# Rectangle is imported by copy, not symlinked (it refuses symlinked configs), so
# unlike karabiner there is no link to assert on and edits made in Rectangle's UI
# do NOT flow back to the repo. The durable invariant is the domain itself.
if [ "$(uname -s)" = "Darwin" ]; then
  _rect_cfg="$DOTFILES/macos/rectangle/RectangleConfig.json"
  _rect_pending="$HOME/Library/Application Support/Rectangle/RectangleConfig.json"
  if [ ! -f "$_rect_cfg" ]; then
    fail "$_rect_cfg missing"
  elif [ -f "$_rect_pending" ]; then
    # Rectangle renames this file away the moment it applies it, so one still
    # sitting here means the import is queued but unconfirmed — Rectangle has not
    # been launched since install.sh staged it, or the prompt is still waiting.
    fail "Rectangle config staged but never applied — launch Rectangle and confirm the import prompt"
  else
    # leftHalf is written to the domain only by an import (or a manual UI edit);
    # Rectangle's own built-in shortcuts are registered in-memory and never
    # persisted, so its presence is a clean signal that the import ran. Compare
    # against the repo rather than a hardcoded number so retuning the config in
    # git cannot silently rot this check.
    _rect_want="$(plutil -extract shortcuts.leftHalf.modifierFlags raw -o - "$_rect_cfg" 2>/dev/null || true)"
    _rect_have="$(defaults export com.knollsoft.Rectangle - 2>/dev/null \
      | plutil -extract leftHalf.modifierFlags raw -o - - 2>/dev/null || true)"
    if [ -z "$_rect_have" ]; then
      fail "Rectangle config not applied — com.knollsoft.Rectangle has no leftHalf shortcut (run ./install.sh)"
    elif [ "$_rect_have" != "$_rect_want" ]; then
      fail "Rectangle leftHalf modifiers drifted: repo says $_rect_want, live domain says $_rect_have (re-export to the repo, or run ./install.sh)"
    else
      ok "Rectangle config applied to com.knollsoft.Rectangle"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# C5 — Doc closure
# ---------------------------------------------------------------------------
# Mechanical half only: every worktree helper the docs name must exist. The full
# both-directions doc audit is judgement work for a review session.

criterion "C5 — doc closure (mechanical subset)"

doc_missing=""
for fn in $(grep -ohE '\bwt[a-z]{1,10}\b' README.md cheatsheet.md 2>/dev/null | sort -u); do
  if ! grep -qE "^[[:space:]]*(function[[:space:]]+)?${fn}[[:space:]]*\(\)|^[[:space:]]*alias[[:space:]]+${fn}=" zsh/.zshrc; then
    doc_missing="$doc_missing $fn"
  fi
done
if [ -n "$doc_missing" ]; then
  fail "documented but not defined in zsh/.zshrc:$doc_missing"
else
  ok "every wt* helper named in the docs is defined"
fi

# Prefix attribution. tmux and herdr both run here and own DIFFERENT prefixes —
# tmux keeps stock C-b precisely so herdr can have C-a. That makes every
# "<prefix> <key>" string in a doc or comment a factual claim about which of the
# two multiplexers handles it, and those claims drift silently: a key bound in
# tmux.conf but written with herdr's prefix sends the user to the wrong program
# with no error. Two independent audits found exactly this, in two different
# files, so it is a recurrence worth gating rather than a one-off typo.
herdr_prefix="$(sed -n 's/^[[:space:]]*prefix[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
  herdr/config.toml 2>/dev/null | head -1)"
if [ -n "$herdr_prefix" ] && [ -f tmux/tmux.conf ]; then
  # "ctrl+a" → the human spellings a doc or comment would plausibly use.
  hp_short="C-${herdr_prefix#ctrl+}"
  hp_long="Ctrl+${herdr_prefix#ctrl+}"

  # Keys herdr itself binds, normalised to the way a doc would write them
  # (`prefix+shift+j` → `J`). Both multiplexers bind j/k/J/K for pane and
  # workspace movement, so those keys carry no information about which program
  # handles them and must be excluded or the check fires on correct docs.
  herdr_keys=""
  while IFS= read -r v; do
    v="${v#prefix+}"
    case "$v" in
      shift+?) herdr_keys="$herdr_keys $(printf '%s' "${v#shift+}" | tr '[:lower:]' '[:upper:]')" ;;
      ?)       herdr_keys="$herdr_keys $v" ;;
    esac
  done <<<"$(grep -oE '"[^"]*"' herdr/config.toml 2>/dev/null | tr -d '"')"

  misattributed=""
  for key in $(grep -oE '^[[:space:]]*bind(-key)?[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*"?([A-Za-z|_-])"?' \
      tmux/tmux.conf 2>/dev/null | awk '{print $NF}' | tr -d '"' | sort -u); do
    case " $herdr_keys " in *" $key "*) continue ;; esac
    hits="$(git grep -n -F -- "$hp_long $key" -- ':!check.sh' 2>/dev/null || true)"
    hits="$hits$(git grep -n -F -- "$hp_short $key" -- ':!check.sh' 2>/dev/null || true)"
    [ -n "$hits" ] && misattributed="$misattributed
$key: $hits"
  done
  if [ -n "$misattributed" ]; then
    fail "tmux-bound keys described with herdr's prefix ($hp_long):"
    printf '%s\n' "$misattributed" | grep -v '^$' | head -10 | sed 's/^/      /'
  else
    ok "no tmux-bound key is described with herdr's prefix ($hp_long)"
  fi
else
  skip "prefix attribution" "could not derive herdr's prefix"
fi

# ---------------------------------------------------------------------------
# C6 — No resurrected config
# ---------------------------------------------------------------------------
# The cheap, scriptable slice of "no dead config": things removed on purpose
# must not come back. This file and the review log name the tokens, so both are
# excluded or the check reports itself.

criterion "C6 — no resurrected config"

for token in $REMOVED_TOKENS; do
  # Comment lines are exempt. A comment naming the removed thing is usually the
  # record of WHY it went ("native diff — the diffview replacement"), which is
  # worth keeping; the regression this catches is the token reappearing in live
  # config. Filtering on the comment marker keeps the check from arguing with
  # the repo's own history.
  hits="$(git grep -n -i -- "$token" -- \
    ':!check.sh' 2>/dev/null \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(--|#|//)' || true)"
  if [ -n "$hits" ]; then
    fail "'$token' was removed deliberately but still appears:"
    printf '%s\n' "$hits" | head -5 | sed 's/^/      /'
  else
    ok "no references to '$token'"
  fi
done

# ---------------------------------------------------------------------------
# C8 — Script syntax and lint
# ---------------------------------------------------------------------------

criterion "C8 — script syntax and lint"

# check.sh is excluded from the bash -n loop: a running script can't usefully
# check its own syntax — if we got here, bash already parsed it successfully.
for f in install.sh install.common.sh install.linux.sh; do
  [ -f "$f" ] || continue
  if bash -n "$f" 2>/dev/null; then
    ok "bash -n $f"
  else
    fail "bash -n $f"
    bash -n "$f" 2>&1 | sed 's/^/      /'
  fi
done
if [ -f zsh/.zshrc ] && command -v zsh >/dev/null 2>&1; then
  zsh -n zsh/.zshrc 2>/dev/null && ok "zsh -n zsh/.zshrc" || fail "zsh -n zsh/.zshrc"
fi

if command -v shellcheck >/dev/null 2>&1; then
  # Only files that exist — naming a missing file makes shellcheck emit an error
  # about the file itself, which then reads as "the repo has lint findings".
  sc_files=""
  for f in install.sh install.common.sh install.linux.sh check.sh; do
    [ -f "$f" ] && sc_files="$sc_files $f"
  done
  # shellcheck disable=SC2086  # deliberate word splitting of the file list
  sc_out="$(shellcheck -x -S warning $sc_files 2>&1)" || true
  if [ -n "$sc_out" ]; then
    warn "shellcheck (severity ≥ warning): $(printf '%s\n' "$sc_out" | grep -c '^In ' || true) location(s) — run with -v to see them"
    [ "$VERBOSE" -eq 1 ] && printf '%s\n' "$sc_out" | sed 's/^/      /'
  else
    ok "shellcheck clean at severity ≥ warning ($(printf '%s' "$sc_files" | wc -w | tr -d ' ') files)"
  fi
else
  skip "shellcheck" "not installed"
fi

# ---------------------------------------------------------------------------
# C9 — No secrets, no tracked machine state
# ---------------------------------------------------------------------------

criterion "C9 — secrets and machine-local state"

tracked_bad=""
for p in $MUST_NOT_TRACK; do
  git ls-files --error-unmatch "$p" >/dev/null 2>&1 && tracked_bad="$tracked_bad $p"
done
if [ -n "$tracked_bad" ]; then
  fail "machine-local/runtime paths are tracked:$tracked_bad"
else
  ok "no machine-local or runtime paths tracked"
fi

# Content scan across tracked files only — anything untracked is not a repo
# problem. Patterns kept narrow: broad ones fire on the word "token" in a
# comment and train you to ignore the check.
secret_hits="$(git grep -nIE \
  '(gh[pousr]_[A-Za-z0-9]{16,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|xox[baprs]-[A-Za-z0-9-]{10,})' \
  -- ':!check.sh' 2>/dev/null || true)"
if [ -n "$secret_hits" ]; then
  fail "credential-shaped strings in tracked files:"
  printf '%s\n' "$secret_hits" | head -5 | sed 's/^/      /'
else
  ok "no credential-shaped strings in tracked files"
fi

# ---------------------------------------------------------------------------
# C7 — Pin integrity (not pin recency)
# ---------------------------------------------------------------------------
# Being pinned behind upstream is the point of pinning and is not a defect. A
# pin that no longer RESOLVES is, because it breaks a fresh install silently.

criterion "C7 — pin integrity"

sub_out="$(git submodule status 2>/dev/null || true)"
if [ -z "$sub_out" ]; then
  ok "no submodules"
else
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      -*) fail "submodule not initialised: ${line#-}" ;;
      +*) warn "submodule not at the recorded commit: ${line#+}" ;;
      *)  ok "submodule at recorded commit: $(printf '%s' "$line" | awk '{print $2}')" ;;
    esac
  done <<<"$sub_out"
fi

if [ "$OFFLINE" -eq 1 ]; then
  skip "remote URL reachability" "offline"
else
  # Every https URL the install scripts and .gitmodules fetch from. A release
  # asset whose name changed upstream is the highest-value catch here: the
  # script still looks correct and a fresh install fails at that line.
  # The character class must include $ { } or a templated URL gets TRUNCATED at
  # the sigil into something that looks concrete — `.../repos/$repo/releases`
  # became `.../repos/` and then failed as a 403, a pure artefact of the regex.
  # Capturing the sigils is what lets the templated-URL skip below actually fire.
  urls="$(grep -ohE 'https://[A-Za-z0-9./_~:?=&%+${}-]+' \
    install.sh install.common.sh install.linux.sh .gitmodules 2>/dev/null \
    | sed 's/[.,)"'"'"']*$//' | sort -u)"
  bad=0
  checked=0
  for u in $urls; do
    case "$u" in *'$'*|*'{'*) detail "skipped templated URL: $u"; continue ;; esac
    checked=$((checked + 1))
    case "$u" in
      *.git)
        # A git smart-HTTP endpoint 404s on a plain GET — AUR is the common case.
        # Ask git, not curl, or every .git URL reads as broken.
        if git ls-remote "$u" >/dev/null 2>&1; then
          detail "git ok $u"
        else
          fail "git ls-remote failed: $u"; bad=1
        fi
        ;;
      *)
        code="$(curl -fsSL -o /dev/null -w '%{http_code}' --max-time 20 --retry 1 "$u" 2>/dev/null || echo 000)"
        case "$code" in
          2*|3*) detail "$code $u" ;;
          *) fail "unreachable ($code): $u"; bad=1 ;;
        esac
        ;;
    esac
  done
  [ "$bad" -eq 0 ] && ok "all $checked concrete URLs resolve ($(printf '%s\n' "$urls" | grep -c .) found, templated ones skipped)"
fi

# ---------------------------------------------------------------------------
# Verdict
# ---------------------------------------------------------------------------

printf '\n%s──────%s\n' "$C_DIM" "$C_OFF"
if [ "$FAILS" -eq 0 ]; then
  printf '%sPASS%s — %d warning(s), %d skipped\n' "$C_OK" "$C_OFF" "$WARNS" "$SKIPS"
  printf '%sJudgement-based criteria (dead config, deprecated keys, simplification)\nare not scriptable — run a manual review session for those.%s\n' \
    "$C_DIM" "$C_OFF"
  exit 0
else
  printf '%sFAIL%s — %d failure(s), %d warning(s), %d skipped\n' "$C_FAIL" "$C_OFF" "$FAILS" "$WARNS" "$SKIPS"
  # Restated here so a run read through `| tail` still says what broke.
  for _f in "${FAILED_CHECKS[@]}"; do
    printf '  %s✗%s %s\n' "$C_FAIL" "$C_OFF" "$_f"
  done
  exit 1
fi
