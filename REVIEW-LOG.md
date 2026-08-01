# Review log

The ledger of what has been reviewed and **decided**. Its purpose is to make
reviews converge instead of restarting from zero every time.

Without this file, every "review the dotfiles thoroughly" re-derives findings
from scratch, re-proposes things already rejected, and always returns a
non-empty list — which reads as "the repo is still broken" when it often means
"the reviewer had no memory". A finding that appears here with a verdict is
**settled**. Don't raise it again unless the underlying facts change.

## How to use it

1. Run `./check.sh` first. It gates the mechanical criteria (C2–C9 below) and can
   actually **pass**. Anything it catches is not a judgement call — just fix it.
2. For a judgement review, work only on what `check.sh` cannot decide: dead
   config, deprecated keys, and whether something could be simpler. Then record
   every finding here with a verdict.
3. **Verdicts:** `FIXED (date, commit)` · `REJECTED (date, why)` ·
   `ACCEPTED-RISK (date, why)` · `OPEN`.
4. A `REJECTED` entry is a standing instruction to future reviewers. Argue with
   it only with new evidence, and say what the new evidence is.

## Completion criteria

"All possible improvements" has no passing state, which is why reviews of that
shape never converge. These do. Status is from the review of 2026-08-01.

| # | Criterion | Gated by | Status |
|---|---|---|---|
| C1 | Fresh clone → working machine, no undocumented manual steps | not scriptable | **Linux: PASS (2026-08-01)** — run end-to-end as a non-root sudo user in clean `archlinux:latest`, `debian:trixie` and `fedora:latest` containers, each finishing with every verification check passing. Two limits stand: the derivatives in each row were never tested directly, and a container has no GUI, so ghostty and the Nerd Font install but are never seen to render. **macOS: still unverified** — needs a spare machine or throwaway account |
| C2 | Startup health silent (zsh, nvim, tmux) | `check.sh` | pass |
| C3 | Stow closure — no conflicts, nothing tracked-but-undeployed | `check.sh` | pass |
| C4 | Reference closure — every tool a config needs is installed | `check.sh` + `verify_install` | 1 warning (P2-01) |
| C5 | Doc closure — nothing documented that doesn't exist | `check.sh` (partial) + review | **fail** — P1-11, and see the doc table |
| C6 | No resurrected config (deliberately removed things stay gone) | `check.sh` | pass |
| C7 | **Pin integrity** — every pin/URL resolves (not "is newest") | `check.sh` | pass |
| C8 | Script syntax + lint clean | `check.sh` | pass |
| C9 | No secrets, no tracked machine state | `check.sh` | pass (but see P0-02) |

C7 is deliberately *integrity*, not *recency*. Being pinned behind upstream is
the point of pinning; a pin that no longer resolves is a real defect. As of
2026-08-01 every tool is on the exact latest upstream release, which is unusual
and worth recording so nobody "fixes" it again.

**What no automated check covers, by design:** whether a design could be
simpler, whether a comment is still true, and whether a config key was
deprecated upstream. Those need a periodic judgement review — the criteria for
which are in "Improvement criteria" at the bottom.

---

# Findings — review of 2026-08-01

Nine parallel audits (macOS bootstrap, Linux bootstrap, zsh, nvim, terminal
stack, stow/tool configs, docs, cross-cutting seams, upstream freshness) against
`c582fa7`. Every finding below was proven by execution or against a live upstream
source. Cross-corroborated findings are marked ×2/×3 — independent audits that
reached the same conclusion.

**Status: all closed on 2026-08-01.** Every finding was fixed the same day except
P2-14 and F-14 (ACCEPTED-RISK, reasoned in their rows) and F-15 (OPEN, low).
`./check.sh` passes with 0 failures and 0 warnings. Each fix was verified by
execution, not by reading — the evidence is summarised per group in "How these were
verified" below.

Then `install.linux.sh` was run end-to-end in Arch, Debian and Fedora containers,
which found three more defects that static review had not — see "Found by container
testing". That is the honest shape of this: a clean gate plus a clean audit still
left defects that only executing the thing on a real machine could surface.

The P4 table has no verdict column: every row in it was corrected on 2026-08-01.

## P0 — act first

| ID | Location | Finding | Verdict |
|---|---|---|---|
| P0-01 | `zsh/.zshrc:417-428` | **Data loss.** `wthr` lacks the self-removal guard `wtr` has (`:287-291`). From a herdr pane whose cwd *is* the worktree, `wthr --force` deletes the checkout under you, discarding uncommitted changes, no confirmation, leaving the shell in a deleted cwd. `cheatsheet.md:81,87` promises the symmetry the code does not have. Fix: lift the guard into `_wt_refuse_self` and call it from both. | FIXED (2026-08-01) |
| P0-02 | `atuin/config.toml:29-32` | **Privacy.** `[ai] enabled = true` with a comment claiming "Atuin sends only OS and shell name/version, not shell history" — false for 18.18.1. `AiCapabilities` (`enable_history_search`, `enable_history_output`, `enable_file_tools`, `enable_command_execution`) default to enabled-with-prompt, and requests go to `api.atuin.sh`. Your history is 9 MB of commands against a PHI-handling platform. Fix: set `[ai.capabilities]` explicitly, or `enabled = false` on work machines. ×2 | FIXED (2026-08-01) |

