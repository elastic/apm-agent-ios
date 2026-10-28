#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
LINT_SCRIPT="$SCRIPT_DIR/swift-lint.sh"
FIXTURE_ROOT=$(mktemp -d)
trap 'rm -rf "$FIXTURE_ROOT"' EXIT
mkdir -p "$FIXTURE_ROOT/bin"
REAL_GIT=$(command -v git)
REAL_MKTEMP=$(command -v mktemp)
export REAL_GIT REAL_MKTEMP
cat > "$FIXTURE_ROOT/bin/docker" <<'STUB'
#!/usr/bin/env bash
printf '%s\0' "$@" > "$LINT_CALL"
exit "${LINTER_EXIT:-0}"
STUB
cat > "$FIXTURE_ROOT/bin/git" <<'STUB'
#!/usr/bin/env bash
if [[ "${FAIL_GIT_COMMAND:-}" == "$1" ]]; then
  echo "Injected Git $1 failure" >&2
  exit 71
fi
exec "$REAL_GIT" "$@"
STUB
# Observe real temporary-file creation without depending on the platform's TMPDIR policy.
cat > "$FIXTURE_ROOT/bin/mktemp" <<'OBSERVER'
#!/usr/bin/env bash
set -euo pipefail
path=$("$REAL_MKTEMP" "$@")
printf '%s\n' "$path" >> "$LINT_TEMP_PATHS"
printf '%s\n' "$path"
OBSERVER
chmod +x "$FIXTURE_ROOT/bin/docker" "$FIXTURE_ROOT/bin/git" "$FIXTURE_ROOT/bin/mktemp"
export PATH="$FIXTURE_ROOT/bin:$PATH"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export LINT_CALL="$FIXTURE_ROOT/lint-call"
export LINT_TEMP_PATHS="$FIXTURE_ROOT/lint-temp-paths"
output="$FIXTURE_ROOT/output"

fail() { echo "FAIL: $*" >&2; cat "$output" >&2; exit 1; }
assert_output() { grep -q "$1" "$output" || fail "Missing output: $1"; }
assert_arg() { tr '\0' '\n' < "$LINT_CALL" | grep -Fx -- "$1" >/dev/null || fail "Missing lint argument: $1"; }
run_lint() {
  rm -f "$LINT_CALL"
  result=0
  : > "$LINT_TEMP_PATHS"
  bash "$LINT_SCRIPT" > "$output" 2>&1 || result=$?
  local temporary_file
  while IFS= read -r temporary_file; do
    [[ ! -e "$temporary_file" ]] || fail "Lint left a temporary file: $temporary_file"
  done < "$LINT_TEMP_PATHS"
}
assert_lint() { [[ "$result" == 0 && -f "$LINT_CALL" ]] || fail 'Expected successful lint invocation'; }
assert_noop() {
  [[ "$result" == 0 && ! -e "$LINT_CALL" ]] || fail 'Expected successful no-op'
  assert_output 'No existing Swift files changed'
}
assert_git_failure() {
  [[ "$result" != 0 && ! -e "$LINT_CALL" ]] || fail 'Git failure did not fail closed'
  assert_output '::error::'
  if grep -q 'No existing Swift files changed' "$output"; then fail 'Git failure announced a no-op'; fi
}

# A local origin exercises real fetch, commit validation, merge-base, and NUL-delimited diff.
git init -q --bare "$FIXTURE_ROOT/origin.git"
git clone -q "$FIXTURE_ROOT/origin.git" "$FIXTURE_ROOT/work" 2>/dev/null
cd "$FIXTURE_ROOT/work"
git config user.name 'Lint fixture'
git config user.email 'lint-fixture@example.invalid'
mkdir Sources
printf 'let answer = 42\n' > Sources/Base.swift
printf 'included:\n  - Sources\n' > .swiftlint.yml
git add Sources/Base.swift .swiftlint.yml
git commit -qm initial
initial=$(git rev-parse HEAD)
printf 'let changed = true\n' > 'Sources/With space.swift'
printf 'let flag = false\n' > ./-Option.swift
git add -- 'Sources/With space.swift' ./-Option.swift
git commit -qm changed
changed=$(git rev-parse HEAD)
git branch fixture-base "$initial"
git push -q origin HEAD refs/heads/fixture-base

