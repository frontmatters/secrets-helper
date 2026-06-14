#!/usr/bin/env bash
# Cut a secrets-helper release in one shot: bump version everywhere, roll the
# changelog, commit, tag, push, and publish a GitHub Release. Pushing the tag
# triggers the notify-tap workflow, which auto-bumps the Homebrew formula.
#
# Usage:
#   ./release.sh 0.2.2     # explicit version
#   ./release.sh patch     # 0.2.1 -> 0.2.2
#   ./release.sh minor     # 0.2.1 -> 0.3.0
#   ./release.sh major     # 0.2.1 -> 1.0.0
#   ./release.sh patch -y  # skip the confirmation prompt
set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

die() { echo "ERROR: $*" >&2; exit 1; }

# --- Args ---
[[ $# -ge 1 ]] || die "usage: ./release.sh <major|minor|patch|X.Y.Z> [-y]"
BUMP="$1"; shift || true
ASSUME_YES=0
[[ "${1:-}" == "-y" || "${1:-}" == "--yes" ]] && ASSUME_YES=1

# --- Repo slug from origin (owner/repo), tolerating https or ssh remotes ---
origin="$(git config --get remote.origin.url || true)"
REPO="$(printf '%s' "$origin" | sed -E 's#(git@github\.com:|https://github\.com/)##; s#\.git$##')"
[[ -n "$REPO" ]] || die "could not determine GitHub owner/repo from origin remote"

# --- Compute new version ---
CUR="$(cat VERSION)"
[[ "$CUR" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "VERSION '$CUR' is not X.Y.Z"
IFS='.' read -r MA MI PA <<< "$CUR"
case "$BUMP" in
  major) NEW="$((MA+1)).0.0" ;;
  minor) NEW="${MA}.$((MI+1)).0" ;;
  patch) NEW="${MA}.${MI}.$((PA+1))" ;;
  [0-9]*) NEW="$BUMP" ;;
  *) die "first arg must be major|minor|patch or an explicit X.Y.Z version" ;;
esac
[[ "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "computed version '$NEW' is not X.Y.Z"
DATE="$(date '+%Y-%m-%d')"

# --- Preflight safety ---
git diff --quiet && git diff --cached --quiet \
  || die "working tree not clean — commit your changes (incl. CHANGELOG [Unreleased] notes) first"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[[ "$BRANCH" == "main" || "$BRANCH" == "master" ]] \
  || echo "WARN: on branch '$BRANCH', not main/master — continuing"
git rev-parse -q --verify "refs/tags/v${NEW}" >/dev/null \
  && die "tag v${NEW} already exists"
command -v gh >/dev/null || echo "WARN: gh not found — will skip GitHub Release creation"

# Warn if the changelog has nothing staged under [Unreleased].
unreleased_body="$(awk '/^## \[Unreleased\]/{g=1;next} g&&/^## \[/{exit} g{print}' CHANGELOG.md | tr -d '[:space:]')"
[[ -n "$unreleased_body" ]] || echo "WARN: CHANGELOG [Unreleased] section is empty"

echo "Release plan:"
echo "  repo:    $REPO"
echo "  version: $CUR -> $NEW"
echo "  date:    $DATE"
echo "  files:   VERSION, README.md (badge), CHANGELOG.md"
echo "  git:     commit 'Release v$NEW' + annotated tag v$NEW -> push origin $BRANCH"
echo "  release: gh release create v$NEW (notes from CHANGELOG)"
if [[ "$ASSUME_YES" -ne 1 ]]; then
  printf 'Continue? [y/N]: '; read -r ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || die "aborted"
fi

# --- 1. VERSION ---
printf '%s\n' "$NEW" > VERSION

# --- 2. README badge ---
perl -0pi -e "s{badge/version-\d+\.\d+\.\d+-}{badge/version-$NEW-}g" README.md

# --- 3. CHANGELOG: rename [Unreleased] -> [NEW] - DATE, add fresh [Unreleased] ---
perl -0pi -e "s/^## \[Unreleased\]/## [Unreleased]\n\n## [$NEW] - $DATE/m" CHANGELOG.md
# Repoint the compare link and add a tag link for the new version.
perl -0pi -e "s{compare/v\d+\.\d+\.\d+\.\.\.HEAD}{compare/v$NEW...HEAD}" CHANGELOG.md
perl -0pi -e "s{(^\[Unreleased\]:.*\n)}{\$1\[$NEW\]: https://github.com/$REPO/releases/tag/v$NEW\n}m" CHANGELOG.md

# --- 4. commit + annotated tag ---
git add VERSION README.md CHANGELOG.md
git commit -m "Release v$NEW"
git tag -a "v$NEW" -m "Release v$NEW"

# --- 5. push (commit + tag) — triggers the tap auto-bump ---
git push origin "$BRANCH" --follow-tags

# --- 6. GitHub Release with the changelog section as notes ---
if command -v gh >/dev/null; then
  notes="$(awk -v v="$NEW" '
    $0 ~ "^## \\[" v "\\]" {g=1; next}
    g && /^## \[/ {exit}
    g {print}
  ' CHANGELOG.md | perl -0pe 's/\A\s+//; s/\s+\z/\n/')"
  gh release create "v$NEW" --title "v$NEW" --notes "${notes:-Release v$NEW}"
  echo "Published GitHub Release v$NEW"
fi

echo "Done. v$NEW released. The Homebrew tap will auto-bump within moments (or daily)."
