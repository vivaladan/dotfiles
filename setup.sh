#!/bin/bash
set -e

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

link_file() {
  local src="$1"
  local dest="$2"

  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    echo "Already linked $dest → $src"
    return
  fi

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    local backup="$dest-backup-$(date +%Y%m%d%H%M%S)"
    mv "$dest" "$backup"
    echo "Backed up $dest → $backup"
  fi

  ln -s "$src" "$dest"
  echo "Linked $dest → $src"
}

link_file "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"
