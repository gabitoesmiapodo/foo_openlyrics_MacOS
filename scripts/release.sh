#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ── Helpers ────────────────────────────────────────────────────────────────────

die() { echo "error: $*" >&2; exit 1; }
confirm() {
    local prompt="$1"
    local reply
    read -r -p "$prompt [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

# ── Pre-flight checks ──────────────────────────────────────────────────────────

command -v gh >/dev/null 2>&1 || die "gh CLI not found"
command -v git >/dev/null 2>&1 || die "git not found"

cd "$PROJECT_DIR"

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "main" ]; then
    die "must be on main branch (currently on '$CURRENT_BRANCH')"
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
    die "working tree is dirty -- commit or stash changes first"
fi

# ── Ask for version ────────────────────────────────────────────────────────────

CURRENT_VERSION=$(grep 'DECLARE_COMPONENT_VERSION' mac/OpenLyricsRegistration.mm \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')

echo "Current version: $CURRENT_VERSION"
read -r -p "New version: " NEW_VERSION

[[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || die "invalid version format (expected X.Y.Z)"

TAG="v$NEW_VERSION"

echo ""
echo "  Version : $CURRENT_VERSION → $NEW_VERSION"
echo "  Tag     : $TAG"
echo ""
confirm "Proceed?" || { echo "Aborted."; exit 0; }

# ── Pull latest main ───────────────────────────────────────────────────────────

echo ""
echo "==> Pulling latest main..."
git pull origin main

# ── Bump version ───────────────────────────────────────────────────────────────

echo "==> Bumping version to $NEW_VERSION..."

sed -i '' "s/DECLARE_COMPONENT_VERSION(\"OpenLyrics MacOS\", \"$CURRENT_VERSION\"/DECLARE_COMPONENT_VERSION(\"OpenLyrics MacOS\", \"$NEW_VERSION\"/" \
    mac/OpenLyricsRegistration.mm

sed -i '' "s/MARKETING_VERSION = [0-9]*\.[0-9]*\.[0-9]*;/MARKETING_VERSION = $NEW_VERSION;/g" \
    mac/openlyrics.xcodeproj/project.pbxproj

# ── Build & deploy ─────────────────────────────────────────────────────────────

echo "==> Building..."
SKIP_DEPS_BUILD=1 bash "$SCRIPT_DIR/deploy-component.sh" --build

BUILD_DIR="$PROJECT_DIR/mac/build/Release"
COMPONENT="$BUILD_DIR/foo_openlyrics_MacOS.component"
ARTIFACT="$BUILD_DIR/foo_openlyrics_MacOS.fb2k-component"

[ -d "$COMPONENT" ] || die "build artifact not found: $COMPONENT"

echo "==> Packaging $ARTIFACT..."
cd "$BUILD_DIR"
rm -f "$ARTIFACT"
mkdir -p mac
cp -r "foo_openlyrics_MacOS.component" mac/
zip -r "foo_openlyrics_MacOS.fb2k-component" "mac/foo_openlyrics_MacOS.component"
rm -rf mac
cd "$PROJECT_DIR"

# ── Commit & push ──────────────────────────────────────────────────────────────

echo "==> Committing version bump..."
git add mac/OpenLyricsRegistration.mm mac/openlyrics.xcodeproj/project.pbxproj
git commit -m "chore: bump version to $NEW_VERSION"
git push origin main

# ── Tag ────────────────────────────────────────────────────────────────────────

echo "==> Creating tag $TAG..."
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "    Tag $TAG already exists locally -- deleting..."
    git tag -d "$TAG"
fi
if git ls-remote --tags origin "$TAG" | grep -q "$TAG"; then
    echo "    Tag $TAG exists on remote -- deleting..."
    git push origin --delete "$TAG"
fi
git tag "$TAG"
git push origin "$TAG"

# ── Release ────────────────────────────────────────────────────────────────────

echo "==> Creating GitHub release $TAG..."
if gh release view "$TAG" >/dev/null 2>&1; then
    echo "    Release $TAG already exists -- deleting..."
    gh release delete "$TAG" --yes
fi

gh release create "$TAG" \
    --title "$TAG" \
    --generate-notes \
    "$ARTIFACT"

echo ""
echo "Done. https://github.com/gabitoesmiapodo/foo_openlyrics_MacOS/releases/tag/$TAG"
