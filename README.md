# dotfiles

Configuration files, deployed with [GNU Stow](https://www.gnu.org/software/stow/).

Software is **not** installed here — that lives in a separate `setup` repo.
This one deploys config; that one installs the programs the config is for.

---

## How it works

Stow does one thing: it reads a subdirectory (a **package**) and recreates
that package's internal tree as symlinks in the directory *one level above*
the repo. Since this repo sits at `~/dotfiles`, one level above is `~` — so
the folder structure inside each package **is** its path relative to your
home directory.

```
~/dotfiles/kitty/.config/kitty/kitty.conf
                └─────────────┬────────┘
                              │  stow kitty
                              ▼
~/.config/kitty  ->  ../dotfiles/kitty/.config/kitty
```

Kitty still opens `~/.config/kitty/kitty.conf`. The kernel follows the link
and hands it the file in this repo. Nothing else in `~/.config` is touched,
which is what makes this safe: **anything not moved in here is invisible to
git**, so there is no long ignore list to maintain.

---

## Usage

```bash
task sync DRY=1    # preview — prints what it would link, changes nothing
task sync          # link every package into $HOME
```

`task sync` restows everything, so it both links new packages and repairs
links after files move inside an existing one. Task runs from this
directory regardless of where you invoke it from.

The one thing it cannot do is clean up after a package you *delete* — the
glob only sees directories that still exist. Run `stow -D <package>` before
removing one.

Underneath it is plain stow, which is worth knowing for one-off work:

```bash
stow -n -v <package>    # dry run on a single package
stow <package>          # link it
stow -D <package>       # unlink; files stay safe in the repo
stow -R <package>       # relink, after restructuring a package
```

Get in the habit of `-n` first. Stow refuses to overwrite a real file, which
is the safety property this all rests on — a conflict means something is
already there, not that stow is broken.

### On a new machine

```bash
git clone <this-repo> ~/dotfiles
cd ~/dotfiles && stow */
```

---

## Two kinds of package

| Style | Move in | Result |
| --- | --- | --- |
| **Whole directory** | the entire folder | One symlink. Everything inside is tracked, including files added later. |
| **Individual files** | only the files you edited | The real directory stays in place, untracked. Only your files become links. |

Whole-directory for config you own outright. Individual files when you are
layering your own edits on top of someone else's setup — a distro's rice, a
starter config — and want to track only your deltas.

For an individual-file package, use `--no-folding`:

```bash
stow --no-folding <package>
```

Without it, stow links a whole directory whenever the target does not yet
exist, and any new file you create there silently lands inside this repo.
`--no-folding` makes it always create real directories and link only leaf
files, so the behaviour never depends on what happens to exist.

---

## What belongs here

| Here | Not here |
| --- | --- |
| Config you hand-edit | Anything a package manager owns |
| `~/.config/<tool>/…`, `~/.zshrc`, `~/.gitconfig` | Installed programs — see the `setup` repo |
| Files you would miss on a new machine | Caches, generated assets, credentials, tokens |

Machine-specific values (a monitor layout, a credential helper path) are
worth thinking about before tracking. They are still config, but they are
config that is wrong on the next machine.

---

## Layout

```
dotfiles/
├── README.md
├── AGENTS.md        conventions (CLAUDE.md is a symlink to it)
├── Taskfile.yml     `task sync`
├── .gitignore
└── <package>/       one per tool, added as configs migrate
```

### Packages

| Package | Deploys |
| --- | --- |
| `lazygit` | `~/.config/lazygit/` — delta as diff renderer, Nerd Font icons, gruvbox theme |
| `tmux` | `~/.config/tmux/` — flat gruvbox bar on top (design after [tmux-dotbar](https://github.com/vaaleyard/tmux-dotbar)), tpm plugins, popups |

Neovim is deliberately **not** here. It lives in its own repository and is
cloned separately.

#### tmux, on a new machine

tpm is not vendored — plugin checkouts are gitignored, since they are
third-party repositories rather than configuration. After `task sync`:

```bash
task setup                 # clones tpm and installs every plugin
```

`setup` depends on `sync`, and that ordering matters: tpm has to be cloned
into `~/.config/tmux/plugins`, which only resolves into this repo once
`sync` has made `~/.config/tmux` a symlink.

`prefix` is `C-b`. Reload the config with `prefix + r` — deliberately not
`C-r`, which belongs to atuin's history search.

`vim-tmux-navigator` is half of a pair. Seamless `C-h/j/k/l` between tmux
panes and neovim splits also needs the plugin of the same name installed on
the neovim side, which lives in its own repo.
