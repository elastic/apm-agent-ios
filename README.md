[![Build Status](https://apm-ci.elastic.co/buildStatus/icon?job=apm-agent-ios%2Fapm-agent-ios-mbp%2Fmain)](https://apm-ci.elastic.co/job/apm-agent-ios/job/apm-agent-ios-mbp/job/main/)

# apm-agent-ios : APM Agent for iOS
This is the official iOS package for [Elastic APM](https://www.elastic.co/solutions/apm)

This package is considered experimental and should not be used in production.

## Documentation

Visit [elastic.co](https://www.elastic.co/guide/en/apm/agent/swift/current/index.html) for the iOS agent documentation.

To build this project's documentation locally, you must first clone the [`elastic/docs` repository](https://github.com/elastic/docs/). Then run the following commands:

```bash
# Set the location of your repositories
export GIT_HOME="/<fullPathToYourRepos>"
# Build the APM iOS documentation
$GIT_HOME/docs/build_docs --doc $GIT_HOME/apm-agent-ios/docs/index.asciidoc --chunk 1 --open
```
