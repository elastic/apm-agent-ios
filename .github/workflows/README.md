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

### Release process

The tag release follows the naming convention: `v.<major>.<minor>.<patch>`, where `<major>`, `<minor>` and `<patch>`.

### OpenTelemetry

Every workflow and its logs are exported to OpenTelemetry traces/logs/metrics. Those details can be seen [here](https://ela.st/oblt-ci-cd-stats) (**NOTE**: only available for Elasticians).
