#!/usr/bin/env bash
# Shared bootstrap steps for install.sh (macOS) and install.linux.sh (Linux).
#
# NOT executable on its own — it is sourced by both installers, which own the
# platform-specific half (package manager, GUI apps, login shell) and delegate
# everything after that to the functions here.
#
# Why this file exists: the tail used to be copy-pasted into both scripts, with a
# comment in each claiming they were identical. They were not — the Linux copy
# had drifted to the point of missing a `mkdir -p ~/.config` whose absence
# aborted the entire stow step. Extracting it makes that class of drift
# impossible rather than merely detectable.
#
# Contract — the caller must set:
#   DOTFILES   absolute path to the repo (resolved from the script's own location)
# Optional:
#   LOG        path to a package-manager log, mentioned in the closing message
#
# Sourcing this file runs the root check below immediately, so source it early —
# after the caller's platform guard, before anything that touches $HOME.

# Run as YOURSELF, never `sudo ./install*.sh`. Under sudo $HOME becomes /root, so
# every user-scoped step in this file silently targets the wrong account:
#   * stow links the whole repo into /root instead of your home;
#   * terminfo compiles into /root/.terminfo;
#   * the gh extension and the conflict backup dir land in root's home.
# On Linux additionally: chsh switches root's login shell while yours stays on
# bash (so the install looks like it did nothing), and makepkg — therefore
# yay/paru — refuses to run as root outright, failing every AUR package.
#
# This lives here rather than in the callers on purpose. The steps it protects
# are all in this file, so a guard in one installer left the other reaching the
# same code unguarded; on macOS that was covered only incidentally, by Homebrew
# refusing to run as root and dying first. Both installers escalate with sudo on
# their own for the package steps that genuinely need it.
if [ "$(id -u)" -eq 0 ] && [ -z "${DOTFILES_ALLOW_ROOT:-}" ]; then
  _self="$(basename -- "${0:-install.sh}")"
  echo "!! Do not run this script with sudo or as root." >&2
  echo "   \$HOME would be $HOME, so stow, terminfo and the backup directory" >&2
  echo "   would all target the wrong account." >&2
  echo "" >&2
  echo "   Run it as your normal user instead:" >&2
  echo "     ./$_self" >&2
  echo "" >&2
  echo "   (It calls sudo itself for the package installs.)" >&2
  echo "   Genuinely provisioning a root account? DOTFILES_ALLOW_ROOT=1 overrides." >&2
  unset _self
  exit 1
fi

# Where anything stow refuses to overwrite gets moved instead of clobbered.
# Derived from $HOME, so it must come after the root check above.
: "${BACKUP:=$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)}"

# Optional platform-specific first entry in the closing "Next:" list.
: "${NEXT_STEP_FIRST:=}"

# Packages the caller's package step could not install, space-separated, folded
# into verify_install's result. install.sh appends its failed formulae and casks
# here because both of those steps are deliberately non-fatal, and something has
# to remember that afterwards. Left empty on Linux: install.linux.sh does its own
# best-effort accounting (MISSING) and installs fonts itself, so the loop in
# verify_install that reads this simply has nothing to iterate over there.
: "${FAILED_PKGS:=}"

# EVERY binary name a tool may answer to, primary first, space separated. This is
# the single table of binary-name knowledge for both installers; bin_name and
# have_tool below are two views of it, so a new tool is added in exactly one place.
#
# More than one name is the normal case, not an exception, and each entry below is
# a packaging fact that cost a silent failure to learn:
#   * Homebrew's sevenzip installs only 7zz; the Linux packages provide 7z. yazi's
#     archive previewer itself resolves `try("7zz") or try("7z")`, so either means
#     previews work.
#   * apt's imagemagick is ImageMagick 6, which has convert but NO magick at all.
#   * Debian renames fd → fdfind and bat → batcat to avoid collisions (the Linux
#     installer symlinks them back, but the check must pass before that runs).
#   * wl-clipboard is a package that installs no binary of its own name.
# Tools whose binary matches their package name need no entry.
tool_bins() {
  case "$1" in
    neovim)       echo "nvim" ;;
    ripgrep)      echo "rg" ;;
    git-delta)    echo "delta" ;;
    sevenzip)     echo "7zz 7z" ;;
    poppler)      echo "pdftoppm" ;;
    imagemagick)  echo "magick convert" ;;
    ncurses)      echo "tic" ;;
    fontconfig)   echo "fc-cache" ;;
    fd)           echo "fd fdfind" ;;
    bat)          echo "bat batcat" ;;
    wl-clipboard) echo "wl-copy" ;;
    *)            echo "$1" ;;
  esac
}