## P1 — broken today

| ID | Location | Finding | Verdict |
|---|---|---|---|
| P1-01 | `zsh/.zshrc:244-245` | `wtc` tries `git worktree add -b` **first**, so the tracking fallback is unreachable when the branch exists only on the remote: you silently get an empty branch off your current HEAD instead of a colleague's work. Proven in a scratch clone. Fix: swap the order. | FIXED (2026-08-01) |
| P1-02 | `zsh/.zshrc:156` | `git branch -d` deletes a branch merged into **its upstream**, not into the default branch, and `2>/dev/null` swallows git's warning saying so. `wtr` before a PR merges reports `✓ deleted branch` while destroying it. Contradicts `:151` and `cheatsheet.md:79`. Fix: drop the redirect, or gate on `merge-base --is-ancestor`. | FIXED (2026-08-01) |
| P1-03 | `zsh/.zshrc:249,252,254,300` | The `=` exact-match prefix does not protect a tmux target from a `.` — tmux parses it as `window.pane`. Any branch with a dot (`release/1.2.0`) breaks `has-session`/`kill-session`; `wtr` then leaves resurrect pointing at a deleted dir. Proven on an isolated socket. Fix: collapse `.`/`:` in `_wt_paths:146`. | FIXED (2026-08-01) |
| P1-04 | `nvim/lua/plugins/formatting.lua:59-67` | When prettier's per-project gate returns false, conform goes inactive and LazyVim's **LSP** formatter activates instead — `jsonls` reformats. Measured: `lazy-lock.json` 40 → 154 lines on a stray `:w`. Fix: strip `documentFormattingProvider` from jsonls. | FIXED (2026-08-01) |
| P1-05 | `nvim/lua/plugins/gitsigns.lua:7,9` | The only file under `nvim/` that fails `stylua --check`, and stylua is an active format-on-save formatter for it — so the next save adds a 12-line unrelated diff. Fix: `-- stylua: ignore` or commit the expansion. | FIXED (2026-08-01) |
| P1-06 | `install.linux.sh:339` + `:213-231` | Debian/Ubuntu ship nvim below the **0.11.2** LazyVim's pinned commit requires (Ubuntu 24.04 = 0.9.5, Debian 12 = 0.7.2). `install_tool` only tests existence, so it prints `✓`, never enters MISSING, the "too old" hint at `:481` is unreachable, and `verify_install` passes — then the editor config is unsupported. **This blocks C1 on Debian/Ubuntu outright.** ×2 | FIXED (2026-08-01) |
| P1-07 | `install.sh:40-64` | All 24 formulae in one `brew install` under `set -e`: one failure aborts before `finish_install`, so nothing is stowed, no terminfo, no TPM, no verification, **and no error banner** — the exact failure already fixed one screen below for casks (`:83-98`). ×2 | FIXED (2026-08-01) |
| P1-08 | `install.linux.sh:129` + `install.common.sh:65` | `sevenzip` → `p7zip` on dnf ships only `/usr/bin/7za`; `bin_name` looks for `7z`. Fedora prints `✓ p7zip` and yazi archive previews are silently dead. `p7zip` is gone entirely in f44+. Separately, brew ships `7zz`, so the `7z` mapping is wrong on macOS too (harmless — `verify_install` omits it). Fix: `dnf) echo "7zip"`. ×3 + caught by `check.sh` | FIXED (2026-08-01) |
| P1-09 | `install.linux.sh:266-278` | On aarch64 the asset picker selects zoxide's **Android** build: no aarch64 asset contains `gnu`, so `_pick 'gnu'` is empty and `head -1` takes the android one. Replayed against the live release list. Fix: exclude `android`. | FIXED (2026-08-01) |
| P1-10 | `install.linux.sh:391-398` vs `:518` | `chsh` runs **before** stow. If the stow step fails (e.g. AlmaLinux, where stow is EPEL-only and EPEL is never enabled), `set -e` kills the script with the login shell already switched → next login lands in `zsh-newuser-install`. | FIXED (2026-08-01) |
| P1-11 | `zsh/.zshrc:25,92` | Comments say the sesh picker is `Ctrl+a T`; the binding is `Ctrl+b T` (`tmux.conf:64`) — `Ctrl+a` is herdr's. Anyone following the comment gets herdr. ×2, and **`check.sh` gates this class now**. | FIXED (2026-08-01) |
| P1-12 | `atuin/config.toml:9` | The docs link `docs.atuin.sh/configuration/config/` is a 404; it moved to `/latest/`. This is the file's only pointer to authoritative key docs — which is *why* P1-13 went unnoticed. | FIXED (2026-08-01) |
| P1-13 | `atuin/config.toml:18-21` | `[sync] records = true` was deleted upstream in atuin 18.18.0 (commit `a7a7f921`, V1 sync protocol removal). Silently ignored, so the comment's stated guarantee is false. ×2 | FIXED (2026-08-01) |
| P1-14 | `install.linux.sh:124-137` | Fedora has no `ffmpeg` package (`ffmpeg-free`, which does not `Provides: ffmpeg`), and apt's `imagemagick` is IM6 with **no `magick` binary** — both print `✓`, neither enters MISSING, yazi previews silently off. | FIXED (2026-08-01) |
| P1-15 | `install.common.sh:112,155` | The submodule fetch and TPM clone are unguarded network calls inside `run_shared_tail`, which `finish_install:245` calls without `|| rc=1` — a captive network hard-aborts the script before stow/verification, contradicting this file's own stated design at `:238-242`. | FIXED (2026-08-01) |
| P1-16 | `install.linux.sh:249,287` vs `:340-341` | yazi's fallback asset is a `.zip` but `unzip` is installed eight entries later; `unzip`'s stderr is discarded so a 127 is invisible. yazi reports `✗ not available` even though the download succeeded. Works on a re-run, which is why it never showed up. | FIXED (2026-08-01) |
| P1-17 | `install.linux.sh:369` | `MISSING=("${MISSING[@]/mise}")` blanks the element instead of removing it, so the "install these manually" header prints with zero entries beneath it. | FIXED (2026-08-01) |

