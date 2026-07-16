# dotfiles

My personal dev environment — terminal, editor, shell, and CLI tools.

## What's inside

| Tool | Config path | Purpose |
|------|-------------|---------|
| [Neovim](https://neovim.io) + [LazyVim](https://lazyvim.org) | `.config/nvim/` | Editor |
| [tmux](https://github.com/tmux/tmux) | `.config/tmux/tmux.conf` | Terminal multiplexer |
| [sesh](https://github.com/joshmedeski/sesh) | `.config/sesh/sesh.toml` | tmux session manager |
| [worktrunk](https://worktrunk.dev) | `.config/worktrunk/config.toml` | git worktree + tmux session helper (`wt`) |
| [Ghostty](https://ghostty.org) | `.config/ghostty/` | Terminal emulator |
| [Zsh](https://zsh.sourceforge.io) | `.zshrc`, `.zprofile`, `.zshenv` | Shell |
| [Starship](https://starship.rs) | `.config/starship.toml` | Shell prompt |
| [Atuin](https://atuin.sh) | `.config/atuin/config.toml` | Shell history search |
| [lazygit](https://github.com/jesseduffield/lazygit) | `.config/lazygit/config.yml` | Terminal git UI |
| [delta](https://github.com/dandavison/delta) | `.config/git/config` | Syntax-highlighting git diff pager |
| [zoxide](https://github.com/ajeetdsouza/zoxide) | — | Smarter `cd` |
| [bat](https://github.com/sharkdp/bat) | — | Better `cat` |
| [fzf](https://github.com/junegunn/fzf) | — | Fuzzy finder |
| [fd](https://github.com/sharkdp/fd) | — | Better `find` |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | — | Better `grep` |

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

```sh
cd ~/dotfiles
chmod +x install.sh
./install.sh
```

This will:
- Install [Homebrew](https://brew.sh) (if missing)
- Install all tools listed above via `brew install`
- Install **GNU Stow** (`brew install stow`) — required to create the symlinks
- Use Stow to symlink all configs to their correct locations

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

**Machine-specific shell config** — anything you *don't* want on every machine (language toolchains like Node/NVM, the Angular CLI, Java, Python/pyenv, Go, SDKMAN, Rust) lives in `~/.zshrc.local`, which the tracked `.zshrc` sources at the very end if it exists:

```sh
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
```

`~/.zshrc.local` is **not** tracked by this repo — it sits in `~`, outside `~/dotfiles/`, so git never sees it. That keeps the committed config portable: a fresh machine gets only the cross-machine tooling and starts clean. Recreate `~/.zshrc.local` per machine with just the toolchains that machine actually needs (it's sourced last, so tools like SDKMAN that must initialise at the end of `.zshrc` still work).

To add a new tool to the repo:

1. Create its folder: `mkdir ~/dotfiles/<tool>/`
2. Move the config there: `mv ~/.config/<tool>/ ~/dotfiles/<tool>/`
3. Restow: `cd ~/dotfiles && stow .`

---

## First-time migration (existing machine only)

If you already have configs on your current machine and want to move them into this repo, run the migration script instead of the install script:

```sh
cd ~/dotfiles
chmod +x migrate.sh
./migrate.sh
```

This will:
1. Move each existing config from `~/.config/<tool>/` into `~/dotfiles/<tool>/`
2. Install Stow if missing
3. Run `stow .` to put the symlinks in place

After that, push to GitHub:

```sh
cd ~/dotfiles
git init
git add .
git commit -m "initial dotfiles"
git remote add origin git@github.com:<your-username>/dotfiles.git
git push -u origin main
```

From this point on, any change you make to your configs is just a `git push` away from being synced everywhere.
