#!/usr/bin/env bash
# Prints the modules/herdr builtin_checksums entry for a herdr release, from
# the SHA-256 digests GitHub records for its assets. Needs gh.
#   ./scripts/herdr-checksums.sh 0.9.4
set -euo pipefail
version=${1:?usage: $0 <version, e.g. 0.9.4>}
version=${version#v}
digests=$(gh api "repos/herdrdev/herdr/releases/tags/v$version" \
  --jq '.assets[] | select(.name | test("^herdr-(linux|macos)-(x86_64|aarch64)$")) | "\(.name | ltrimstr("herdr-")) \(.digest | ltrimstr("sha256:"))"')
[ "$(wc -l <<<"$digests")" -eq 4 ] || {
  echo "expected 4 linux/macos binaries in v$version, got:" >&2
  echo "$digests" >&2
  exit 1
}
echo "    \"$version\" = {"
while read -r plat sum; do
  [[ $sum =~ ^[0-9a-f]{64}$ ]] || {
    echo "no SHA-256 digest for $plat" >&2
    exit 1
  }
  printf '      %-15s = "%s"\n' "\"$plat\"" "$sum"
done <<<"$digests"
echo "    }"
