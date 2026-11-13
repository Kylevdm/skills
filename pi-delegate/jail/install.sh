#!/usr/bin/env bash
# Install pi-jail, its pi guard extensions and the protect lists from this directory.
#
#   pi-delegate/jail/install.sh [--force]
#
# Copies (never symlinks: the jail mounts a tmpfs over /home, so links into this
# repo would dangle inside it). An existing file that differs is left alone and
# reported unless --force is given. Never touches pi's auth, settings or models.
set -euo pipefail

SRC=$(cd "$(dirname "$0")" && pwd)
FORCE=0; [ "${1:-}" = "--force" ] && FORCE=1

command -v bwrap >/dev/null || { echo "install: bubblewrap missing (apt install bubblewrap)" >&2; exit 1; }
[ -x "$HOME/.pi/agent/bin/pi" ] || { echo "install: pi not found at ~/.pi/agent/bin/pi" >&2; exit 1; }

drift=0
put() { # src dest mode
  mkdir -p "$(dirname "$2")"
  if [ -e "$2" ] && ! cmp -s "$1" "$2"; then
    if [ $FORCE -eq 0 ]; then echo "differs, kept: $2"; drift=1; return; fi
    echo "overwrote: $2"
  elif [ -e "$2" ]; then echo "up to date: $2"; return
  else echo "installed: $2"; fi
  install -m "$3" "$1" "$2"
}

put "$SRC/pi-jail" "$HOME/.local/bin/pi-jail" 755
for f in "$SRC"/extensions/*.ts; do put "$f" "$HOME/.pi/agent/extensions/$(basename "$f")" 644; done
for f in "$SRC"/protect/*; do put "$f" "$HOME/.config/pi-jail/protect/$(basename "$f")" 644; done

[ $drift -eq 0 ] || echo "install: some files differ; diff them, then rerun with --force to take this repo's copy" >&2
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "note: add ~/.local/bin to PATH" ;; esac
exit $drift
