#!/usr/bin/env bash
# Shared bootstrap steps for install.sh (macOS) and install.linux.sh (Linux).
#
# Source this file from either installer. Keep platform-specific steps in the callers.
#
# Contract — the caller must set:
#   DOTFILES   absolute path to the repo (resolved from the script's own location)
# Optional:
#   LOG        path to a package-manager log, mentioned in the closing message
#
# Sourcing this file runs the root check below immediately, so source it early —
# after the caller's platform guard, before anything that touches $HOME.

# Run as your normal user. Root installation targets the wrong home and login shell.
# Both installers call sudo themselves for package steps. AUR builds cannot run as root.
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
  # Return so callers can catch failure without terminating their shell.
  return 1
fi

# Where anything stow refuses to overwrite gets moved instead of clobbered.
# Derived from $HOME, so it must come after the root check above.
: "${BACKUP:=$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)}"

# Optional platform-specific first entry in the closing "Next:" list.
: "${NEXT_STEP_FIRST:=}"

# Both installers record package failures here, space-separated, for verify_install's exit status.
: "${FAILED_PKGS:=}"

# Accepted binary names for both installers, primary first and space-separated.
# Homebrew uses 7zz, Linux uses 7z. ImageMagick 6 provides convert, not magick.
# Debian renames fd/bat to fdfind/batcat. wl-clipboard provides wl-copy.
# Tools whose binary matches their package name need no entry.
tool_bins() {
  case "$1" in
    neovim)       echo "nvim" ;;
    ripgrep)      echo "rg" ;;
    git-delta)    echo "delta" ;;
    worktrunk)    echo "wt" ;;
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

# Return one primary name for release extraction and version queries.
bin_name() {
  local names; names="$(tool_bins "$1")"
  printf '%s\n' "${names%% *}"
}

# Accept any binary name listed for this tool.
have_tool() {
  local b
  for b in $(tool_bins "$1"); do
    command -v "$b" >/dev/null 2>&1 && return 0
  done
  return 1
}

