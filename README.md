# dotfiles

My personal dev environment: terminal, editor, shell, and CLI tools.

## What is inside

| Tool | Config path | Purpose |
|------|-------------|---------|
| [Neovim](https://neovim.io) + [LazyVim](https://lazyvim.org) | `.config/nvim/` | Editor |
| [tmux](https://github.com/tmux/tmux) | `.config/tmux/tmux.conf` | Terminal multiplexer |
| [sesh](https://github.com/joshmedeski/sesh) | `.config/sesh/sesh.toml` | tmux session manager |
| [Worktrunk](https://worktrunk.dev) | `.config/worktrunk/config.toml` | Git worktree create/switch/remove |
| [Ghostty](https://ghostty.org) | `.config/ghostty/` | Terminal emulator |
| [Zsh](https://zsh.sourceforge.io) | `.zshrc`, `.zprofile`, `.zshenv` | Shell |
| [Starship](https://starship.rs) | `.config/starship.toml` | Shell prompt |
| [Atuin](https://atuin.sh) | `.config/atuin/config.toml` | Shell history search |
| [lazygit](https://github.com/jesseduffield/lazygit) | `.config/lazygit/config.yml` | Terminal git UI |
| [yazi](https://github.com/sxyazi/yazi) | `.config/yazi/` | Terminal file manager |
| [Git](https://git-scm.com) | `.gitconfig`, `.gitconfig-work`, `.config/git/config` | Identity and shared git settings |
| [delta](https://github.com/dandavison/delta) | `.config/git/config` | Syntax-highlighting git diff pager |
| [OpenCode](https://opencode.ai) | `.config/opencode/` | AI coding agent: configuration, instructions and the simple-english skill |
| [gh](https://cli.github.com) | none | GitHub CLI |
| [zoxide](https://github.com/ajeetdsouza/zoxide) | none | Smarter `cd` |
| [bat](https://github.com/sharkdp/bat) | none | Better `cat` |
| [fzf](https://github.com/junegunn/fzf) | none | Fuzzy finder |
| [fd](https://github.com/sharkdp/fd) | none | Better `find` |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | none | Better `grep` |
| [carapace](https://carapace.sh) | none | Multi-shell completion engine |
| [mise](https://mise.jdx.dev) | `~/.config/mise/config.toml` (untracked) | Runtime version manager |
| [herdr](https://herdr.dev) | `.config/herdr/config.toml` | Agent workspace multiplexer |
| [jq](https://jqlang.github.io/jq/) | none | JSON processor |

Every config path is relative to `~`.

## How it works

[chezmoi](https://www.chezmoi.io) deploys these files. The repo is the chezmoi
source directory. It lives at `~/.local/share/chezmoi`, and `chezmoi cd` opens
a shell there.

The `.chezmoiroot` file tells chezmoi that the home directory starts at
`home/`. chezmoi renames `dot_` to `.` when it deploys a file. The `private_`
prefix keeps `~/.config` readable only by you (mode 0700):

```
home/dot_zshrc                            →  ~/.zshrc
home/private_dot_config/nvim/init.lua     →  ~/.config/nvim/init.lua
home/private_dot_config/starship.toml     →  ~/.config/starship.toml
```

chezmoi copies each file into place. The files in `~` are not symlinks. If you
edit `~/.config/nvim/init.lua` directly, the repo does not change until you run
`chezmoi re-add`. The safer habit is `chezmoi edit`, which opens the repo copy.

The repo root holds what chezmoi does not deploy:

- `install.sh`, `install.linux.sh` and `install.common.sh` install the tools and run `chezmoi apply`.
- `check.sh` checks that the machine matches the repo.
- `terminfo/` holds an `xterm-256color` variant with undercurl support for herdr panes. The installer compiles it into `~/.terminfo` with `tic`.
- `cheatsheet.md` lists keybindings and commands for the tools.

`home/.chezmoiignore` lists runtime files that tools write next to their
configuration, for example herdr logs, Worktrunk approvals and the tmux plugins
that TPM clones. chezmoi never adds or deploys these files. It also keeps the
OpenCode service password, the generated Trellis plugin and the work-only
skills out of the repo.

Files that end in `.tmpl` are templates: `home/dot_gitconfig.tmpl`,
`home/dot_gitconfig-work.tmpl` and the OpenCode `opencode.json.tmpl`. chezmoi
fills in the work folder and the work email from
`~/.config/chezmoi/chezmoi.toml`, which `home/.chezmoi.toml.tmpl` creates at
`chezmoi init`. `chezmoi re-add` skips templates, so change these files with
`chezmoi edit`, for example `chezmoi edit ~/.gitconfig`.

## Daily workflow

These are the commands you use most. Each one works from any directory.

| Task | Command |
|------|---------|
| Edit a config in the repo copy | `chezmoi edit ~/.config/nvim/init.lua` |
| Edit, then deploy when the editor closes | `chezmoi edit --apply ~/.zshrc` |
| See what `apply` will change in `~` | `chezmoi diff` |
| Deploy the repo to `~` | `chezmoi apply` |
| Copy changes that a tool made in `~` back into the repo | `chezmoi re-add` |
| Start to track a new file or directory | `chezmoi add ~/.config/<tool>` |
| Stop tracking a file, but keep it in `~` | `chezmoi forget ~/.config/<tool>/file` |
| List files that differ between `~` and the repo | `chezmoi status` |
| Open a shell in the repo | `chezmoi cd` |
| Run git in the repo from anywhere | `chezmoi git -- status` |
| Pull the latest commits and deploy them | `chezmoi update` |
| Check the whole machine against the repo | `~/.local/share/chezmoi/check.sh` |

### Change a config and push it

```sh
chezmoi edit --apply ~/.config/tmux/tmux.conf
chezmoi cd
git add -A
git commit -m "Describe the change"
git push
exit
```

Without `chezmoi cd`, use `chezmoi git -- add -A`, `chezmoi git -- commit -m "..."`
and `chezmoi git -- push`.

### Keep a change that a tool made

Some tools write their own configuration. For example, `:Lazy update` in Neovim
rewrites `lazy-lock.json`, and `ya pkg` rewrites the yazi `package.toml`. These
writes change the copy in `~`, not the repo. To keep them, run:

```sh
chezmoi diff        # read the change first
chezmoi re-add      # copy every changed file back into the repo
chezmoi git -- add -A
chezmoi git -- commit -m "Update Neovim plugin versions"
chezmoi git -- push
```

`chezmoi diff` shows the change in reverse, because it shows what `apply` will
do to `~`. If you do not want to keep the change, run `chezmoi apply` to put
the repo version back.

### Add a new tool

```sh
chezmoi add ~/.config/<tool>
chezmoi diff            # must show nothing
chezmoi git -- add -A
chezmoi git -- commit -m "Add <tool> configuration"
chezmoi git -- push
```

If the tool writes runtime files into its configuration directory, add them to
`home/.chezmoiignore` before you run `chezmoi add`. If the tool must be
installed on every machine, also add it to `install.sh` and `install.linux.sh`.

## Fresh machine setup

### 1. Clone the repo

```sh
git clone https://github.com/LuisBarroso37/dotfiles.git ~/.local/share/chezmoi
```

### 2. Run the install script

On macOS:

```sh
~/.local/share/chezmoi/install.sh
```

On Linux with `pacman`, `apt`, or `dnf` (Arch, Manjaro, CachyOS, Debian,
Ubuntu, Mint, Fedora, RHEL, Rocky, 64-bit only), run the script as your own
user. Do not use sudo, because the script asks for it when it needs it:

```sh
~/.local/share/chezmoi/install.linux.sh
```

Both scripts install every tool above, including chezmoi, and run
`chezmoi apply`. If a file already exists where chezmoi deploys one, the
installer moves it to `~/.dotfiles-backup/<date>/` first. The scripts also
install mise with no language runtimes pinned, set up the tmux and sesh
plugins, compile the terminfo entry, and finish with a verification pass.

`install.common.sh` holds the steps that both scripts share. An optional
untracked `install.local.sh` next to them can hold per-machine toolchains.

### 3. Restart your terminal

### 4. Git identity

chezmoi deploys the git identity. `~/.gitconfig` holds the personal identity.
For repos under your work folder, it includes `~/.gitconfig-work`, which sets
the work identity and the work SSH key. OpenCode also reads `AGENTS.md` from
the work folder.

The work folder and the work email stay out of this public repo. The install
script runs `chezmoi init`, which asks for both once and saves them in
`~/.config/chezmoi/chezmoi.toml`. If you leave the folder empty, chezmoi adds
no work rule to `~/.gitconfig`. If you leave the email empty, chezmoi creates
no `~/.gitconfig-work`. chezmoi asks only in a terminal, so a non-interactive
install gets neither.

To set or change the work folder or email later, run:

```sh
chezmoi init --prompt
chezmoi apply
```

### 5. Set up private-registry tokens (optional)

You need this step only for `npm`, `terraform`, or `go` against a private
registry that requires a token. This repo ships no tokens or vault names. An
untracked `opread` shell function in `~/.zshrc.local` fetches them when a
command needs them, not at shell startup. See the worked example in
[cheatsheet.md](cheatsheet.md#gitlab-tokens-opread).

## Updating an existing machine

To get configuration changes that you pushed from another machine, run:

```sh
chezmoi update
```

If the new commits also add a tool, run the install script again. It installs
missing packages and applies the configuration:

```sh
chezmoi update && ~/.local/share/chezmoi/install.sh      # or install.linux.sh
```

On macOS, `brew install` does not upgrade installed formulae. To upgrade the
tools, run `brew update && brew upgrade`. To include casks that update
themselves, run `brew upgrade --cask --greedy`. Then run
`~/.local/share/chezmoi/check.sh` to check the result.

## Machine-specific configuration

`~/.zshrc.local` is untracked, and `~/.zshrc` sources it last. Put anything
that only one machine needs there, for example embedded toolchains, Docker
hosts or SDKMAN.

Language runtimes follow the same split through [mise](https://mise.jdx.dev).
The tracked `~/.zshrc` only activates mise. The versions live in an untracked
`~/.config/mise/config.toml`:

```sh
mise use -g node@lts go@latest java@corretto-25
```

## Notes

Neovim is set up for JS, TS and web work (`vtsls`, ESLint LSP, and `prettier`
through conform). Each piece starts only if the project has a configuration
for it, so nothing runs on machines without JS projects. Settings that belong
to one codebase, for example LSP heap sizes or per-repo lint autocmds, go in
that repo's own `.nvim.lua`. Neovim loads that file through `vim.o.exrc`.

On macOS, the [sesh Raycast extension](https://www.raycast.com/joshmedeski/sesh)
can switch to running tmux sessions from outside Ghostty. It uses the same
sessions as the shell and tmux pickers. It needs a running tmux server.
