#!/usr/bin/env bash
#
# Nerd Font icon for the program running in a pane.
#
# Called from window-status-format as:
#     #(~/.config/tmux/scripts/app-icon.sh #{pane_current_command})
#
# A script rather than a chain of nested #{?...} conditionals in the config.
# Eight applications would mean eight levels of nesting on a single
# unreadable line, and adding a ninth would mean rebuilding it. tmux caches
# #() output per distinct command string, so the cost is one short-lived
# process per running program per status interval.
#
# Everything here is a pure bash case with no forks, so that process is
# about as cheap as a process gets.

set -o nounset

readonly CMD="${1:-}"

case "${CMD,,}" in
    nvim | vim | vi)              printf '' ;;   # neovim
    node | npm | npx | pnpm | yarn | bun)
                                  printf '' ;;   # node
    python* | py | ipython | uv)  printf '' ;;   # python
    cargo | rustc | rust*)        printf '' ;;   # rust
    go | gopls)                   printf '' ;;   # go
    dotnet)                       printf '' ;;   # dotnet
    java | gradle | kotlin)       printf '' ;;   # jvm
    docker | podman | lazydocker) printf '' ;;   # container
    git | lazygit | gitui)        printf '' ;;   # git
    ssh | mosh)                   printf '' ;;   # remote
    htop | btop | top)            printf '' ;;   # monitor
    yazi | ranger | lf)           printf '' ;;   # file manager
    man | less | bat | batcat)    printf '' ;;   # reading
    psql | mysql | sqlite3)       printf '' ;;   # database
    zsh | bash | sh | fish)       printf '' ;;   # shell
    *)                            printf '' ;;   # anything else
esac
