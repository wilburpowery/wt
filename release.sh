#!/usr/bin/env bash
set -euo pipefail

V="${1:?usage: release.sh <version> — bumps WT_VERSION, tags, pushes, updates the tap formula}"
[[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "✗ version must be semver (e.g. 0.1.1)" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAP="${WT_TAP_DIR:-$ROOT/../homebrew-tap}"
[[ -f "$TAP/Formula/wt.rb" ]] || { echo "✗ tap formula not found at $TAP/Formula/wt.rb (set WT_TAP_DIR)" >&2; exit 1; }

echo "▸ Bumping WT_VERSION to $V"
sed -i '' "s/^WT_VERSION=.*/WT_VERSION=\"$V\"/" "$ROOT/wt"
bash -n "$ROOT/wt"

git -C "$ROOT" add wt
git -C "$ROOT" commit -m "Release v$V"
git -C "$ROOT" tag -a "v$V" -m "v$V"
git -C "$ROOT" push origin main --tags

echo "▸ Computing tarball sha256"
SHA="$(curl -sL "https://github.com/wilburpowery/wt/archive/refs/tags/v$V.tar.gz" | shasum -a 256 | awk '{print $1}')"
[[ -n "$SHA" ]] || { echo "✗ failed to fetch tarball" >&2; exit 1; }
echo "  $SHA"

echo "▸ Updating tap formula"
sed -i '' \
  -e "s|tags/v[0-9][0-9.]*\.tar\.gz|tags/v$V.tar.gz|" \
  -e "s|^  sha256 \".*\"|  sha256 \"$SHA\"|" \
  "$TAP/Formula/wt.rb"

git -C "$TAP" add Formula/wt.rb
git -C "$TAP" commit -m "wt $V"
git -C "$TAP" push origin main

echo ""
echo "✓ Released v$V"
echo "  users pick it up with: brew update && brew upgrade wt"
