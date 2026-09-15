#!/bin/bash
set -eu

source_file=$(cd "$(dirname "$0")" && pwd)/macssh
target_dir="${PREFIX:-/usr/local}/bin"
target_file="$target_dir/macssh"

if [ ! -d "$target_dir" ]; then
  mkdir -p "$target_dir" 2>/dev/null || {
    printf 'Cannot create %s. Try:\n  sudo PREFIX=%s ./install.sh\n' "$target_dir" "${PREFIX:-/usr/local}" >&2
    exit 1
  }
fi

cp "$source_file" "$target_file"
chmod 755 "$target_file"
printf 'Installed macssh to %s\n' "$target_file"
printf 'Run: macssh add\n'
