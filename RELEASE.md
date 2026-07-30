# Release process

Releases are created through GitHub Actions. Version numbers, Git tags, and
GitHub release names use the semantic version format `X.Y.Z`. Release branches
use the corresponding `rel/X.Y.Z` name.

Do not manually edit `Sources/apm-agent-ios/Version.swift`, create a tag, or
create a GitHub release.

## Prepare the release

- [ ] Choose the next semantic version.
- [ ] Confirm the latest commit on `main` passes all required checks.
- [ ] Update the package version in
      `docs/reference/edot-ios/getting-started.md`.
- [ ] Update the OpenTelemetry Swift version in
      `docs/reference/edot-ios/automatic-instrumentation.md`, if necessary.
- [ ] Add the release to `docs/release-notes/index.md`.
- [ ] Update `NOTICE.txt` if dependency licenses changed.
- [ ] Confirm all package dependencies resolve to semantic versions. The
      release workflow also validates this requirement.
- [ ] Merge the documentation and notice updates into `main`.

## Create the release

1. Open the **Create Release PR** workflow in GitHub Actions.
2. Run it from `main` and enter the new version as `X.Y.Z`.
3. Review the generated `rel/X.Y.Z` pull request and wait for all required
   checks to pass.
4. Merge the pull request.

Merging the release pull request runs the **Tag & Note Release** workflow. It
tags the merge commit as `X.Y.Z` and immediately publishes a stable GitHub
release named `X.Y.Z` with generated release notes. Closed or merged pull
requests from other branches do not run the release job.

## Verify the release

- [ ] Confirm the `X.Y.Z` tag points to the release pull request's merge
      commit.
- [ ] Confirm the GitHub release is published, marked as the latest release,
      and is not a prerelease.
- [ ] Review the generated GitHub release notes.
- [ ] Confirm `Sources/apm-agent-ios/Version.swift` contains `X.Y.Z` on
      `main`.
