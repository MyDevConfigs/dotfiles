# AGENTS.md

Instructions for AI agents working in this repository. Read this before
changing anything.

`CLAUDE.md` is a symlink to this file.

---

## What this repository is

Configuration files, deployed into `$HOME` with GNU Stow.

**It is not the `setup` repository.** That one installs software; this one
deploys config. Keep the boundary sharp:

| This repo (`dotfiles`) | The `setup` repo |
| --- | --- |
| Deploys *configuration* | Installs *software* |
| Symlinks into `~` and `~/.config` | `apt`, `rustup`, cargo, release tarballs |
| Tracked and edited continuously | Runs once per machine |

If a change is about *installing a program*, it belongs in `setup`. If it is
about *what a program reads once installed*, it belongs here.

The one deliberate overlap is the shell rc file. `setup` appends `PATH` and
environment lines to `~/.zshrc` through its `lib/shell.sh`. If `.zshrc` is
ever stowed from this repo, that file becomes a symlink into here and
`setup` will be writing into this repository — which works, but is worth
being deliberate about rather than discovering later.

---

## Hard requirements

### Never clobber

Stow refuses to overwrite a real file, and that refusal is the safety
property this repo depends on. Do not work around a conflict by deleting the
existing file — a conflict means something is already there that nobody
decided to replace.

The correct order is always **move, then stow**:

```bash
mkdir -p ~/dotfiles/<pkg>/.config
mv ~/.config/<pkg> ~/dotfiles/<pkg>/.config/
cd ~/dotfiles && stow <pkg>
```

### Individual-file packages need `--no-folding`

A package that tracks only some files inside a directory must be stowed with
`--no-folding`. Stow's default is to link a whole directory when the target
does not exist, which means a new file created there would silently land
inside this repo. `--no-folding` forces real directories and leaf-file links,
so the behaviour never depends on what happens to exist at the time.

Use the same flag on every stow *and* restow of that package, or the
behaviour reverts.

### Nothing generated, nothing secret

No caches, no build output, no wallpaper renders, no tokens, no SSH keys.
This repo is expected to become public or at least shared; treat everything
in it as readable by anyone.

Machine-specific values deserve a moment's thought before being tracked — a
monitor layout or a credential-helper path is real config, but it is config
that will be wrong on the next machine.

---

## Conventions

- **One package per tool**, named after the tool, containing the full path
  relative to `$HOME`: `kitty/.config/kitty/`, `zsh/.zshrc`.
- **Prefer whole-directory packages.** Reach for individual files only when
  layering edits on top of someone else's config, where tracking the whole
  directory would mean owning their work too.
- **Test with `stow -n -v <pkg>` before stowing.** Every time.
- Config that is *itself* a git repository cannot simply be moved in —
  nesting repos produces a gitlink that clones will not populate. Either add
  it as a submodule, or leave it out and let `setup` clone it.

---

## Working with the user

### Git

**The user creates repositories and links remotes himself.** Do not run
`git init`, `git remote add`, `gh repo create`, or `git push`. Create the
directory and files; stop there and report.

**Commit only when asked.** Use conventional commits (`feat:`, `fix:`,
`chore:`, `docs:`) with a scope. Split genuinely unrelated changes into
separate commits.

### Process

The user prefers to **discuss a design before it is written**, and to guide
multi-step work one step at a time. When a request has real forks in it,
raise them and ask rather than scaffolding everything and asking forgiveness.

Do not move files out of `~/.config` or change system state that was not
asked for.

---

## Verifying a change

```bash
cd ~/dotfiles
stow -n -v <pkg>              # what would it link?
ls -l ~/.config/<pkg>         # is the link there and pointing here?
readlink -f ~/.config/<pkg>   # does it resolve to a real path?
```

A stow that reports nothing has nothing to do. A stow that reports
`WARNING! stowing <pkg> would cause conflicts` means a real file is in the
way — find out what it is before touching it.