## P2 — gaps (works here, breaks elsewhere or on a fresh machine)

| ID | Location | Finding | Verdict |
|---|---|---|---|
| P2-01 | `install.linux.sh:338-342` | No Linux clipboard provider installed on any distro path, but `tmux.conf:83` (tmux-yank) and `keymaps.lua:20-27` both need one. `cheatsheet.md:267-273` documents all four as working. macOS has `pbcopy` built in, which is why it's invisible from here. Fix: add `wl-clipboard` + `xclip`. | FIXED (2026-08-01) |
| P2-02 | `install.linux.sh:339`, `:213-231` | fzf version floors used unguarded: `--zsh` needs 0.48 (`.zshrc:51`), `--color=selected-bg` needs 0.42 (`:41`). Ubuntu 22.04 ships 0.29 → *every* fzf call fails, taking out the sesh picker and `prefix+T`. No GitHub-release fallback for fzf. ×2 | FIXED (2026-08-01) |
| P2-03 | `install.linux.sh:213-231` | `atuin` has no release fallback and is unpackaged on every apt distro → history search silently absent. The header at `:29-32` omits it from the unpackaged list. | FIXED (2026-08-01) |
| P2-04 | `install.linux.sh:153-156` | RHEL/Rocky/AlmaLinux are advertised as supported with "verified" package names, but `stow`, `fzf`, `bat`, `fd`, `ripgrep`, `zoxide`, `atuin` are all **EPEL-only** and EPEL is never enabled. The stow step itself is unobtainable. | FIXED (2026-08-01) |
| P2-05 | `git/config:1-3`, README | The personal-vs-work identity split lives **only** in untracked `~/.gitconfig` + `~/.gitconfig-personal` and is documented nowhere (zero grep hits across README and all install scripts). On a fresh machine the first commit in `~/dotfiles` carries the work email. `~/.gitconfig` overrides `~/.config/git/config`, so the fix must stay in `~/.gitconfig` — document the snippet, don't move it. | FIXED (2026-08-01) |
| P2-06 | README | No documented update path after `git pull`. Concretely: the commit that made `jq`/`herdr` load-bearing and the one adding yazi's four preview backends both need a package step; a pull-only machine gets dead `wth`/`wthr` and no previews, with nothing saying re-running the installer is safe. `install.linux.sh:39` says so; `install.sh` doesn't. | FIXED (2026-08-01) |
| P2-07 | `install.sh:95-99` | Cask failures are deliberately non-fatal but never re-checked, so a failed Nerd Font install ends with `✓ all checks passed` and a tofu-filled prompt. Same hole on Linux at `:443-463`. | FIXED (2026-08-01) |
| P2-08 | `.gitignore:15-17` | On a fresh machine `~/.config/atuin` doesn't exist, so stow **folds** it into the repo — atuin then writes `TERMINAL.md` (its AI context file) *inside* `~/dotfiles/atuin/`, untracked and un-ignored, where `git add -A` will commit it. This machine is immune only because its atuin dir predates the stow run. | FIXED (2026-08-01) |
| P2-09 | `install.linux.sh:246-303` | The release fallback verifies nothing — no checksum, no signature — and `_pick`'s exclusion regex actively **discards** the sibling `checksums.txt`/`.sha256` assets rather than using them. | FIXED (2026-08-01) |
| P2-10 | `herdr/config.toml:9-10` | `previous_agent`/`next_agent` sit on herdr's own defaults for `swap_pane_up`/`swap_pane_down`, silently disabling both — there is now no binding to move a pane within a layout. herdr reports the collision itself; `herdr config check` is blind to explicit-vs-default conflicts (proven). | FIXED (2026-08-01) |
| P2-11 | `herdr/config.toml:11-12` | `navigate_workspace_up/down = k/j` collide with navigate-mode defaults `navigate_pane_up/down = k/j`; resolution is priority-based, not file-order. In navigate mode there is no key to move pane focus up or down. | FIXED (2026-08-01) |
| P2-12 | `tmux/tmux.conf:69` | The sesh picker binds `ctrl-a` inside fzf — the one `Ctrl+a` the "yield to herdr" commit missed. In the documented nesting (tmux inside a herdr pane) herdr swallows it and the next key fires a herdr action. herdr 0.7.5 exposes no passthrough. The header at `:67` still advertises `^a all`. | FIXED (2026-08-01) |
| P2-13 | `install.linux.sh:9` vs `:251-254` | Raspbian is listed as supported but `gh_release_install` bails on any arch that isn't x86_64/aarch64, so on 32-bit `armv7l` **eight** tools — including herdr, which `.zshrc` hard-depends on — have no fallback at all. | FIXED (2026-08-01) |
| P2-14 | `nvim/lua/config/keymaps.lua:17` | `<leader>d` (`"_d`) is both a complete mapping and a prefix of LazyVim's `<leader>dpp/dph/dps`, so with >300 ms between keys the profiler keys silently don't fire. Blast radius is only those three. | **ACCEPTED-RISK (2026-08-01)** — deleting lazy-registered keys at config time is unreliable, and `<leader>d` is the frequently-used mapping while the snacks profiler is not. Reopen only if the profiler is actually wanted. |

