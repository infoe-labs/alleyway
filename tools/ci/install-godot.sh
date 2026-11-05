#!/usr/bin/env bash
set -euo pipefail

version="${1:?Godot version required}"
cache_dir="${2:?Cache directory required}"
template_dir="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${version}.stable"
mkdir -p "$cache_dir" "$template_dir"

if [[ ! -x "$cache_dir/godot" || ! -f "$cache_dir/templates/web_nothreads_release.zip" ]]; then
  download_dir="$(mktemp -d)"
  trap 'rm -rf "$download_dir"' EXIT
  base_url="https://github.com/godotengine/godot/releases/download/${version}-stable"
  engine="Godot_v${version}-stable_linux.x86_64.zip"
  templates="Godot_v${version}-stable_export_templates.tpz"
  for asset in SHA512-SUMS.txt "$engine" "$templates"; do
    curl --fail --location --retry 3 --max-time 600 "$base_url/$asset" -o "$download_dir/$asset"
  done
  (
    cd "$download_dir"
    for asset in "$engine" "$templates"; do
      awk -v asset="$asset" '$2 == asset || $2 == "*" asset { print; found=1 } END { if (!found) exit 1 }' SHA512-SUMS.txt > expected.sha512
      sha512sum --check expected.sha512
    done
    unzip -q "$engine" -d engine
    unzip -q "$templates" 'templates/web_*' 'templates/version.txt' -d web
  )
  install -m 755 "$download_dir/engine/Godot_v${version}-stable_linux.x86_64" "$cache_dir/godot"
  mkdir -p "$cache_dir/templates"
  cp "$download_dir/web/templates/"* "$cache_dir/templates/"
fi
cp "$cache_dir/templates/"* "$template_dir/"
"$cache_dir/godot" --headless --version
if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "$cache_dir" >> "$GITHUB_PATH"
fi
