#!/usr/bin/env bash

set -euo pipefail
trap 'echo "::error::SwiftLint setup or Git comparison failed (line $LINENO, exit $?)." >&2' ERR

# Git stays on the runner. This image is the inspected swift-5 runtime (SwiftLint 0.63.2).
SWIFTLINT_IMAGE=norionomura/swiftlint@sha256:fbcab6fa89a5e652da77d10aa167f321b96ee68a95f02c2c5ea525f4c66f2de9

fail() {
  echo "::error::$*" >&2
  exit 1
}

validate_commit() {
  [[ "$1" =~ ^[0-9a-fA-F]{40}$ ]] || fail "Invalid $2 commit: $1"
}

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"
full_scope=false
case "${GITHUB_EVENT_NAME:-}" in
  pull_request)
    base=${PR_BASE_SHA:-}
    head=${PR_HEAD_SHA:-}
    validate_commit "$base" 'PR base'
    validate_commit "$head" 'PR head'
    ;;
  push)
    base=${PUSH_BASE_SHA:-}
    head=${PUSH_HEAD_SHA:-}
    validate_commit "$head" 'push head'
    if [[ -z "$base" || "$base" =~ ^0+$ ]]; then
      full_scope=true
      echo 'Initial push has no predecessor; linting the full configured source scope.'
    else
      validate_commit "$base" 'push predecessor'
    fi
    ;;
  workflow_dispatch)
    full_scope=true
    echo 'Manual dispatch; linting the full configured source scope.'
    ;;
  *) fail "Unsupported lint event: ${GITHUB_EVENT_NAME:-unset}" ;;
esac

files=()
if [[ "$GITHUB_EVENT_NAME" != workflow_dispatch ]]; then
  refs=("$head")
  if [[ "$full_scope" == false ]]; then refs+=("$base"); fi
  # A shallow checkout may not contain the PR merge base. Fetch full ancestry explicitly.
  if [[ $(git rev-parse --is-shallow-repository) == true ]]; then
    git fetch --no-tags --unshallow origin "${refs[@]}"
  else
    git fetch --no-tags origin "${refs[@]}"
  fi
  git cat-file -e "${head}^{commit}"
  if [[ "$full_scope" == false ]]; then
    git cat-file -e "${base}^{commit}"
    if [[ "$GITHUB_EVENT_NAME" == pull_request ]]; then
      base=$(git merge-base "$base" "$head")
    fi
    diff_file=$(mktemp)
    trap 'rm -f "$diff_file"' EXIT
    # Capture first: a process-substitution loop would hide a failed git diff.
    git diff --name-only -z --diff-filter=ACMRT "$base" "$head" -- > "$diff_file"
    while IFS= read -r -d '' path; do
      if [[ "$path" == *.swift && -f "$path" ]]; then files+=("./$path"); fi
    done < "$diff_file"
    if [[ ${#files[@]} -eq 0 ]]; then
      echo 'No existing Swift files changed; SwiftLint has nothing to lint.'
      exit 0
    fi
  fi
fi

# Explicit paths respect configured exclusions. With no paths, SwiftLint owns included scope.
# Prefix filenames with ./ so option-like names are passed as paths. Arrays preserve whitespace.
# The container performs no Git operations and cannot change the checkout.
trap - ERR
docker run --rm --platform linux/amd64 \
  --volume "$repo_root:/work:ro" --workdir /work \
  --entrypoint /usr/local/bin/swiftlint "$SWIFTLINT_IMAGE" \
  lint --config .swiftlint.yml --strict --force-exclude --no-cache ${files[@]+"${files[@]}"}