## P3 — dead config (behaviour-neutral to remove)

Each of these was verified against the tool's actual defaults, not assumed.

| ID | Location | Finding | Verdict |
|---|---|---|---|
| P3-01 | `.stowrc:2,5,8` | `README\.md`, `\.gitignore`, `\.gitmodules` restate stow's **built-in** ignore list (proven: they're skipped with no `--ignore` at all, and `--ignore` is additive). Worse, they cover only 3 of ~10 built-in patterns, so anyone later adding a `.stow-local-ignore` — which *replaces* the built-in list — will believe the list is complete and start stowing `.git` and `LICENSE`. | FIXED (2026-08-01) |
| P3-02 | `.gitignore:15-17` | `atuin/history.db` / `atuin/*.db` can never match: every atuin db path defaults to `data_dir`, and on disk they're in `~/.local/share/atuin/`. Replace with the rule from P2-08. | FIXED (2026-08-01) |
| P3-03 | `tmux/tmux.conf:4` | `default-terminal 'tmux-256color'` restates the default on tmux ≥3.1 (stock probe confirms). tmux-sensible can't downgrade it either — its guard compares against literal `screen`, which no tmux ≥3.1 reports. **Interaction:** don't remove this expecting it to fix P2's Debian terminfo gap — the entry is missing there regardless. | FIXED (2026-08-01) |
| P3-04 | `tmux/tmux.conf:92` | `@resurrect-strategy-nvim 'session'` can never activate: it needs a per-project `Session.vim`, and your nvim uses persistence.nvim (`~/.local/state/nvim/sessions/`, 34 files). Your own last resurrect save records nvim panes as bare `nvim`, never `nvim -S`. | FIXED (2026-08-01) |
| P3-05 | `nvim/lua/plugins/vtsls.lua:12` | `autoUseWorkspaceTsdk = true` restates LazyVim's vtsls extra (`vtsls.lua:37`). The whole `servers` block exists only to carry this dead key. | FIXED (2026-08-01) |
| P3-06 | `nvim/lua/plugins/markdown.lua:10` | `render_modes = { "n", "c", "t" }` is byte-for-byte the plugin default at the pinned commit. | FIXED (2026-08-01) |
| P3-07 | `nvim/lua/plugins/scrollbar.lua:17,18,20` | `cursor = true`, `diagnostic = true`, `search = false` restate defaults. Only `gitsigns = true` and `handle.blend = 0` are real. | FIXED (2026-08-01) |
| P3-08 | `nvim/lua/config/lazy.lua:34-42` | `defaults = { lazy = false, version = false }` restates lazy.nvim's defaults (starter boilerplate). The rest of the block — `checker.enabled`, `rtp.disabled_plugins`, `install.colorscheme` — is real and must stay. | FIXED (2026-08-01) |
| P3-09 | `nvim/stylua.toml:3` | `column_width = 120` restates stylua's default (verified byte-identical output). `indent_type`/`indent_width` are real. | FIXED (2026-08-01) |
| P3-10 | `install.sh:60`, `install.linux.sh:341,488` | `shellcheck` is installed by both installers and referenced by nothing in the repo; the hint's justification ("shell linting in nvim") is false — no `lang.sh` extra is enabled. Being a directly-used CLI for the install scripts is a fine reason; it's just not the stated one. | FIXED (2026-08-01) |
| P3-11 | `install.linux.sh:201` | The `*)` arm of `aur_install` is unreachable — `AUR` can only ever be `""`, `yay` or `paru`, and `""` returns earlier. | FIXED (2026-08-01) |
| P3-12 | `~/.config/config.toml` (deployed state) | Stray symlink → `../dotfiles/herdr/config.toml`, left by a superseded layout. Nothing reads it; stow will never clean it up because stow didn't create it. The real link at `~/.config/herdr/config.toml` is correct. `rm` it by hand. ×2 | FIXED (2026-08-01) |

