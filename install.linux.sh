#!/usr/bin/env bash
set -euo pipefail

# Linux bootstrap for these dotfiles. Companion to install.sh (macOS/Homebrew).
#
# Philosophy — because we can't know the distro *or* which tools its repos carry:
#   1. Detect the package manager (not the distro name) at runtime.
#   2. Best-effort install every tool via that PM; whatever the repo doesn't
#      carry is REPORTED at the end with a fallback recipe — never pretended.
#   3. mise (runtime version manager) comes from its own installer; language
#      runtimes are then chosen per machine with `mise use -g` (see .zshrc).
#   4. GUI bits (ghostty, Nerd Font) are always a manual step on Linux.
#   5. The tail (submodules, stow, TPM, sesh file) is identical to install.sh.

DOTFILES="$HOME/dotfiles"

SUDO=""
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then SUDO="sudo"; fi

MISSING=()  # tools the package manager couldn't provide → reported at the end

# ---------------------------------------------------------------------------
# 1. Detect the package manager
# ---------------------------------------------------------------------------
echo "==> Detecting package manager"
if   command -v apt-get      >/dev/null 2>&1; then PM=apt
elif command -v dnf          >/dev/null 2>&1; then PM=dnf
elif command -v pacman       >/dev/null 2>&1; then PM=pacman
elif command -v zypper       >/dev/null 2>&1; then PM=zypper
elif command -v apk          >/dev/null 2>&1; then PM=apk
elif command -v xbps-install >/dev/null 2>&1; then PM=xbps
else
  echo "!! No supported package manager found (apt/dnf/pacman/zypper/apk/xbps)."
  echo "   Install the tools manually, then re-run from the '==> Stowing' step."
  exit 1
fi
echo "   Using: $PM"

pm_install() { # install one or more packages; returns non-zero if the PM fails
  case "$PM" in
    apt)    $SUDO apt-get install -y "$@" ;;
    dnf)    $SUDO dnf install -y "$@" ;;
    pacman) $SUDO pacman -S --needed --noconfirm "$@" ;;
    zypper) $SUDO zypper install -y "$@" ;;
    apk)    $SUDO apk add "$@" ;;
    xbps)   $SUDO xbps-install -Sy "$@" ;;
  esac
}

pkg_name() { # map a tool to this PM's package name (differences are the exception)
  case "$1" in
    fd)        case "$PM" in apt|dnf) echo "fd-find" ;; *) echo "fd" ;; esac ;;
    git-delta) case "$PM" in apk) echo "delta" ;; *) echo "git-delta" ;; esac ;;
    *)         echo "$1" ;;
  esac
}

# Refresh package indexes once up front where the PM needs it.
echo "==> Refreshing package index"
case "$PM" in
  apt)    $SUDO apt-get update ;;
  zypper) $SUDO zypper refresh ;;
  xbps)   $SUDO xbps-install -S ;;
  *)      : ;;  # dnf/pacman/apk refresh implicitly on install
esac

# ---------------------------------------------------------------------------
# 2. Best-effort native install (reports, never hides, what's unavailable)
# ---------------------------------------------------------------------------
# git + curl are bootstrap deps (submodules, TPM clone, mise installer).
echo "==> Installing tools via $PM (best-effort)"
for tool in \
  git curl tmux stow neovim ripgrep fzf zoxide bat fd \
  gh lazygit git-delta starship atuin yazi carapace
do
  pkg="$(pkg_name "$tool")"
  if pm_install "$pkg" >/dev/null 2>&1; then
    echo "   ✓ $tool ($pkg)"
  else
    echo "   ✗ $tool — not in $PM repos"
    MISSING+=("$tool")
  fi
done

# sesh isn't packaged by any mainstream distro — always a fallback.
MISSING+=("sesh")

# ---------------------------------------------------------------------------
# 3. Debian/Ubuntu binary-name fixups (fd→fdfind, bat→batcat)
# ---------------------------------------------------------------------------
# ~/.local/bin is already first on PATH (see zsh/.zshrc). Alias the renamed
# binaries back to the names the configs expect.
if [ "$PM" = apt ]; then
  mkdir -p "$HOME/.local/bin"
  if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
    ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
    echo "   ↳ symlinked fdfind → ~/.local/bin/fd"
  fi
  if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
    ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
    echo "   ↳ symlinked batcat → ~/.local/bin/bat"
  fi
fi

# ---------------------------------------------------------------------------
# 4. mise — runtime version manager (own installer; not reliably packaged)
# ---------------------------------------------------------------------------
echo "==> Installing mise"
if ! command -v mise >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/mise" ]; then
  curl -fsSL https://mise.run | sh
fi
echo "   Pick language runtimes per machine, e.g.:"
echo "     mise use -g node@lts java@corretto-25 go@latest"

