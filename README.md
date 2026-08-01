# dotfiles

My personal dev environment — terminal, editor, shell, and CLI tools.

## What's inside

| Tool | Config path | Purpose |
|------|-------------|---------|
| [Neovim](https://neovim.io) + [LazyVim](https://lazyvim.org) | `.config/nvim/` | Editor |
| [tmux](https://github.com/tmux/tmux) | `.config/tmux/tmux.conf` | Terminal multiplexer |
| [sesh](https://github.com/joshmedeski/sesh) | `.config/sesh/sesh.toml` | tmux session manager |
| [Ghostty](https://ghostty.org) | `.config/ghostty/` | Terminal emulator |
| [Zsh](https://zsh.sourceforge.io) | `.zshrc`, `.zprofile`, `.zshenv` | Shell |
| [Starship](https://starship.rs) | `.config/starship.toml` | Shell prompt |
| [Atuin](https://atuin.sh) | `.config/atuin/config.toml` | Shell history search |
| [lazygit](https://github.com/jesseduffield/lazygit) | `.config/lazygit/config.yml` | Terminal git UI |
| [yazi](https://github.com/sxyazi/yazi) | `.config/yazi/` | Terminal file manager (`y` cd's into last dir on exit) |
| [delta](https://github.com/dandavison/delta) | `.config/git/config` | Syntax-highlighting git diff pager |
| [gh](https://cli.github.com) | — | GitHub CLI (PRs, issues, auth from the terminal) |
| [zoxide](https://github.com/ajeetdsouza/zoxide) | — | Smarter `cd` |
| [bat](https://github.com/sharkdp/bat) | — | Better `cat` |
| [fzf](https://github.com/junegunn/fzf) | — | Fuzzy finder |
| [fd](https://github.com/sharkdp/fd) | — | Better `find` |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | — | Better `grep` |
| [carapace](https://carapace.sh) | — | Multi-shell completion engine |
| [mise](https://mise.jdx.dev) | `~/.config/mise/config.toml` (untracked) | Runtime version manager (node, go, java, …) |
| [herdr](https://herdr.dev) | `.config/herdr/config.toml` | Agent workspace multiplexer (owns `Ctrl+a`; drives `wth`/`wthr`) |
| [jq](https://jqlang.github.io/jq/) | — | JSON processor — **required** by the `wth`/`wthr` worktree helpers |

---

## Key idea

The problem with dotfiles is that tools expect their configs at fixed paths (e.g. `~/.config/nvim/`), but you want those files tracked in a git repo.

The solution is [GNU Stow](https://www.gnu.org/software/stow/) — a symlink manager. Your real config files live inside `~/dotfiles/`, and Stow creates symlinks at the locations tools expect, pointing back into the repo:

```
~/dotfiles/nvim/   ──►  ~/.config/nvim/   (symlink)
~/dotfiles/tmux/   ──►  ~/.config/tmux/   (symlink)
```

You edit files at the paths you already know (`~/.config/nvim/`, etc.) — they just happen to be symlinks. Git sees the real files inside `~/dotfiles/`, so you commit and push changes like any other repo. **Stow is the only required tool that isn't a terminal utility** — everything else is optional depending on what you use.

---

## Fresh machine setup

### 1. Clone the repo

```sh
git clone https://github.com/<your-username>/dotfiles.git ~/dotfiles
```

### 2. Run the install script

**macOS** (Homebrew):

```sh
cd ~/dotfiles
chmod +x install.sh
./install.sh
```

**Linux** (native package manager — apt/dnf/pacman/zypper/apk/xbps):

```sh
cd ~/dotfiles
chmod +x install.linux.sh
./install.linux.sh
```

`install.linux.sh` detects the package manager, installs every tool it can, and
**reports** anything the distro's repos don't carry with a copy-paste fallback
recipe (rather than pretending it succeeded). GUI bits (Ghostty, the Nerd Font)
are always a manual step on Linux — the script prints the exact commands.

Both scripts will:
- Install all tools listed above (via `brew` on macOS, the native PM on Linux)
- Install **GNU Stow** — required to create the symlinks
- Use Stow to symlink all configs to their correct locations
- Install [mise](https://mise.jdx.dev) (the runtime version manager) — but **no
  language runtimes**; a fresh clone is language-free (see "Machine-specific
  shell config" below)
- Initialise the catppuccin-tmux submodule and clone TPM (tmux plugin manager)
- Create an empty `~/.config/sesh.local.toml` (sesh errors on a missing import)

Both also source an optional, untracked `install.local.sh` if you place one next
to them — put per-machine package installs there (e.g. yazi's optional preview
deps), so the tracked scripts stay portable.

### 3. Restart your terminal

All configs will be in place and your shell, editor, and tools will pick them up automatically.

---

## How Stow works in practice

Each tool has its own subdirectory at the root of this repo, containing its config files directly. A `.stowrc` sets the stow target to `~/.config`, so running `stow .` creates a directory-level symlink in `~/.config/` for each package:

```
dotfiles/
  nvim/          →  ~/.config/nvim  (symlink to ~/dotfiles/nvim/)
    init.lua
    lua/
  tmux/          →  ~/.config/tmux  (symlink to ~/dotfiles/tmux/)
    tmux.conf
  starship.toml  →  ~/.config/starship.toml
```

The key: `stow .` treats the entire dotfiles directory as a single package. Each top-level folder gets folded into one symlink in `~/.config/`, rather than symlinking individual files. Files like `README.md` and `install.sh` are excluded via `.stowrc` ignore rules.

**Zsh is a special case** — its dotfiles (`.zshrc`, `.zprofile`, `.zshenv`) live directly in `~`, not `~/.config/`. The `zsh/` package is excluded from `stow .` and stowed separately with an explicit target:

```sh
stow .                     # all ~/.config packages
stow --target="$HOME" zsh  # zsh dotfiles → ~
```

**Two more packages are excluded from `stow .`**, because a symlink is the wrong
shape for them:

- `herdr/` — herdr writes runtime state (logs, sockets, `session.json`) into
  `~/.config/herdr`, so that has to stay a real directory. `install.sh` links
  only `config.toml` into it by hand. Left to stow, the whole restow aborts with
  *"existing target is not owned by stow"* and **no other package gets restowed
  either**.
- `terminfo/` — terminfo sources are *compiled* into `~/.terminfo` with `tic`,
  not symlinked. `install.sh` does that. It carries an `xterm-256color` variant
  with `Smulx`/`Setulc` so Neovim emits undercurl (red squiggles on LSP
  diagnostics) inside herdr panes, which force `TERM=xterm-256color`; `.zshrc`
  switches `TERM` to it when it detects a herdr pane. Inside tmux the equivalent
  fix is `terminal-features ',*:usstyle'` in `tmux.conf`.

**Machine-specific shell config** — anything you *don't* want on every machine (the Angular CLI, Docker hosts, embedded toolchains, SDKMAN, and any runtime not managed by mise) lives in `~/.zshrc.local`, which the tracked `.zshrc` sources at the very end if it exists:

```sh
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
```

`~/.zshrc.local` is **not** tracked by this repo — it sits in `~`, outside `~/dotfiles/`, so git never sees it. That keeps the committed config portable: a fresh machine gets only the cross-machine tooling and starts clean. Recreate `~/.zshrc.local` per machine with just the toolchains that machine actually needs (it's sourced last, so tools like SDKMAN that must initialise at the end of `.zshrc` still work).

**Language runtimes** follow the same portability split, via [mise](https://mise.jdx.dev). The tracked `.zshrc` only *activates* mise (`eval "$(mise activate zsh)"`); the actual language versions live in an **untracked** `~/.config/mise/config.toml`, chosen per machine:

```sh
mise use -g node@lts go@latest java@corretto-25   # writes ~/.config/mise/config.toml
```

So a fresh clone starts **language-free** — no Node, Go, or Java is pinned by the repo. (Rust is the exception: it stays on rustup, and `.zshrc` just sources `~/.cargo/env` if present.)

**Neovim is tuned for JS/TS/web.** The language-specific plugins (`vtsls`, `eslint`, `prettier` via conform, the JSON eslint-fix autocmd) are intentionally kept, but every one **self-gates** — prettier only runs when a prettier config resolves, eslint only when `node_modules/eslint` exists — so on a Rust/Go/etc. machine they're inert no-ops, not breakage.

To add a new tool to the repo:

1. Create its folder: `mkdir ~/dotfiles/<tool>/`
2. Move the config there: `mv ~/.config/<tool>/ ~/dotfiles/<tool>/`
3. Restow: `cd ~/dotfiles && stow .`

