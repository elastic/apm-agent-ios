[![macos](https://github.com/elastic/apm-agent-ios/actions/workflows/macos.yml/badge.svg)](https://github.com/elastic/apm-agent-ios/actions/workflows/macos.yml)


# apm-agent-ios : APM Agent for iOS
This is the official iOS package for [Elastic APM](https://www.elastic.co/solutions/apm)

## Documentation

Visit [elastic.co](https://www.elastic.co/guide/en/apm/agent/swift/current/index.html) for the iOS agent documentation.

To build this project's documentation locally, you must first clone the [`elastic/docs` repository](https://github.com/elastic/docs/). Then run the following commands:

```bash
# Set the location of your repositories
export GIT_HOME="/<fullPathToYourRepos>"
# Build the APM iOS documentation
$GIT_HOME/docs/build_docs --doc $GIT_HOME/apm-agent-ios/docs/index.asciidoc --chunk 1 --open
```

## Notes

### disabling noisy logs

- CoreTelephony in simulator
```xcrun simctl spawn booted log config --mode "level:off" --subsystem com.apple.CoreTelephony```

- Layout Constraints warnings
```xcrun simctl spawn booted log config --mode "level:off" --subsystem com.apple.UIKit```