## P4 — stale comments and docs

The code is right; the prose is wrong. Listed compactly because they're one edit
each, but they matter: these are what a future cleanup pass reasons *from*.

| ID | Location | Says | Reality |
|---|---|---|---|
| P4-01 | `cheatsheet.md:95` | `Ctrl+a k`/`j` = prev/next workspace | Those are navigate-mode-**local** keys; as a prefix chord they hit herdr's `focus_pane_up/down`. Real prefix actions are unset. |
| P4-02 | `cheatsheet.md:105` | Step 1: from a plain shell use `Ctrl+b T` | That's a tmux binding needing an attached client; outside tmux the path is the `s` function, as the same file says at `:45-46`. |
| P4-03 | `cheatsheet.md:75` | `wtr` with no arg removes the worktree you're near, from another session | Self-cancelling: no-arg resolves the *current* branch, which the cwd guard then always refuses. The row promises something that cannot succeed. |
| P4-04 | `cheatsheet.md:161` | `<leader>E` focuses the file explorer | It's LazyVim's `fE` — explorer rooted at **cwd** (vs `<leader>e` = root-dir). In a monorepo those differ, which is exactly your case. |
| P4-05 | `cheatsheet.md` Misc | — | `<leader>um` (toggle render-markdown, your own spec) is undocumented; it's the only repo-custom nvim mapping missing. |
| P4-06 | `README.md:149,153` | `install.sh` links herdr config / compiles terminfo | Both live in `install.common.sh`, as README `:106-109` itself correctly says. |
| P4-07 | `README.md:157` | `terminal-features ',*:usstyle'` | Actual line is `',*:RGB:usstyle'` — copying the quoted form drops true-colour. |
| P4-08 | `herdr/config.toml:25` | New worktree from herdr's UI is `prefix+n` | In 0.7.5 it's `prefix+shift+g`; `prefix+n` is `next_tab`. |
| P4-09 | `tmux/tmux.conf:21-23` | tmux defaults escape-time to 500 ms, sensible is the fallback | Since tmux 3.5 stock is **10 ms**, and sensible's 500 ms guard therefore never fires. The setting itself is still load-bearing (0 vs 10) — only the reasoning is wrong. |
| P4-10 | `git/config:12` | The Catppuccin syntax theme ships with bat ≥ 0.26 | delta bundles its own theme set and doesn't read bat's. Works, but for a different reason than stated. |
| P4-11 | `install.linux.sh:473` | yazi fallback: `cargo install yazi-fm yazi-cli` | Upstream now ships a single `yazi-build` crate; the split crates stopped at 26.5.6 while `yazi-build` is at 26.5.9. |
| P4-12 | `nvim/lua/plugins/gitsigns.lua:7` | — | `toggle_deleted()` is marked `@deprecated` upstream (`actions.lua:231`). Works today; with `checker.enabled = true`, a future bump that removes it makes `<leader>gtd` throw. LazyVim's `<leader>ghp` is the supported equivalent. |

## Informational — no action implied

- **Every tool is on the exact latest upstream release** (23 checked against live
  sources on 2026-08-01), the catppuccin submodule is on the latest tag, and all
  38 nvim pins point at live, unrenamed repos. 30 of 38 are at upstream HEAD.
  `blink.cmp` looks "211 behind main" but is at the newest **v1** tag, which is
  what LazyVim's semver constraint asks for — not stale.
- **The four tmux plugins are dormant**: tmux-sensible (last code commit
  2022-08), tmux-resurrect (2023-03), tmux-yank (2023-07), tmux-continuum
  (2024-01). All work on 3.7b. Worth knowing because `_wt_resurrect_save`
  (`zsh/.zshrc:223-228`) reaches directly into tmux-resurrect's `save.sh`, so a
  future tmux change would surface as a worktree-teardown bug, not an obvious
  plugin failure. tpm itself is active.
- **The undercurl chain works end to end**, measured rather than inspected: the
  vendored terminfo's concrete payoff over stock `xterm-256color` is the coloured
  underline (`ESC[58:2`), which stock lacks entirely.
