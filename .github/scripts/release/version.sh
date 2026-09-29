#!/usr/bin/env bash
#
# Version lookup for the release scripts. Release tags are plain `X.Y.Z`, and
# every script finds the previous release here, so the tag pattern has one
# home.
#
#   highest-tag   the latest release tag by version order

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  version.sh highest-tag
USAGE
  exit 2
}

case ${1:-} in
  highest-tag)
    [[ $# -eq 1 ]] || usage
    # Release tags are plain X.Y.Z. The glob skips legacy `v*` tags; the exact
    # pattern also skips prerelease names such as 2.0.0-rc1.
    tag=$(
      git tag --list '[0-9]*.[0-9]*.[0-9]*' --sort=-version:refname \
        | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
        | head -n 1 \
        || true
    )
    if [[ -z $tag ]]; then
      echo "No release tag matching X.Y.Z was found." >&2
      exit 1
    fi
    printf '%s\n' "$tag"
    ;;
  *)
    usage
    ;;
esac
