#!/bin/bash
set -euo pipefail

# Usage: scripts/release.sh <version>
# Example: scripts/release.sh 0.4.0

VERSION="${1:-}"

if [ -z "$VERSION" ]; then
  echo "Usage: scripts/release.sh <version>"
  echo "Example: scripts/release.sh 0.4.0"
  exit 1
fi

# Strip leading 'v' if provided
VERSION="${VERSION#v}"

echo "Preparing release v${VERSION}..."

# Check for clean working tree
if [ -n "$(git status --porcelain)" ]; then
  echo "ERROR: Working tree is not clean. Commit or stash changes first."
  exit 1
fi

# Verify version in Clings.swift matches
SOURCE_VERSION=$(grep -o 'version: "[^"]*"' Sources/ClingsCLI/Clings.swift | head -1 | sed 's/version: "//;s/"//')
if [ "$SOURCE_VERSION" != "$VERSION" ]; then
  echo "ERROR: Clings.swift has version \"${SOURCE_VERSION}\", expected \"${VERSION}\""
  echo "Update the version in Sources/ClingsCLI/Clings.swift first."
  exit 1
fi

# Verify changelog entry exists
if ! grep -q "^## \[${VERSION}\]" CHANGELOG.md; then
  echo "ERROR: No changelog entry found for [${VERSION}] in CHANGELOG.md"
  echo "Add a ## [${VERSION}] section to CHANGELOG.md first."
  exit 1
fi

# Create annotated tag and push
echo "Creating tag v${VERSION}..."
git tag -a "v${VERSION}" -m "Release v${VERSION}"

echo "Pushing tag to origin..."
git push origin "v${VERSION}"

REPO_URL=$(git remote get-url origin | sed 's/\.git$//' | sed 's|git@github.com:|https://github.com/|')
echo ""
echo "Tag v${VERSION} pushed. Watch the release workflow:"
echo "  ${REPO_URL}/actions"