- `zsh -i -c exit` emits `can't change option: zle` from fzf's integration when
  there's **no tty**. It is a probe artefact, not a fault — under a real pty
  startup is silent. `check.sh` handles this; don't "fix" it.

---

# Found while fixing (2026-08-01)

Remediation surfaced its own findings. They are recorded here because two of them
demonstrate the drift mechanism this whole file exists to stop.

| ID | Finding | Verdict |
|---|---|---|
| F-01 | **A fix created a stale doc.** Restricting `install.linux.sh` to 64-bit made `README.md:70`'s distro table — which had been verified as matching that header exactly — wrong, still advertising Raspbian. Caught only by an explicit cross-file check after the edits. | FIXED (2026-08-01) — README now carries the 64-bit-only paragraph |
| F-02 | **`check.sh` assumed `.stowrc` was the whole ignore list.** It is not: stow has a BUILT-IN list (`.git`, `README.*`, `LICENSE.*`, `*~`) that `--ignore` only adds to. So deleting three correctly-redundant `--ignore` lines (P3-01) made the gate report `README.md` as an undeployed package. Now derived by asking stow itself — a dry run into a pristine empty target — which cannot drift from stow. | FIXED (2026-08-01) |
| F-03 | **`check.sh` reported a clean pass over an empty set.** When `install.sh`'s `brew install \` block became a `_formulae=()` array (P1-07), the awk pattern matched nothing and the check announced "all 0 derived formulae resolve". A textbook SILENT-SUCCESS, in the gate written to catch them. Both derivations now hard-fail when they return nothing. A second bug in the same line — `tr -d '[:space:]'` eating newlines, collapsing 24 formulae into one token — was caught the same way. | FIXED (2026-08-01) |
| F-04 | **The prescribed fix for P1-04 was insufficient.** Clearing jsonls' `documentFormattingProvider` alone would not have worked: `LazyVim.lsp.formatter` accepts a client advertising `textDocument/formatting` **or** `rangeFormatting`, and jsonls advertises both. Both are now cleared. Recorded as the standing reminder that a finding and its proposed remedy are two separate claims, and the remedy usually got less scrutiny. | FIXED (2026-08-01) |
| F-05 | `install.common.sh`'s new `have_tool` and `install.linux.sh`'s new `tool_ok`/`alt_bins` overlap conceptually — both answer "is this tool really present". They were written by separate passes that could not safely edit each other's file. Qualifies under improvement criterion 2 (duplicate logic that can drift). | **FIXED (2026-08-01)** — one `tool_bins` table in `install.common.sh` now holds every binary name a tool may answer to; `bin_name` returns the primary (still one name, since the Linux release fallback consumes it as a literal filename) and `have_tool` accepts any. `tool_bin` and `alt_bins` deleted. Note the primary for `sevenzip` is now `7zz`, which is inert: `$bin` is only consulted for tools with a version floor, sevenzip has none and no release fallback |
| F-06 | `nvim/lua/plugins/vtsls.lua` no longer contains any vtsls configuration after P3-05; it holds only the editor-wide `inlay_hints` override, so the filename now misleads. Qualifies only weakly — the cost is future reader confusion, nothing breaks. | **FIXED (2026-08-01)** — renamed to `lsp.lua`; `inlay_hints.enabled=false` and formatting.lua's `setup.jsonls` both re-probed as still in effect |
| F-07 | The sesh picker's "all" filter moved to `ctrl-s`, which terminals with `ixon` can intercept as XOFF. fzf puts the terminal in raw mode so it should not bite. | ACCEPTED-RISK (2026-08-01) — if that filter ever feels dead, this is the first thing to check |
| F-08 | yazi's four preview backends are now verified, but as a **warning** rather than a failure when simply absent. Making them fatal would newly break machines that never had them; a backend that *fails to install during a run* is still a hard `✗`. | ACCEPTED-RISK (2026-08-01) — deliberate asymmetry |
| F-09 | The stray `~/.config/config.toml` symlink (P3-12) is removed by code in `install.common.sh` but still exists on this machine — the cleanup runs on the next `./install.sh`. Left deliberately: letting the installer do it is also the end-to-end proof the new block works. | FIXED in code (2026-08-01) — clears on next install run |

# Found by container testing (2026-08-01)

Running `install.linux.sh` end-to-end in clean Arch, Debian and Fedora containers
found three defects that no amount of static review had. All three were fixed in
`823beef`, `78cad97` and `d134098`; reviewing those commits then found a fourth.

Two of the three were **invisible on the development machine**, which is the same
lesson as P2-08 and F-01 arriving by a third route.

