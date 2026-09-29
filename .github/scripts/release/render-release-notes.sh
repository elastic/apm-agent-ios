#!/usr/bin/env bash
#
# Render the release-note JSON as the Markdown section for
# docs/release-notes/index.md.
#
# Usage: render-release-notes.sh <source-json> <version>
#
# Arguments:
#   source-json  release-note JSON to validate and render
#   version      release version in X.Y.Z form
#
# Environment:
#   GITHUB_REPOSITORY  owner/repository used in pull-request links
#                      (default elastic/apm-agent-ios)
#
# Validates the JSON shape, refuses input that still has `uncategorized`
# items, has no items, or has a message that already starts with
# `[Breaking]`, and prints a `## X.Y.Z` section with the anchors the existing
# sections use: an untitled list for dependencies, then "Features and
# enhancements" and "Fixes" subsections. Empty groups are omitted. Items with
# `breaking: true` render with a `[Breaking]` prefix and sort first, so the
# flag is the only breaking signal.

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: render-release-notes.sh <source-json> <version>" >&2
  exit 2
fi

source_file=$1
version=$2
release_date=$(LC_ALL=C date -u +'%B %-d, %Y')
repository=${GITHUB_REPOSITORY:-elastic/apm-agent-ios}

if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid release version: $version" >&2
  exit 1
fi

jq -e '
  type == "object"
  and (.dependencies | type == "array")
  and (.featuresEnhancements | type == "array")
  and (.fixes | type == "array")
  and (.uncategorized | type == "array")
  and ([.dependencies[], .featuresEnhancements[], .fixes[], .uncategorized[]]
    | all(
        type == "object"
        and (.message | type == "string" and length > 0 and (test("[\\r\\n]") | not))
        and (.breaking == null or (.breaking | type == "boolean"))
        and (
          .prId == null
          or (.prId | type == "number" and . == floor and . > 0)
          or (.prId | type == "string" and test("^[1-9][0-9]*$"))
        )
      )
  )
' "$source_file" >/dev/null 2>&1 || {
  echo "Release notes must be a JSON object with dependencies, featuresEnhancements, fixes, and uncategorized arrays of items with a one-line message, an optional prId, and an optional boolean breaking." >&2
  exit 1
}

if jq -e '[.dependencies[], .featuresEnhancements[], .fixes[], .uncategorized[]]
  | any(.message | startswith("[Breaking]"))' "$source_file" >/dev/null; then
  echo "Release-note messages must not start with [Breaking]; set breaking: true instead." >&2
  exit 1
fi
if [[ $(jq '.uncategorized | length' "$source_file") -ne 0 ]]; then
  echo "Release notes contain uncategorized items; place or delete every item before preparing the release." >&2
  exit 1
fi
if [[ $(jq '[.dependencies[], .featuresEnhancements[], .fixes[]] | length' "$source_file") -eq 0 ]]; then
  echo "Release notes must contain at least one item." >&2
  exit 1
fi

# The existing sections use `elastic-apm-<digits>-release-notes` for the
# version heading and `elastic-apm-ios-agent-<digits>-...` for the
# subsections. The two bases differ; keep both as they are.
digits=${version//./}
heading_anchor="elastic-apm-$digits-release-notes"
subsection_base="elastic-apm-ios-agent-$digits"

render_items() {
  jq -r \
    --arg repository "$repository" \
    "$1
     | sort_by(if .breaking == true then 0 else 1 end)
     | .[]
     | \"* \" + (if .breaking == true then \"[Breaking] \" else \"\" end) + .message
       + (if .prId == null then \"\"
          else \": [#\" + (.prId | tostring) + \"](https://github.com/\" + \$repository + \"/pull/\" + (.prId | tostring) + \")\"
          end)" \
    "$source_file"
}

printf '## %s [%s]\n' "$version" "$heading_anchor"
printf '**Release date:** %s\n' "$release_date"

if [[ $(jq '.dependencies | length' "$source_file") -gt 0 ]]; then
  printf '\n'
  render_items '.dependencies'
fi
if [[ $(jq '.featuresEnhancements | length' "$source_file") -gt 0 ]]; then
  printf '\n### Features and enhancements [%s-features-enhancements]\n\n' "$subsection_base"
  render_items '.featuresEnhancements'
fi
if [[ $(jq '.fixes | length' "$source_file") -gt 0 ]]; then
  printf '\n### Fixes [%s-fixes]\n\n' "$subsection_base"
  render_items '.fixes'
fi
