# CI end-to-end test

The end-to-end test runs the integration app in an iOS Simulator and confirms
that its telemetry reaches Elasticsearch through an Elastic Agent OTLP
endpoint.

## What it validates

The test:

1. Starts Elasticsearch and the OTLP endpoint as native macOS processes.
2. Builds the integration app in Release configuration with a dSYM.
3. Installs and launches the app in a fresh iOS Simulator.
4. Finds the app's span, log record, and metric in Elasticsearch.
5. Verifies the service name, service version, and telemetry SDK name on each
   matched document.

Every query includes a unique `test.run_id` resource attribute. The harness
passes that attribute at launch without adding test-only plumbing to the app.

## Run locally

The test requires macOS, Xcode with an iOS Simulator runtime, `curl`, `jq`,
`nc`, `shasum`, and `tar`. No container runtime is required.

Run this command from the repository root:

```sh
.github/scripts/e2e-test/e2e_test.sh
```

The first run downloads the pinned Elasticsearch and Elastic Agent archives to
the ignored `.ci-cache/` directory. Set `ELASTIC_VERSION` to test another
matching version.

## Artifacts

Results and diagnostics remain under `build/e2e/` after the run. They include:

- Elasticsearch and OTLP endpoint logs.
- App standard output, standard error, and Simulator logs on failure.
- The query for each assertion.
- The Elasticsearch document matched by each assertion.
