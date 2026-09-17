#!/usr/bin/env bash
# Cut a signed release locally. The signing (commit + tag) stays human — a CI
# job cannot produce a GPG-signed object without a private key in secrets, which
# this project deliberately avoids. Pushing the tag triggers .github/workflows/
# release.yml, which publishes the GitHub Release.
#
# Usage:
#   scripts/release.sh X.Y.Z             # bump CHANGELOG, signed commit + signed tag
#   scripts/release.sh --dry-run X.Y.Z   # print the bumped CHANGELOG, touch nothing
set -euo pipefail

REPO="JarnDev/autodap.nvim"

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then DRY_RUN=1; shift; fi
VERSION="${1:-}"
[ -n "$VERSION" ] || { echo "usage: scripts/release.sh [--dry-run] X.Y.Z" >&2; exit 1; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: version must be X.Y.Z" >&2; exit 1; }
TAG="v$VERSION"
DATE="$(date +%Y-%m-%d)"

# Promote the [Unreleased] section to [X.Y.Z] - DATE and fix the link refs.
# Reads CHANGELOG.md on stdin, writes the result to stdout.
bump_changelog() {
  awk -v ver="$VERSION" -v date="$DATE" '
    { print }
    /^## \[Unreleased\]/ && !seen { print ""; print "## [" ver "] - " date; seen=1 }
  ' \
  | sed -E "s#^\[Unreleased\]:.*#[Unreleased]: https://github.com/$REPO/compare/$TAG...HEAD#" \
  | awk -v ver="$VERSION" -v repo="$REPO" -v tag="$TAG" '
      { print }
      /^\[Unreleased\]:/ { print "[" ver "]: https://github.com/" repo "/releases/tag/" tag }
    '
}

if [ "$DRY_RUN" = 1 ]; then
  bump_changelog < CHANGELOG.md
  exit 0
fi

[ -z "$(git status --porcelain)" ] || { echo "error: working tree is not clean" >&2; exit 1; }
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || { echo "error: not on main" >&2; exit 1; }
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
  echo "error: tag $TAG already exists" >&2; exit 1
fi

bump_changelog < CHANGELOG.md > CHANGELOG.md.tmp && mv CHANGELOG.md.tmp CHANGELOG.md
git add CHANGELOG.md
git commit -S -q -m "docs: release $VERSION"
git tag -s "$TAG" -m "autodap.nvim $VERSION"

cat <<EOF
Created signed commit and signed tag $TAG.
  review:   git show $TAG
  publish:  git push origin main $TAG
Pushing the tag triggers the release workflow, which creates the GitHub Release.
EOF