# The PRIMARY binary — exactly one name, because install.linux.sh consumes it as a
# literal filename when it extracts a bare binary out of a release archive, and as
# the thing to ask `--version`.
bin_name() {
  local names; names="$(tool_bins "$1")"
  printf '%s\n' "${names%% *}"
}

# Is a tool usable on this machine? True if ANY of its names resolves. Callers that
# need to know which one resolved should ask; nothing currently does.
have_tool() {
  local b
  for b in $(tool_bins "$1"); do
    command -v "$b" >/dev/null 2>&1 && return 0
  done
  return 1
}

# Stow refuses to overwrite a real file it doesn't own, and a fresh account often
# ships a skeleton ~/.zshrc — which aborts the whole restow and leaves the install
# half-applied. Move whatever it objects to into $BACKUP and retry, using stow's
# own conflict report as the authority on what is in the way.
stow_with_backup() {
  local target="$1"; shift
  local out conflicts rel
  for _ in 1 2 3; do
    if out="$(stow --restow --target="$target" "$@" 2>&1)"; then
      [ -n "$out" ] && printf '%s\n' "$out"
      return 0
    fi
    conflicts="$(printf '%s\n' "$out" \
      | sed -n -e 's/^ *\* existing target is[^:]*: *//p' \
               -e 's/^ *\* cannot stow .* over existing target \(.*\) since.*$/\1/p')"
    if [ -z "$conflicts" ]; then
      printf '%s\n' "$out" >&2
      return 1
    fi
    while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      [ -e "$target/$rel" ] || [ -L "$target/$rel" ] || continue
      mkdir -p "$BACKUP/$(dirname "$rel")"
      mv "$target/$rel" "$BACKUP/$rel"
      echo "   ↳ backed up $target/$rel → $BACKUP/$rel"
    done <<< "$conflicts"
  done
  echo "!! stow still reports conflicts after 3 attempts" >&2
  return 1
}