| ID | Finding | Verdict |
|---|---|---|
| F-10 | **Every interactive zsh exited 1.** `zsh/.zshrc` ended with `[ -f ~/.zshrc.local ] && source …`, and being the last line its status became the file's. `~/.zshrc.local` is untracked and absent on most machines, so the test failed, `&&` short-circuited, and `zsh -i -c exit` returned 1 on a completely healthy shell — breaking anything that checks whether startup succeeded, `check.sh`'s C2 among them. Invisible here because this machine *has* that file. | FIXED `823beef` — `if` form, which returns 0 when the file is simply absent while still propagating a real failure from inside it |
| F-11 | **`check.sh`'s own timeout wrapper could never work.** `guarded 30 in_pty …` ran `timeout(1)` — an external binary — with a shell function as its command, which it cannot execve, so it died with 127 and C2 reported "zsh -i exited 127" regardless of what `.zshrc` did. Invisible on macOS, which ships no `timeout`, so the broken branch never ran; it fired on every container. | FIXED `78cad97` for C2 — timeout moved inside the pty, where `script` runs it through `sh` |
| F-12 | **An exhausted GitHub API quota was reported as "no repo has this tool".** `curl -f` collapsed every non-2xx into one silent failure, so a rate-limited run listed eight tools as unavailable and sent the user hand-installing things that would have worked an hour later. The release fallback spends one request per unpackaged tool, so a Debian or Fedora run costs ~8 of the 60/hour an unauthenticated IP gets. A textbook SILENT-SUCCESS inversion — a transient condition presented as a permanent one. | FIXED `d134098` — status captured alongside the body, 403/429 identified as rate limiting and said so before the manual list, and a token used when `GITHUB_TOKEN`/`GH_TOKEN`/authenticated `gh` can supply one |
| F-13 | **F-11's fix was incomplete.** The same `guarded … in_pty` construct survived in `check.sh`'s nvim pty probe. Because that path is opt-in it was never exercised — and it fails worse than C2 did: `timeout` returns **127**, the code special-cased only 124, so it fell through to the success branch and grepped an empty file, reporting "nvim loads without errors" for a probe that never started. A false pass. | **FIXED (2026-08-01)** — timeout built into the probe's own argv, a `PROBE-COMPLETED` sentinel added (`:messages` is legitimately empty on a healthy config, so emptiness could not distinguish "nothing to report" from "never ran"), an unexpected status is now a failure, and the now-callerless `guarded` helper deleted |
| F-14 | The nvim pty probe failed 3/3 immediately after a batch of killed/orphaned nvim processes, then passed 8/8 from a clean state. Dirty prior TUI state, not a config fault. | ACCEPTED-RISK (2026-08-01) — the probe stays opt-in, and F-13's sentinel means a non-completion is now reported honestly instead of passing silently |
| F-15 | The GitHub token is passed as `-H "Authorization: Bearer …"`, so it appears in the process argument list and is readable from `/proc/<pid>/cmdline` by other local users. Real mechanism, negligible impact on a single-user machine; `curl --config -` would keep it off argv. | OPEN (low) — recorded rather than fixed, because by this file's own improvement criteria the cost today is nil |

**Review verdict on the three pushed commits: correct.** Each diagnosis matches the
mechanism, each fix is minimal, and the empty-array expansion in `d134098`
(`${GH_API_AUTH[@]+"${GH_API_AUTH[@]}"}`) is the right `set -u`-safe idiom. Dropping
`-f` to capture the status is necessary and the 200/403/429/other split is correct.
The only gaps were F-13 (the incomplete fix) and F-15 (low).

## How these were verified

Not by reading. Per group:

- **Worktree helpers** — scratch git repo with a real `origin`. The control shows
  plain `git branch -d` deleting an open-PR branch with **exit 0**; the fix keeps
  it while still deleting a genuinely merged one.
- **atuin `[ai]`** — key names read out of v18.18.1's `settings.rs` before writing,
  because a deliberate typo in the same section was confirmed to **also parse
  cleanly**. "atuin accepts it" proves nothing here.
- **herdr bindings** — control config with the four colliding defaults spelled out
  reproduces all four `kept … disabled …` lines; the fixed config produces none.
- **`.stowrc`** — the stow plan was diffed with and against the three deleted
  `--ignore` args restored: identical, proving they were no-ops.
- **nvim dead config** — each deleted key's runtime value re-probed after deletion
  and confirmed unchanged. `column_width` was boundary-tested at 105/118/120/121/130
  rather than trusted from docs.
- **macOS package step** — exercised with a **stubbed** `brew`; real brew never
  invoked. The `~/.config/config.toml` cleanup was run against sandboxed fake
  `$HOME`s covering six link shapes, including leaving a dangling link alone.
- **Linux script** — the new pure logic extracted and run offline: `version_ge`
  across 14 cases, the asset picker against real release listings on both arches,
  checksum discovery across four manifest shapes, `install_tool` routing under
  mocked package managers across 12 scenarios.

# Criteria

The standing request that produced this file was "check for improvements, errors,
missing packages". Those are three different questions with three different
evidence bars, and conflating them is what makes a review feel endless — an
improvement judged by an error's bar looks urgent, and an error judged by an
improvement's bar looks optional. One section each.