export GITHUB_EVENT_NAME=push PUSH_BASE_SHA="$initial" PUSH_HEAD_SHA="$changed"
run_lint
assert_lint
assert_arg './Sources/With space.swift'
assert_arg './-Option.swift'
assert_arg '--strict'
assert_arg '.swiftlint.yml'
assert_arg '--force-exclude'
echo 'PASS push changed Swift, spaces, and option-like filename'
[[ -s "$LINT_TEMP_PATHS" ]] || fail 'Changed-file lint created no observed comparison file'
echo 'PASS successful lint cleans comparison file'

export LINTER_EXIT=37
run_lint
[[ "$result" == 37 ]] || fail 'Linter status was not preserved'
unset LINTER_EXIT
[[ -s "$LINT_TEMP_PATHS" ]] || fail 'Failed lint created no observed comparison file'
echo 'PASS failed lint preserves exit 37 and cleans comparison file'

printf 'documentation\n' > README.md
git add README.md
git commit -qm documentation
docs=$(git rev-parse HEAD)
git rm -q -- 'Sources/With space.swift'
git commit -qm deletion
deleted=$(git rev-parse HEAD)
git push -q origin HEAD
export PUSH_BASE_SHA="$changed" PUSH_HEAD_SHA="$docs"
run_lint
assert_noop
export PUSH_BASE_SHA="$docs" PUSH_HEAD_SHA="$deleted"
run_lint
assert_noop
export PUSH_BASE_SHA="$changed" PUSH_HEAD_SHA="$changed"
run_lint
assert_noop
echo 'PASS non-Swift, deletion-only, and empty-diff no-ops'

# The PR base advances independently: its added Swift file must not enter the PR diff.
git checkout -q fixture-base
printf 'let baseOnly = true\n' > Sources/BaseOnly.swift
git add Sources/BaseOnly.swift
git commit -qm base-advance
pr_base=$(git rev-parse HEAD)
git push -q origin fixture-base
git checkout -q --detach "$changed"
export GITHUB_EVENT_NAME=pull_request PR_BASE_SHA="$pr_base" PR_HEAD_SHA="$changed"
run_lint
assert_lint
assert_arg './Sources/With space.swift'
if tr '\0' '\n' < "$LINT_CALL" | grep -Fx './Sources/BaseOnly.swift' >/dev/null; then fail 'PR did not use merge base'; fi
echo 'PASS PR merge-base selection'

git push -q origin "$changed:refs/heads/fixture-head"
git clone -q --depth 1 --branch fixture-head "file://$FIXTURE_ROOT/origin.git" "$FIXTURE_ROOT/shallow"
cd "$FIXTURE_ROOT/shallow"
[[ $(git rev-parse --is-shallow-repository) == true ]] || fail 'Fixture is not shallow'
run_lint
assert_lint
assert_arg './Sources/With space.swift'
[[ $(git rev-parse --is-shallow-repository) == false ]] || fail 'Required PR ancestry was not fetched'
cd "$FIXTURE_ROOT/work"
echo 'PASS shallow PR checkout fetches merge-base ancestry'

export PR_BASE_SHA=invalid
run_lint
assert_git_failure
export PR_BASE_SHA=1111111111111111111111111111111111111111
run_lint
assert_git_failure
export PR_BASE_SHA="$pr_base"
for command in rev-parse fetch diff; do
  export FAIL_GIT_COMMAND="$command"
  run_lint
  assert_git_failure
done
unset FAIL_GIT_COMMAND
echo 'PASS invalid/unavailable refs and Git ownership/fetch/diff failure boundaries'

export GITHUB_EVENT_NAME=workflow_dispatch
run_lint
assert_lint
assert_output 'full configured source scope'
if tr '\0' '\n' < "$LINT_CALL" | grep '^\./' >/dev/null; then fail 'Full scope passed changed files'; fi
export GITHUB_EVENT_NAME=push PUSH_HEAD_SHA="$changed"
for predecessor in '' 0000000000000000000000000000000000000000; do
  export PUSH_BASE_SHA="$predecessor"
  run_lint
  assert_lint
  assert_output 'full configured source scope'
done
echo 'PASS manual and initial-push full scope'

echo 'All SwiftLint regression checks passed.'
