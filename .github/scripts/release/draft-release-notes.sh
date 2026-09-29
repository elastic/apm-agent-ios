#!/usr/bin/env bash
#
# Draft the release-note JSON for the next release.
#
# Usage: draft-release-notes.sh [ref] [previous-tag]
#
# Arguments:
#   ref           commit or ref to draft for (default HEAD)
#   previous-tag  release tag at the start of the range (default the highest
#                 X.Y.Z tag, the same one Prepare release uses)
#
# Lists the pull requests merged since the previous release (see pr-range.sh)
# and groups them by label into the release-note JSON shape of sample.json:
# `dependencies`, `featuresEnhancements`, `fixes`, and `uncategorized`. Labels are hints only. A PR with none of the three labels
# lands in `uncategorized` for the operator to place or delete. Repeated
# updates of the same dependency collapse into the last one merged. The output
# is a starting point; the operator edits it before dispatching.

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
range=$("$script_dir/pr-range.sh" "${1:-HEAD}" "${2:-}")

jq 'def has_label($name):
      any(.labels[]?; ascii_downcase == $name);
    def item:
      {message: .title, prId: (.number | tostring)};
    # Title with every standalone number removed, so "Bump foo from 1.2 to
    # 1.3" and "Bump foo from 1.3 to 1.4" dedupe to one entry, and so do
    # "from 4 to 5" / "from 5 to 6" and "with 2 updates" / "with 4 updates".
    # Digits inside a name (log4j, junit5) are kept.
    def dependency_key:
      .title
      | ascii_downcase
      | gsub("\\bv?[0-9]+(\\.[0-9]+)*([-+][0-9a-z.-]+)?\\b"; "")
      | gsub("[[:space:]]+"; " ")
      | gsub("^[[:space:]]+|[[:space:]]+$"; "");
    .pullRequests as $included
    | (
        reduce ($included[] | select(has_label("dependencies"))) as $pr
          ([];
            ($pr | dependency_key) as $key
            | map(select(.key != $key))
            + [{key: $key, item: ($pr | item)}])
      ) as $dependencies
    | {
        dependencies: [$dependencies[].item],
        featuresEnhancements: [
          $included[]
          | select((has_label("dependencies") or has_label("bug")) | not)
          | select(has_label("enhancement"))
          | item
        ],
        fixes: [
          $included[]
          | select(has_label("dependencies") | not)
          | select(has_label("bug"))
          | item
        ],
        uncategorized: [
          $included[]
          | select(
              (
                has_label("dependencies")
                or has_label("enhancement")
                or has_label("bug")
              )
              | not
            )
          | item
        ]
      }' <<<"$range"