# ---------------------------------------------------------------------------
# 5. ghostty — official on some PMs, community/snap on others
# ---------------------------------------------------------------------------
# (https://ghostty.org/docs/install/binary#linux)
echo "==> Installing ghostty"
if ! command -v ghostty >/dev/null 2>&1; then
  case "$PM" in
    pacman|xbps)
      pm_install ghostty >/dev/null 2>&1 || true ;;                  # official repo
    apk)
      # official, but lives in the 'testing' repo (not enabled on stable)
      $SUDO apk add ghostty >/dev/null 2>&1 \
        || $SUDO apk add --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing ghostty >/dev/null 2>&1 \
        || true ;;
    dnf)
      # not in Fedora's official repos → community COPR
      { $SUDO dnf copr enable -y scottames/ghostty && pm_install ghostty; } >/dev/null 2>&1 || true ;;
  esac
  # cross-distro fallback: the semi-official snap (classic confinement)
  if ! command -v ghostty >/dev/null 2>&1 && command -v snap >/dev/null 2>&1; then
    $SUDO snap install ghostty --classic >/dev/null 2>&1 || true
  fi
fi
if command -v ghostty >/dev/null 2>&1; then
  echo "   ✓ ghostty"
else
  echo "   ✗ ghostty — no direct package for $PM. Options:"
  case "$PM" in
    apt)    echo "       • community .deb: https://github.com/mkasberg/ghostty-ubuntu" ;;
    dnf)    echo "       • COPR: sudo dnf copr enable scottames/ghostty && sudo dnf install ghostty" ;;
    zypper) echo "       • openSUSE dropped it (Zig version) — build from source" ;;
  esac
  echo "       • snap:     sudo snap install ghostty --classic"
  echo "       • AppImage: https://ghostty.org/docs/install/binary (any distro)"
fi

# ---------------------------------------------------------------------------
# 6. Report what native repos couldn't provide, with fallback recipes
# ---------------------------------------------------------------------------
hint() {
  case "$1" in
    starship)  echo "curl -sS https://starship.rs/install.sh | sh" ;;
    atuin)     echo "curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh" ;;
    zoxide)    echo "curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh" ;;
    yazi)      echo "cargo install --locked yazi-fm yazi-cli   (or GitHub releases)" ;;
    sesh)      echo "mise use -g go@latest && go install github.com/joshmedeski/sesh/v2@latest" ;;
    carapace)  echo "GitHub releases: https://github.com/carapace-sh/carapace-bin/releases" ;;
    lazygit)   echo "go install github.com/jesseduffield/lazygit@latest   (or GitHub releases)" ;;
    git-delta) echo "cargo install git-delta   (or GitHub releases: dandavison/delta)" ;;
    gh)        echo "GitHub's repo: https://github.com/cli/cli/blob/trunk/docs/install_linux.md" ;;
    neovim)    echo "If the packaged version is too old: GitHub releases (neovim/neovim) or the AppImage" ;;
    *)         echo "install manually" ;;
  esac
}

if [ ${#MISSING[@]} -gt 0 ]; then
  echo ""
  echo "==> Install these manually ($PM didn't provide them):"
  # de-dup while preserving order
  printf '%s\n' "${MISSING[@]}" | awk '!seen[$0]++' | while read -r t; do
    printf '   - %-10s %s\n' "$t" "$(hint "$t")"
  done
fi

echo ""
echo "==> Nerd Font (manual — the patched JetBrainsMono NF isn't reliably packaged):"
echo "   mkdir -p ~/.local/share/fonts && cd ~/.local/share/fonts \\"
echo "     && curl -fLO https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip \\"
echo "     && unzip -o JetBrainsMono.zip && rm JetBrainsMono.zip && fc-cache -f"

# ---------------------------------------------------------------------------
# 7. Shared tail — identical to install.sh
# ---------------------------------------------------------------------------
echo ""
echo "==> Initialising submodules"
cd "$DOTFILES"
git submodule update --init --recursive

# Stow BEFORE cloning TPM: this makes ~/.config/tmux a symlink into the repo, so the
# TPM clone below lands at ~/dotfiles/tmux/plugins/tpm (gitignored). Cloning first
# would create a real ~/.config/tmux directory and make `stow .` conflict on tmux.
echo "==> Stowing dotfiles"
stow --restow .               # ~/.config packages (nvim, tmux, sesh, ghostty, starship, atuin)
stow --restow --target="$HOME" zsh  # zsh dotfiles live in ~, not ~/.config

echo "==> Installing TPM (tmux plugin manager)"
if [ ! -d "$HOME/.config/tmux/plugins/tpm" ]; then
  git clone https://github.com/tmux-plugins/tpm "$HOME/.config/tmux/plugins/tpm"
fi

# sesh/sesh.toml imports a machine-specific session file; sesh errors if the
# import target is missing, so guarantee it exists (empty is fine). Put work/
# client project sessions here — it stays untracked, outside the dotfiles repo.
echo "==> Ensuring machine-specific sesh session file exists"
[ -f "$HOME/.config/sesh.local.toml" ] || touch "$HOME/.config/sesh.local.toml"

echo ""
echo "Done! Restart your terminal. In tmux run prefix+I to install plugins."
# gh needs a one-time interactive login before wtr's PR-merge cleanup works:
#   gh auth login
echo "Next: run 'gh auth login' so wtr can detect merged PRs."
