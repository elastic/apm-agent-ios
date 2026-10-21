# Release process

EDOT iOS is distributed through Swift Package Manager. A release is the
`X.Y.Z` tag, which SwiftPM resolves directly, plus the GitHub Release.

Do not edit `Sources/apm-agent-ios/Version.swift`, create a tag, or create a
GitHub Release by hand.

## Release steps

A release from `main` takes three steps: dispatch the preparation, merge the
preparation PR, then merge the resulting PR into `main`. The version is
derived from the highest release tag and the release-note content. Merging
the preparation PR is what publishes.

### 1. Prepare the release

Before dispatching, update `NOTICE.txt` on `main` when dependency licenses
changed. Update the OpenTelemetry-Swift compatibility sentence under
**SDK compatibility** in `docs/reference/edot-ios/automatic-instrumentation.md`
when supported versions changed. Merge these changes through ordinary PRs.

Open the
[Prepare release workflow](https://github.com/elastic/apm-agent-ios/actions/workflows/prepare-release.yml)
on `main` and provide the release-note JSON.

The workflow verifies that `Version.swift` holds the next minor `-SNAPSHOT` version after
the highest `X.Y.Z` tag, and that every package dependency resolves to a
version. It creates two branches from the dispatched `main` commit:

- `releasing/x.y.z`, an unchanged copy of `main` that lives until the
  release is finished.
- `prepare/x.y.z`, with one commit: the release version, the release notes,
  the SwiftPM `from:` version in `docs/reference/edot-ios/getting-started.md`,
  and, on a major release, the `applies_to` documentation versions.

It opens the preparation PR from `prepare/x.y.z` into `releasing/x.y.z`, so
the PR diff shows exactly what the release adds. Review it. Push prose or
NOTICE fixes to `prepare/x.y.z` if needed. For a code fix, land it on `main`,
close the PR, delete both branches, and dispatch again. If no pull request
merged since the previous release, the run succeeds, creates nothing, and
says so in its log.

#### Release-note JSON

The
[Draft release notes workflow](https://github.com/elastic/apm-agent-ios/actions/workflows/draft-release-notes.yml)
builds editable JSON from the pull requests merged since the last release. It
shows the JSON in its run summary and attaches it to the run as the
`release-notes` artifact. Labels only group the draft; none is required:

- `dependencies` → `dependencies`. Several updates of one dependency collapse
  into the last one merged. Dependabot adds this label to its pull requests.
- `enhancement` → `featuresEnhancements`
- `bug` → `fixes`
- anything else → `uncategorized`

Move every `uncategorized` item into a category or delete it. Add
`"breaking": true` to a breaking item. Any breaking item makes the release
major; otherwise it is minor. Prepare release rejects JSON that still has
`uncategorized` items, has no items, or has a `message` that starts with
`[Breaking]`; the flag adds that prefix when the notes are rendered.

Each item has a `message`, an optional `prId`, and an optional boolean
`breaking`:

```json
{
  "dependencies": [
    { "message": "Update OpenTelemetry dependencies", "prId": "401" }
  ],
  "featuresEnhancements": [
    { "message": "Improve automatic instrumentation", "prId": "402" },
    { "message": "Remove a deprecated configuration option", "prId": "403", "breaking": true }
  ],
  "fixes": [
    { "message": "Fix offline span delivery", "prId": "404" }
  ],
  "uncategorized": []
}
```

### 2. Merge the preparation PR

When the checks are green and the content is right, merge the preparation PR
into `releasing/x.y.z`. The merge starts the publish workflow, which:

1. Confirms the merged commit carries release version `x.y.z` and that no
   `x.y.z` tag exists yet.
2. Creates the `x.y.z` tag at the merged commit, publishing the release.
3. Creates the GitHub Release titled `EDOT iOS x.y.z`.
4. For a release from `main`, commits the next `-SNAPSHOT` version on
   `releasing/x.y.z` and opens its PR into `main`.
5. For a patch, opens a notes-only PR into `main`.
6. Deletes `prepare/x.y.z`. For a patch, it also deletes `patching/x.y.z`
   and `releasing/x.y.z`.

The team's Slack channel receives a start message once the merged commit is
confirmed, with the version, the merged PR, the release commit, and the run.
It then receives the outcome with links to the GitHub Release and the release
PR, or to the failed run.

### 3. Merge the PR into main

For a release from `main`, review and merge the PR from `releasing/x.y.z`.
It brings the release notes, documentation versions, and the next development
version to `main`. GitHub deletes the branch when its PR merges. Prepare
release stops while any `releasing/*` branch exists, naming it.

For a patch, review and merge the notes-only PR from `patch-notes/x.y.z`.
GitHub deletes that branch when its PR merges. The publish workflow has
already deleted `patching/x.y.z` and `releasing/x.y.z`.

## Patch release

Open the
[Start patch workflow](https://github.com/elastic/apm-agent-ios/actions/workflows/start-patch.yml)
on `main`. Supply the `X.Y` release line and, optionally, merged `main` pull
requests to cherry-pick, as numbers separated by commas, such as `1135,527`.

Start patch selects the highest `X.Y.Z` tag, creates
`patching/X.Y.(Z+1)` from it, and cherry-picks the selected fixes. It pushes
only after every cherry-pick succeeds. Add later fixes by opening pull
requests into the patch branch. A pull request that changes
`.github/workflows/*` cannot be cherry-picked by Start patch: if its push is
rejected, dispatch again without that pull request and add it through a pull
request into the patch branch.

The branch releases with the workflows of its tag.

Draft release notes by dispatching the Draft release notes workflow on `patching/x.y.z`; the draft then covers only that branch's
changes. Approve them, then dispatch Prepare release from that branch. Patch
preparation leaves `applies_to` metadata unchanged. Review and merge the
preparation PR to publish. Finally, merge the notes-only PR into `main`.
The publish workflow deletes `patching/x.y.z` and `releasing/x.y.z`.

## Failure and recovery

Use **Re-run failed jobs** on the failed publish run. Every publish and
finalization step checks the real system before acting and skips work that is
already done, so the rerun continues from the failed step.

- If the run log says the tag already exists, do not push or move it. Rerun so
  the remaining steps finish.
- If a tag exists at another commit, stop. Do not move it.
- If the preparation PR needs different content before it is merged, close
  it, delete both branches, land the correction on `main`, and prepare again.
- If opening the preparation PR fails, Prepare release deletes
  `releasing/x.y.z` and `prepare/x.y.z` and fails; dispatch again. If its log
  says it could not delete them, delete both by hand first. The next dispatch
  refuses while a `releasing/*` branch exists.
- Secret or credential failures require help from whoever owns the pipeline
  secrets.
- Start patch stops when the line has no release or the patch branch already
  exists. For an existing branch, add fixes through pull requests into it.
- If a Start patch cherry-pick conflicts, dispatch again without that pull
  request. Cherry-pick it by hand through a pull request into the named patch
  branch.
- If dependencies resolve to `unspecified`, change them on `main` to versions,
  then prepare again.
- If the SwiftPM `from:` version is not found exactly once, restore the single
  `from: "X.Y.Z"` line in `docs/reference/edot-ios/getting-started.md` on
  `main`, then prepare again.
