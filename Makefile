# Xcode build/test helpers for CI (pattern aligned with open-telemetry/opentelemetry-swift).
# Scheme name follows SwiftPM convention: <package-name>-Package

PROJECT_NAME := apm-agent-ios-Package

XCODEBUILD_OPTIONS_IOS := \
	-configuration Debug \
	-sdk iphonesimulator \
	-destination 'platform=iOS Simulator,name=iPhone 17' \
	-scheme $(PROJECT_NAME)

XCODEBUILD_OPTIONS_TVOS := \
	-configuration Debug \
	-sdk appletvsimulator \
	-destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
	-scheme $(PROJECT_NAME)

XCODEBUILD_OPTIONS_WATCHOS := \
	-configuration Debug \
	-sdk watchsimulator \
	-destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' \
	-scheme $(PROJECT_NAME)

.PHONY: setup-brew
setup-brew:
	brew update && brew install xcbeautify

.PHONY: build-for-testing-ios
build-for-testing-ios:
	set -o pipefail && xcodebuild $(XCODEBUILD_OPTIONS_IOS) build-for-testing | xcbeautify

.PHONY: build-for-testing-tvos
build-for-testing-tvos:
	set -o pipefail && xcodebuild $(XCODEBUILD_OPTIONS_TVOS) build-for-testing | xcbeautify

.PHONY: build-for-testing-watchos
build-for-testing-watchos:
	set -o pipefail && xcodebuild $(XCODEBUILD_OPTIONS_WATCHOS) build-for-testing | xcbeautify

.PHONY: test-without-building-ios
test-without-building-ios:
	set -o pipefail && xcodebuild $(XCODEBUILD_OPTIONS_IOS) test-without-building | xcbeautify

.PHONY: test-without-building-tvos
test-without-building-tvos:
	set -o pipefail && xcodebuild $(XCODEBUILD_OPTIONS_TVOS) test-without-building | xcbeautify

.PHONY: test-without-building-watchos
test-without-building-watchos:
	set -o pipefail && xcodebuild $(XCODEBUILD_OPTIONS_WATCHOS) test-without-building | xcbeautify