## Error criteria

An error is a defect with an **observable wrong outcome**. Classify every one,
because the class sets the priority far more than the component does:

| Class | Test | Priority |
|---|---|---|
| **DATA-LOSS** | Can destroy uncommitted or unpushed work | Always first, regardless of how narrow the trigger |
| **SILENT-SUCCESS** | Produces a wrong outcome *while reporting success* | Second, regardless of blast radius |
| **BROKEN** | Fails today on a machine in scope | By blast radius |
| **LATENT** | Correct today; fails on a state the setup will reach | By how certainly it'll be reached |

**SILENT-SUCCESS deserves its own tier** and it is the class this repo produced
most of. An install that prints `✓` for a package that didn't land, a `wtr` that
says `✓ deleted branch` while destroying an open PR's work, a `verify_install`
that reports "all checks passed" with no font — each removes the only feedback
loop that would ever have caught it. A loud failure gets fixed the day it
happens; a silent one survives every future review too.

**Evidence bar.** Every error needs: `file:line`, the input or state that triggers
it, and the specific wrong outcome. Prefer execution proof over reading — a
scratch git repo, a throwaway tmux socket (`-L`), an isolated config dir
(`ATUIN_CONFIG_DIR=…`). Any claim about a tool's behaviour must be checked against
the **installed version**, never from memory.

**Not an error:** something that merely violates a preference; something that
fails only in a state this setup cannot reach; anything whose sole justification
is "this looks fragile". And before reporting, rule out the harness — see
*Validate the probe* in the `code-review` skill; five findings in the 2026-08-01
review were manufactured by the measuring apparatus, not present in the repo.

## Missing-package criteria

A package is missing only if **something in the repo requires it**. This is a
closure test and it must run in **both** directions:

| Direction | Verdict | Rule |
|---|---|---|
| Required by a config, installed by no path | **GAP** | Must cite the config line that invokes the binary. No citation, no finding. |
| Installed, referenced by nothing | **DEAD** | Unless it's a standalone CLI run by hand (`bat`, `jq`, `gh`, `shellcheck`) — those are legitimate; don't report them, but do check the *stated reason* is true. |
| Installed under a name that doesn't ship the binary | **BROKEN** | Highest-yield check in the whole review. |
| Installed but below the version a config's feature needs | **GAP (version floor)** | An existence check passes and the config still doesn't work. |
| Free on one OS, absent on another | **PLATFORM** | The daily driver hides these entirely. |

**Package name ≠ binary name, and it varies per distro.** Verify against the
distro's *file list*, not its description: `p7zip` on Fedora ships `7za` not `7z`;
apt's `imagemagick` is IM6 with no `magick` at all; Homebrew's `sevenzip` ships
`7zz`. Every one of those printed `✓` and delivered nothing.

**Check the version floor wherever a config uses a versioned feature.** `fzf --zsh`
needs 0.48, `--color=selected-bg` needs 0.42, this LazyVim pin needs nvim 0.11.2.
An installer that tests only `command -v` will pass all three on a distro that
satisfies none of them.

**Out of scope, permanently:** language runtimes (they come from `mise`,
per-machine, deliberately untracked), Rust (rustup), and anything in the untracked
`install.local.sh`. The absence of a nice-to-have tool is never a finding — only a
broken dependency is.

## Improvement criteria

For the judgement half of a review — "could this be simpler or done better?" —
an improvement must satisfy **at least one** of these, with evidence:

1. **Restates a default.** Provable by diffing against the tool's own defaults
   dump. Deleting it is behaviour-neutral. (Zero-risk; this is the whole P3
   section.)
2. **Duplicate logic that can drift.** The same behaviour in two places, where
   fixing one and not the other is possible — ideally where it has *already*
   happened. (`install.common.sh` exists because of exactly this.)
3. **Workaround density.** Config that undoes a default or referees a conflict
   between things a framework bundled. Count **lines, not files**, and only count
   what would **disappear** on migration.
4. **Unreachable under any real input.** Provable by tracing conditions.
5. **Hand-rolled where an installed dependency already does it.** (`wtclean` →
   `gh poi` was this.)
6. **Measured cost with no observed benefit.** Needs numbers, not intuition.

And the rule that does the most work — **an improvement must name what breaks or
costs *today*.** If the answer is "nothing, it would just be nicer", it is not a
finding. Record it here as taste with a verdict and never raise it again.

**Never counts as a finding:** tool or plugin recommendations; aesthetic
reorganisation; "there's a more modern alternative to X"; adding CI, tests, or a
Makefile without naming a concrete failure it would have caught; hypothetical
portability for a platform you don't run.

**Simplification has a higher bar than it looks.** A simplification must be
behaviour-preserving and *demonstrably* so. If equivalence can't be shown, it's
a redesign, and redesigns need a reason beyond elegance.
