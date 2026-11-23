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

# T3 Code renames its release assets from time to time (v0.1.11 dropped the
# version from the AppImage names and nightly AppImages use "Nightly"
# instead of the version), so resolve assets by name pattern instead of
# constructing exact names. The exact asset name is stored in versions.json
# and used verbatim when building download URLs.
asset_patterns=(
  "x86_64-linux|^T3-Code-.*x86_64[.]AppImage$"
  "aarch64-linux|^T3-Code-.*arm64[.]AppImage$"
  "aarch64-darwin|^T3-Code-.*arm64[.]zip$"
)

release_entry() {
  local json="$1"
  local tag version
  tag="$(jq -r .tag_name <<<"$json")"
  version="${tag#v}"

  local system pattern match name digest sri
  local table=""
  for spec in "${asset_patterns[@]}"; do
    system="${spec%%|*}"
    pattern="${spec#*|}"
    match="$(jq -r --arg pattern "$pattern" '
      [.assets[] | select(.name | test($pattern))]
      | if length == 1 then (.[0] | [.name, .digest]) | @tsv else empty end
    ' <<<"$json")"
    if [[ -z "$match" ]]; then
      echo "error: release $tag has no unique asset for $system (pattern: $pattern)" >&2
      return 1
    fi
    name="${match%%$'\t'*}"
    digest="${match#*$'\t'}"
    digest="${digest#sha256:}"
    if [[ ! "$digest" =~ ^[[:xdigit:]]{64}$ ]]; then
      echo "error: asset $name of release $tag is missing a sha256 digest" >&2
      return 1
    fi
    sri="$(to_sri "$digest")"
    table+="${system}"$'\t'"${name}"$'\t'"${sri}"$'\n'
  done

  jq -Rn \
    --arg tag "$tag" \
    --arg version "$version" \
    --arg table "$table" '
    $table | split("\n") | map(select(length > 0) | split("\t"))
    | reduce .[] as [$system, $name, $hash]
        ({tag: $tag, version: $version}; .assets[$system] = {name: $name, hash: $hash})
  '
}

release_json="$(api "https://api.github.com/repos/${repo}/releases/latest")"
releases_json="$(api "https://api.github.com/repos/${repo}/releases?per_page=100")"
nightly_json="$(jq -c '[.[] | select(.prerelease and (.tag_name | contains("-nightly.")))] | sort_by(.published_at) | last' <<<"$releases_json")"

if [[ "$nightly_json" == "null" ]]; then
  echo "No nightly release found" >&2
  exit 1
fi

latest_entry="$(release_entry "$release_json")"
nightly_entry="$(release_entry "$nightly_json")"

jq -n \
  --argjson latest "$latest_entry" \
  --argjson nightly "$nightly_entry" \
  '{latest: $latest, nightly: $nightly}' >"$tmp"

if cmp -s "$tmp" "$root/versions.json"; then
  echo "T3 Code packages are up to date"
  exit 0
fi

mv "$tmp" "$root/versions.json"
echo "Updated latest to $(jq -r .latest.tag "$root/versions.json")"
echo "Updated nightly to $(jq -r .nightly.tag "$root/versions.json")"
