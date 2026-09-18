#!/usr/bin/env bash
set -euo pipefail

repo="pingdotgg/t3code"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

api() {
  local url="$1"
  local args=(-fsSL -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
  curl "${args[@]}" "$url"
}

to_sri() {
  nix hash to-sri --type sha256 "$1"
}

release_json="$(api "https://api.github.com/repos/${repo}/releases/latest")"
releases_json="$(api "https://api.github.com/repos/${repo}/releases?per_page=100")"
nightly_json="$(jq -c '[.[] | select(.prerelease and (.tag_name | contains("-nightly.")))] | sort_by(.published_at) | last' <<<"$releases_json")"

if [[ "$nightly_json" == "null" ]]; then
  echo "No nightly release found" >&2
  exit 1
fi

release_entry() {
  local json="$1"
  local tag version
  tag="$(jq -r .tag_name <<<"$json")"
  version="${tag#v}"

  jq -n \
    --arg tag "$tag" \
    --arg version "$version" \
    --arg x86_64_linux "$(to_sri "$(jq -r --arg name "T3-Code-${version}-x86_64.AppImage" '.assets[] | select(.name == $name) | .digest | sub("^sha256:"; "")' <<<"$json")")" \
    --arg aarch64_linux "$(to_sri "$(jq -r --arg name "T3-Code-${version}-arm64.AppImage" '.assets[] | select(.name == $name) | .digest | sub("^sha256:"; "")' <<<"$json")")" \
    --arg x86_64_darwin "$(to_sri "$(jq -r --arg name "T3-Code-${version}-x64.zip" '.assets[] | select(.name == $name) | .digest | sub("^sha256:"; "")' <<<"$json")")" \
    --arg aarch64_darwin "$(to_sri "$(jq -r --arg name "T3-Code-${version}-arm64.zip" '.assets[] | select(.name == $name) | .digest | sub("^sha256:"; "")' <<<"$json")")" \
    '{tag: $tag, version: $version, hashes: {"x86_64-linux": $x86_64_linux, "aarch64-linux": $aarch64_linux, "x86_64-darwin": $x86_64_darwin, "aarch64-darwin": $aarch64_darwin}}'
}

jq -n \
  --argjson latest "$(release_entry "$release_json")" \
  --argjson nightly "$(release_entry "$nightly_json")" \
  '{latest: $latest, nightly: $nightly}' >"$tmp"

if cmp -s "$tmp" "$root/versions.json"; then
  echo "T3 Code packages are up to date"
  exit 0
fi

mv "$tmp" "$root/versions.json"
echo "Updated latest to $(jq -r .latest.tag "$root/versions.json")"
echo "Updated nightly to $(jq -r .nightly.tag "$root/versions.json")"
