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

# The executable a tool provides, for "is it already here?" checks. Only the
# cases where the binary name differs from the tool name need an entry.
bin_name() {
  case "$1" in
    neovim)      echo "nvim" ;;
    ripgrep)     echo "rg" ;;
    git-delta)   echo "delta" ;;
    sevenzip)    echo "7z" ;;
    poppler)     echo "pdftoppm" ;;
    imagemagick) echo "magick" ;;
    ncurses)     echo "tic" ;;
    fontconfig)  echo "fc-cache" ;;
    *)           echo "$1" ;;
  esac
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
run_shared_tail() {
  echo ""
  echo "==> Initialising submodules"
  cd "$DOTFILES" || return 1
  if [ -e "$DOTFILES/.git" ]; then
    git submodule update --init --recursive
  else
    echo "   ! not a git clone — skipping (catppuccin/tmux theme will be absent)"
  fi

  # Stow BEFORE cloning TPM: this makes ~/.config/tmux a symlink into the repo, so
  # the TPM clone below lands at $DOTFILES/tmux/plugins/tpm (gitignored). Cloning
  # first would create a real ~/.config/tmux directory and conflict on tmux.
  echo "==> Stowing dotfiles"
  mkdir -p "$HOME/.config"      # stow aborts if --target from .stowrc doesn't exist
  stow_with_backup "$HOME/.config" .   # nvim, tmux, sesh, ghostty, starship, atuin, git, lazygit, yazi
  stow_with_backup "$HOME" zsh         # zsh dotfiles live in ~, not ~/.config

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
    git clone https://github.com/tmux-plugins/tpm "$HOME/.config/tmux/plugins/tpm"
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
}

# The package step alone used to be the only thing reported, so a run that stowed
# nothing still ended with "Done!". Check what actually landed.
verify_install() {
  echo ""
  echo "==> Verifying"
  local _fail=0 tool bin l real

  for tool in zsh tmux stow neovim ripgrep fzf zoxide bat fd gh lazygit \
              git-delta starship atuin yazi carapace sesh herdr mise jq; do
    bin="$(bin_name "$tool")"
    command -v "$bin" >/dev/null 2>&1 || { echo "   ✗ missing binary: $bin ($tool)"; _fail=1; }
  done

  # Deliberately not `[ -L ]`: when stow folds a whole package it links the
  # *directory* (~/.config/ghostty → repo/ghostty), so the file underneath is a
  # real file reached through the symlink. What matters is where the path ends up,
  # not which component carries the link — so resolve and compare.
  for l in "$HOME/.zshrc" "$HOME/.zshenv" "$HOME/.zprofile" \
           "$HOME/.config/nvim" "$HOME/.config/tmux" "$HOME/.config/sesh" \
           "$HOME/.config/starship.toml" "$HOME/.config/atuin" \
           "$HOME/.config/git" "$HOME/.config/lazygit" "$HOME/.config/yazi" \
           "$HOME/.config/ghostty/config" "$HOME/.config/herdr/config.toml"; do
    if [ -e "$l" ] && real="$(readlink -f "$l" 2>/dev/null)" \
       && case "$real" in "$DOTFILES"/*) true ;; *) false ;; esac; then
      continue
    fi
    echo "   ✗ not linked into the repo: $l"; _fail=1
  done

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
  return 0
}

# Closing message. Set NEXT_STEP_FIRST beforehand to prepend a platform-specific
# step — Linux uses it for the login-shell re-login.
print_next_steps() {
  local n=1 step
  echo ""
  echo "Done!${LOG:+ Log: $LOG}"
  echo "Next:"
  for step in \
    ${NEXT_STEP_FIRST:+"$NEXT_STEP_FIRST"} \
    "Restart your terminal so the new shell config is loaded." \
    "In tmux, press prefix+I to install plugins." \
    "Run 'gh auth login' so gh (and 'gh poi' branch cleanup) works." \
    "Pick language runtimes: mise use -g node@lts java@corretto-25 go@latest"
  do
    printf '  %d. %s\n' "$n" "$step"
    n=$((n + 1))
  done
}
