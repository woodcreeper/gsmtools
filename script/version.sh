#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
BUILD_FILE="$ROOT_DIR/BUILD"

usage() {
  cat >&2 <<'USAGE'
usage:
  script/version.sh show
  script/version.sh set <major.minor.patch>
  script/version.sh bump major|minor|patch|build

Version uses SemVer while BUILD is a monotonically increasing app-bundle build number.
USAGE
}

read_version() {
  tr -d '[:space:]' <"$VERSION_FILE"
}

read_build() {
  tr -d '[:space:]' <"$BUILD_FILE"
}

validate_version() {
  local version="$1"
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
    echo "invalid version: $version" >&2
    echo "expected SemVer, e.g. 0.1.0 or 0.2.0-beta.1" >&2
    exit 2
  fi
}

write_version() {
  local version="$1"
  validate_version "$version"
  printf '%s\n' "$version" >"$VERSION_FILE"
}

write_build() {
  local build="$1"
  if [[ ! "$build" =~ ^[0-9]+$ ]] || [[ "$build" -lt 1 ]]; then
    echo "invalid build number: $build" >&2
    exit 2
  fi
  printf '%s\n' "$build" >"$BUILD_FILE"
}

increment_build() {
  local build
  build="$(read_build)"
  write_build "$((build + 1))"
}

show() {
  printf 'GSMTools %s (%s)\n' "$(read_version)" "$(read_build)"
}

command="${1:-show}"
case "$command" in
  show)
    show
    ;;
  set)
    [[ $# -eq 2 ]] || { usage; exit 2; }
    write_version "$2"
    increment_build
    show
    ;;
  bump)
    [[ $# -eq 2 ]] || { usage; exit 2; }
    version="$(read_version)"
    validate_version "$version"
    base="${version%%-*}"
    IFS='.' read -r major minor patch <<<"$base"
    case "$2" in
      major)
        major=$((major + 1))
        minor=0
        patch=0
        write_version "$major.$minor.$patch"
        increment_build
        ;;
      minor)
        minor=$((minor + 1))
        patch=0
        write_version "$major.$minor.$patch"
        increment_build
        ;;
      patch)
        patch=$((patch + 1))
        write_version "$major.$minor.$patch"
        increment_build
        ;;
      build)
        increment_build
        ;;
      *)
        usage
        exit 2
        ;;
    esac
    show
    ;;
  *)
    usage
    exit 2
    ;;
esac