# Everything from submodules to the sesh import file: identical on both platforms
# because it only touches this repo and $HOME.
#
# Returns non-zero if a step that verify_install can also see went wrong (stow),
# so finish_install can fold it into the exit status. Steps whose failure is only
# a degradation — a missing tmux theme, no undercurl — warn and return 0.
run_shared_tail() {
  local rc=0
  echo ""
  echo "==> Initialising submodules"
  cd "$DOTFILES" || return 1
  if [ -e "$DOTFILES/.git" ]; then
    # Warn, don't die. This is the first of two network fetches in this function
    # and it was the only unguarded one: on a captive portal or an offline machine
    # it exits non-zero, and `set -e` then killed the run before stow, terminfo,
    # TPM, sesh.local.toml, gh-poi and verify_install — the exact half-applied
    # install this file's design is meant to prevent. An absent .git, a missing
    # tic and a failing cask were all already tolerated with a warning; there was
    # no reason for a fetch to be the one fatal step. All it costs is the
    # catppuccin/tmux theme, and verification still reports the real state.
    git submodule update --init --recursive \
      || echo "   ! submodule fetch failed (offline?) — catppuccin/tmux theme will be absent"
  else
    echo "   ! not a git clone — skipping (catppuccin/tmux theme will be absent)"
  fi

  # Stow BEFORE cloning TPM: this makes ~/.config/tmux a symlink into the repo, so
  # the TPM clone below lands at $DOTFILES/tmux/plugins/tpm (gitignored). Cloning
  # first would create a real ~/.config/tmux directory and conflict on tmux.
  # A stow failure is recorded and carried to the end rather than aborting: the
  # remaining steps are independent of it, and verify_install names every config
  # that is not loaded from the repo — a far more useful report than dying on the
  # first conflict stow could not resolve.
  echo "==> Stowing dotfiles"
  mkdir -p "$HOME/.config"      # stow aborts if --target from .stowrc doesn't exist
  stow_with_backup "$HOME/.config" . || rc=1   # nvim, tmux, sesh, ghostty, starship, atuin, git, lazygit, yazi
  stow_with_backup "$HOME" zsh || rc=1         # zsh dotfiles live in ~, not ~/.config

  ## herdr is stowignored: it writes runtime state (logs, sockets, session.json)
  ## into ~/.config/herdr, so that directory has to stay a real directory rather
  ## than a stow-folded symlink into the repo. Only config.toml is linked, by hand.
  echo "==> Linking herdr config"
  # An earlier run (before herdr was added to .stowrc's ignore list) folded the
  # whole directory into a symlink → $DOTFILES/herdr. Left in place, the ln below
  # resolves source and target to the same path, fails "are the same file", and
  # `set -e` kills the script before terminfo/TPM/sesh ever run. Unfold it first.
  if [ -L "$HOME/.config/herdr" ]; then
    rm -f "$HOME/.config/herdr"
    echo "   ↳ unfolded stow symlink at ~/.config/herdr into a real directory"
  fi
  # The same superseded layout left a second link behind: while herdr was still a
  # stowed package, stow also linked its config.toml straight into ~/.config, as
  # ~/.config/config.toml → ../dotfiles/herdr/config.toml. Nothing reads that path,
  # and because stow no longer owns the package no amount of restowing will ever
  # clean it up — it has to be removed by hand, here.
  #
  # Deliberately narrow: only a symlink, and only one resolving into this repo.
  # ~/.config/config.toml is a plausible name for some other tool's real config, so
  # anything that is not our own stale link is left strictly alone. Note this is a
  # different path from ~/.config/herdr/config.toml, which is the correct link and
  # is (re)created two lines below.
  if [ -L "$HOME/.config/config.toml" ]; then
    local stale
    stale="$(readlink -f "$HOME/.config/config.toml" 2>/dev/null)" || stale=""
    case "$stale" in
      "$DOTFILES"/*)
        rm -f "$HOME/.config/config.toml"
        echo "   ↳ removed stale stow leftover at ~/.config/config.toml (→ $stale)"
        ;;
    esac
  fi
  mkdir -p "$HOME/.config/herdr"
  ln -sfn "$DOTFILES/herdr/config.toml" "$HOME/.config/herdr/config.toml"

  ## terminfo/ is stowignored: these are compiled into ~/.terminfo, not symlinked.
  ## Adds an xterm-256color variant carrying Smulx/Setulc so neovim emits undercurl
  ## inside herdr panes (see the TERM swap in zsh/.zshrc).
  echo "==> Compiling terminfo entries"
  if command -v tic >/dev/null 2>&1; then
    for ti in "$DOTFILES"/terminfo/*.terminfo; do
      [ -e "$ti" ] || continue
      tic -x -o "$HOME/.terminfo" "$ti" && echo "   ✓ $(basename "$ti")"
    done
  else
    echo "   ✗ tic not found (install ncurses) — undercurl in herdr panes will be off"
  fi

  echo "==> Installing TPM (tmux plugin manager)"
  if [ ! -d "$HOME/.config/tmux/plugins/tpm" ]; then
    # The second network fetch, and non-fatal for the same reason as the submodule
    # one above: offline, this used to abort the run before sesh.local.toml, gh-poi
    # and verification ever happened. No warning needed beyond git's own output —
    # verify_install already checks for the tpm directory and reports a ✗, which is
    # what makes the exit status right without this step being fatal.
    git clone https://github.com/tmux-plugins/tpm "$HOME/.config/tmux/plugins/tpm" \
      || echo "   ! TPM clone failed (offline?) — prefix+I will not work until it is installed"
  else
    echo "   ✓ already present"
  fi

  # sesh/sesh.toml imports a machine-specific session file; sesh errors if the
  # import target is missing, so guarantee it exists (empty is fine). Put work/
  # client project sessions here — it stays untracked, outside the dotfiles repo.
  echo "==> Ensuring machine-specific sesh session file exists"
  [ -f "$HOME/.config/sesh.local.toml" ] || touch "$HOME/.config/sesh.local.toml"

  # gh poi is the branch-cleanup step that .zshrc's wtr/wthr point you at after a
  # squash-merge, so the extension has to exist for that advice to work. Needs an
  # authenticated gh, hence the reminder in the closing message.
  echo "==> Installing the gh-poi extension (branch cleanup)"
  if ! command -v gh >/dev/null 2>&1; then
    echo "   ✗ gh not installed — skipping"
  elif gh extension list 2>/dev/null | grep -q 'seachicken/gh-poi'; then
    echo "   ✓ already installed"
  elif gh extension install seachicken/gh-poi >/dev/null 2>&1; then
    echo "   ✓ seachicken/gh-poi"
  else
    echo "   ! could not install (needs 'gh auth login' first) — run:"
    echo "     gh extension install seachicken/gh-poi"
  fi

  return "$rc"
}

# The package step alone used to be the only thing reported, so a run that stowed
# nothing still ended with "Done!". Check what actually landed.
verify_install() {
  echo ""
  echo "==> Verifying"
  local _fail=0 tool pkg l real

  for tool in zsh tmux stow neovim ripgrep fzf zoxide bat fd gh lazygit \
              git-delta starship atuin yazi carapace sesh herdr mise jq; do
    have_tool "$tool" || { echo "   ✗ missing binary: $(bin_name "$tool") ($tool)"; _fail=1; }
  done

  # yazi's preview backends, reported but not fatal — yazi itself works without
  # them, you just lose video thumbnails, archive, PDF and HEIC/JXL previews. They
  # were absent from this list entirely, which is how they stayed missing on every
  # rebuild back when they lived in install.local.sh.
  for tool in ffmpeg sevenzip poppler imagemagick; do
    have_tool "$tool" || echo "   ! yazi preview backend missing: $tool (previews only)"
  done

  # Packages the package step could not install. Both of install.sh's package
  # steps are non-fatal on purpose, so their failures are only visible here — and
  # a cask like the nerd font has no binary anywhere in the checks above to give it
  # away. Empty on Linux (see the FAILED_PKGS contract at the top), so this loop
  # does nothing there.
  for pkg in ${FAILED_PKGS-}; do
    echo "   ✗ package did not install: $pkg"; _fail=1
  done

  # Check a representative config FILE per package, never the directory.
  #
  # Stow has two equally-correct layouts and the directory-level check only
  # recognised one of them. When the target doesn't exist yet stow *folds* the
  # package — ~/.config/nvim becomes a symlink to repo/nvim. When the target is
  # already a real directory holding runtime state (~/.config/atuin has
  # history.db; ~/.config/herdr has sockets and logs) stow *unfolds* instead,
  # leaving a real directory and symlinking the individual files inside it.
  #
  # Resolving the directory therefore reported a perfectly healthy unfolded
  # package as broken — it flagged ~/.config/atuin on a working machine. Asking
  # about the file the tool actually reads is immune to which layout stow chose:
  # folded, it resolves through the directory link; unfolded, the file is itself
  # the link. Either way the question is the one that matters — does this tool
  # load its config from the repo?
  for l in "$HOME/.zshrc" "$HOME/.zshenv" "$HOME/.zprofile" \
           "$HOME/.config/nvim/init.lua" "$HOME/.config/tmux/tmux.conf" \
           "$HOME/.config/sesh/sesh.toml" "$HOME/.config/starship.toml" \
           "$HOME/.config/atuin/config.toml" "$HOME/.config/git/config" \
           "$HOME/.config/lazygit/config.yml" "$HOME/.config/yazi/theme.toml" \
           "$HOME/.config/ghostty/config" "$HOME/.config/herdr/config.toml"; do
    if [ -e "$l" ] && real="$(readlink -f "$l" 2>/dev/null)" \
       && case "$real" in "$DOTFILES"/*) true ;; *) false ;; esac; then
      continue
    fi
    echo "   ✗ config not loaded from the repo: $l"; _fail=1
  done

  # macOS-only symlinks — not checked on Linux where karabiner-elements does not exist.
  if [ "$(uname -s)" = "Darwin" ]; then
    for l in "$HOME/.config/karabiner/karabiner.json"; do
      if [ -e "$l" ] && real="$(readlink -f "$l" 2>/dev/null)" \
         && case "$real" in "$DOTFILES"/*) true ;; *) false ;; esac; then
        continue
      fi
      echo "   ✗ config not loaded from the repo: $l"; _fail=1
    done
  fi

  [ -d "$HOME/.config/tmux/plugins/tpm" ] || { echo "   ✗ TPM not installed"; _fail=1; }
  [ -f "$HOME/.config/sesh.local.toml" ]  || { echo "   ✗ sesh.local.toml missing"; _fail=1; }
  infocmp xterm-256color-undercurl >/dev/null 2>&1 \
    || echo "   ! terminfo entry xterm-256color-undercurl not compiled (undercurl only)"

  if [ "$_fail" -eq 0 ]; then
    echo "   ✓ all checks passed"
  else
    echo "   (see the manual-install section above for anything missing)"
  fi

  [ -d "$BACKUP" ] && echo "" && echo "==> Files moved aside are in $BACKUP"
  return "$_fail"
}

# The single call both installers end with. Verification used to be advisory:
# it printed ✗ lines and the script still finished with "Done!" and exit 0, so
# neither a human skimming the tail nor a CI job could tell a good run from a
# broken one. Now its result is the script's exit status — while still printing
# the next-steps block first, since those are useful either way.
finish_install() {
  local rc=0
  # `|| rc=1` rather than a bare call, for two reasons. It keeps a failure the tail
  # reports (stow) out of the "Done!" path, and — because `set -e` does not apply
  # inside a function whose result is being tested — it is what lets the steps in
  # there warn and carry on instead of taking the script down mid-way. Both halves
  # of that are the point: get to verify_install no matter what, and let its
  # verdict be the exit status.
  run_shared_tail || rc=1
  verify_install || rc=1
  print_next_steps
  if [ "$rc" -ne 0 ]; then
    echo "" >&2
    echo "!! The install is INCOMPLETE — see the ✗ lines under 'Verifying' above." >&2
  fi
  return "$rc"
}

# Closing message. Set NEXT_STEP_FIRST beforehand to prepend a platform-specific
# step — Linux uses it for the login-shell re-login.
#
# The git identity step is here rather than automated because it cannot live in
# this repo: it is per-machine (work vs personal name and address) and secondly it
# has to go in ~/.gitconfig, which is NOT stowed. The stowed git package provides
# ~/.config/git/config, and ~/.gitconfig takes precedence over it — so identity
# plus the [includeIf "gitdir:..."] rules that switch to a personal identity for
# certain trees have to be written there to win. Nothing created that file and no
# step mentioned it, so the first commit on a fresh machine died with "Author
# identity unknown" and left you guessing. README.md carries the snippet.
print_next_steps() {
  local n=1 step
  echo ""
  echo "Done!${LOG:+ Log: $LOG}"
  echo "Next:"
  for step in \
    ${NEXT_STEP_FIRST:+"$NEXT_STEP_FIRST"} \
    "Restart your terminal so the new shell config is loaded." \
    "In tmux, press prefix+I to install plugins." \
    "Set your git identity in ~/.gitconfig — see the git identity section in README.md." \
    "Run 'gh auth login' so gh (and 'gh poi' branch cleanup) works." \
    "Pick language runtimes: mise use -g node@lts java@corretto-25 go@latest"
  do
    printf '  %d. %s\n' "$n" "$step"
    n=$((n + 1))
  done
}