# Move conflicting target files into $BACKUP and retry, using Stow's conflict report.
stow_with_backup() {
  local target="$1"; shift
  local out conflicts rel
  for _ in 1 2 3; do
    if out="$(stow --restow --target="$target" "$@" 2>&1)"; then
      [ -n "$out" ] && printf '%s\n' "$out"
      return 0
    fi
    # Extract targets from Stow's starred conflict lines, including directory mismatches.
    # The first match wins. Strip "=> destination" and ignore source-only conflicts.
    conflicts="$(printf '%s\n' "$out" | sed -n -E '
/^ *\* /!d
s/^ *\* existing target is[^:]*: *//
t strip
s/^ *\* cannot stow .* over existing target (.*) since .*$/\1/
t strip
s/^ *\* cannot stow .* over existing (non-)?directory target (.*)$/\2/
t strip
s/^ *\* cannot stow .* over existing target (.*)$/\1/
t strip
d
:strip
s/ => .*$//
p
')" || conflicts=""
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

# Everything from Stow to the sesh import file: identical on both platforms
# because it only touches this repo and $HOME.
#
# Returns non-zero if a step that verify_install can also see went wrong (stow),
# so finish_install can fold it into the exit status. Steps whose failure is only
# a degradation — a missing tmux theme, no undercurl — warn and return 0.
run_shared_tail() {
  local rc=0
  echo ""
  cd "$DOTFILES" || return 1
  # Stow before cloning TPM so plugins land in the repo's ignored directory.
  # Record stow failures, but continue so verification can report all missing links.
  echo "==> Stowing dotfiles"
  mkdir -p "$HOME/.config"      # stow aborts if --target from .stowrc doesn't exist
  # Worktrunk writes approvals beside config.toml: don't fold that directory
  # into the tracked repo when stowing a fresh home.
  mkdir -p "$HOME/.config/worktrunk"
  stow_with_backup "$HOME/.config" . || rc=1
  stow_with_backup "$HOME" zsh || rc=1         # zsh dotfiles live in ~, not ~/.config
  # Private-module credentials stay in ~/.netrc and the untracked ~/.zshrc.local.

  ## herdr is stowignored: it writes runtime state (logs, sockets, session.json)
  ## into ~/.config/herdr, so that directory has to stay a real directory rather
  ## than a stow-folded symlink into the repo. Only config.toml is linked, by hand.
  echo "==> Linking herdr config"
  # Unfold legacy directory links before linking config.toml to avoid a self-link.
  if [ -L "$HOME/.config/herdr" ]; then
    rm -f "$HOME/.config/herdr"
    echo "   ↳ unfolded stow symlink at ~/.config/herdr into a real directory"
  fi
  # Remove the legacy ~/.config/config.toml only if it is a symlink into this repo.
  # Preserve other tools' files. The correct link is ~/.config/herdr/config.toml.
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
    # An offline fetch must not abort the run before verification. Git prints
    # the failure and verify_install checks for the TPM directory.
    git clone https://github.com/tmux-plugins/tpm "$HOME/.config/tmux/plugins/tpm" \
      || echo "   ! TPM clone failed (offline?) — prefix+I will not work until it is installed"
  else
    echo "   ✓ already present"
  fi
  # Older clones had Catppuccin at this same path as a Git submodule. TPM sees
  # the directory as "already installed" and would never honor the new release
  # pin. Only remove a clean submodule belonging to this repo; preserve local
  # edits and unknown directories for manual review.
  local catpath="$HOME/.config/tmux/plugins/tmux" cat_status
  if [ -f "$catpath/.git" ]; then
    cat_status="$(git -C "$catpath" status --porcelain 2>/dev/null)" || cat_status=unknown
    if [ "$(readlink -f "$catpath" 2>/dev/null)" = "$DOTFILES/tmux/plugins/tmux" ] \
       && [ -z "$cat_status" ]; then
      rm -rf "$catpath"
      echo "   ↳ removed clean, retired Catppuccin submodule for TPM to reinstall"
    else
      echo "   ! old Catppuccin submodule has local changes or is not from this repo; migrate it manually" >&2
      rc=1
    fi
  fi
  # Install plugins on a fresh machine, including the theme.
  if [ -x "$HOME/.config/tmux/plugins/tpm/bin/install_plugins" ]; then
    "$HOME/.config/tmux/plugins/tpm/bin/install_plugins" \
      || { echo "   ! TPM could not install all plugins (offline?)" >&2; rc=1; }
  fi

  # sesh/sesh.toml imports a machine-specific session file; sesh errors if the
  # import target is missing, so guarantee it exists (empty is fine). Put work/
  # client project sessions here — it stays untracked, outside the dotfiles repo.
  echo "==> Ensuring machine-specific sesh session file exists"
  [ -f "$HOME/.config/sesh.local.toml" ] || touch "$HOME/.config/sesh.local.toml"

  return "$rc"
}

# Report installed tools and links, not just package-manager success.
verify_install() {
  echo ""
  echo "==> Verifying"
  local _fail=0 tool pkg l real

  for tool in zsh tmux stow neovim ripgrep fzf zoxide bat fd gh lazygit \
              git-delta starship atuin yazi carapace sesh herdr worktrunk mise jq; do
    have_tool "$tool" || { echo "   ✗ missing binary: $(bin_name "$tool") ($tool)"; _fail=1; }
  done

  # Missing preview backends only warn, since yazi works without previews.
  for tool in ffmpeg sevenzip poppler imagemagick; do
    have_tool "$tool" || echo "   ! yazi preview backend missing: $tool (previews only)"
  done

  # Missing script linting only warns, since runtime configuration does not need it.
  have_tool shellcheck || echo "   ! shellcheck missing (lints these install scripts; check.sh C8)"

  # Include recorded failures that binary checks cannot detect, such as the font.
  for pkg in ${FAILED_PKGS-}; do
    echo "   ✗ package missing or unusable: $pkg"; _fail=1
  done

  # Resolve representative files, since Stow can link either directories or individual files.
  for l in "$HOME/.zshrc" "$HOME/.zshenv" "$HOME/.zprofile" \
           "$HOME/.config/nvim/init.lua" "$HOME/.config/tmux/tmux.conf" \
           "$HOME/.config/sesh/sesh.toml" "$HOME/.config/starship.toml" \
           "$HOME/.config/atuin/config.toml" "$HOME/.config/git/config" \
           "$HOME/.config/lazygit/config.yml" "$HOME/.config/yazi/theme.toml" \
           "$HOME/.config/ghostty/config" "$HOME/.config/herdr/config.toml" \
           "$HOME/.config/worktrunk/config.toml"; do
    if [ -e "$l" ] && real="$(readlink -f "$l" 2>/dev/null)" \
       && case "$real" in "$DOTFILES"/*) true ;; *) false ;; esac; then
      continue
    fi
    echo "   ✗ config not loaded from the repo: $l"; _fail=1
  done

  [ -d "$HOME/.config/tmux/plugins/tpm" ] || { echo "   ✗ TPM not installed"; _fail=1; }
  [ -f "$HOME/.config/tmux/plugins/tmux/catppuccin.tmux" ] \
    || { echo "   ✗ Catppuccin tmux plugin missing (run prefix+I)"; _fail=1; }
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

# Always print next steps, but return failure if shared steps or verification fail.
finish_install() {
  local rc=0
  # Testing the return status disables errexit inside the tail so verification always runs.
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
# Keep machine-specific identity and includeIf rules in ~/.gitconfig, which takes precedence over the stowed Git configuration.
print_next_steps() {
  local n=1 step
  echo ""
  echo "Done!${LOG:+ Log: $LOG}"
  echo "Next:"
  for step in \
    ${NEXT_STEP_FIRST:+"$NEXT_STEP_FIRST"} \
    "Restart your terminal so the new shell config is loaded." \
    "In tmux, press prefix+I to retry any plugins that failed to install." \
    "Set your git identity in ~/.gitconfig — see the git identity section in README.md." \
    "Authenticate your forge CLI ('gh auth login' or 'glab auth login') for PR/MR lookup." \
    "Pick language runtimes: mise use -g node@lts java@corretto-25 go@latest"
  do
    printf '  %d. %s\n' "$n" "$step"
    n=$((n + 1))
  done
}
