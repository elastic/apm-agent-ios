## CI/CD

There are 3 main stages that run on GitHub actions:

* Build
* Test
* Package

### Scenarios

* Tests should be triggered on branch, tag and PR basis.
* **This is not the case yet**, but if Github secrets are required then Pull Requests from forked repositories won't run any build accessing those secrets. If needed, then create a feature branch.

### How to interact with the CI?

#### On a PR basis

Once a PR has been opened then there are two different ways you can trigger builds in the CI:

1. Commit based
1. UI based, any Elasticians can force a build through the GitHub UI

#### Branches

Every time there is a merge to main or any release branches the whole workflow will compile and test on MacOS

### SwiftLint

The `swift-lint` job runs its focused regression checks followed by strict lint:

```sh
bash .github/scripts/test-swift-lint.sh
bash .github/scripts/swift-lint.sh
```

The lint command uses the GitHub event and the `PR_BASE_SHA`/`PR_HEAD_SHA` or
`PUSH_BASE_SHA`/`PUSH_HEAD_SHA` environment variables provided by the workflow.
Git runs on the checked-out runner: PRs compare from the base/head merge base;
pushes compare their actual before/after commits. Required history is fetched
explicitly. Manual dispatch and initial pushes without a predecessor lint the
full source scope in `.swiftlint.yml` and log that choice.

An invalid or unavailable commit, failed fetch, ownership error, or failed diff
produces an Actions error and fails the job. A successful comparison with no
existing changed Swift files logs a no-op. Deleted files are omitted; filenames
with spaces are passed intact. SwiftLint runs directly in the digest-pinned
container with the checked-out configuration, configured exclusions, and
`--strict`; linter failures fail the required gate. The regression command uses
isolated temporary repositories and a stub container command.

### Release process

Release versions and Git tags use `X.Y.Z`; see [`RELEASE.md`](../../RELEASE.md) for the release process.

### OpenTelemetry

Every workflow and its logs are exported to OpenTelemetry traces/logs/metrics. Those details can be seen [here](https://ela.st/oblt-ci-cd-stats) (**NOTE**: only available for Elasticians).
