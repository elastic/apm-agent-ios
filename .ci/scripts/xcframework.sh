#!/usr/bin/env bash
# Bash strict mode
set -eo pipefail
trap 's=$?; echo >&2 "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

xcodebuild clean archive -scheme ElasticApm_iOS \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath ./build/Release-iOS.xcarchive \
    -derivedDataPath ./build/derivedDataPath \
    SKIP_INSTALL=NO
    
xcodebuild clean archive -scheme ElasticApm_iOS \
    -configuration Release \
    -destination 'generic/platform=iOS Simulator' \
    -archivePath ./build/Release-iphonesimulator.xcarchive \
    -derivedDataPath ./build/derivedDataPath \
    SKIP_INSTALL=NO

xcodebuild -create-xcframework \
        -framework $(pwd)/build/Release-iOS.xcarchive/Products/Library/Frameworks/ElasticApm.framework \
        -framework $(pwd)/build/Release-iphonesimulator.xcarchive/Products/Library/Frameworks/ElasticApm.framework \
        -output ./build/ElasticApm_iOS.xcframework


xcodebuild clean archive -scheme ElasticApm_macOS \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath ./build/Release-macOS.xcarchive \
    -derivedDataPath ./build/derivedDataPath \
    SKIP_INSTALL=NO

xcodebuild -create-xcframework \
        -framework $(pwd)/build/Release-macOS.xcarchive/Products/Library/Frameworks/ElasticApm.framework \
        -output ./build/ElasticApm_macOS.xcframework

xcodebuild clean archive -scheme ElasticApm_tvOS \
    -configuration Release \
    -destination 'generic/platform=tvOS' \
    -archivePath ./build/Release-tvOS.xcarchive \
    -derivedDataPath ./build/derivedDataPath \
    SKIP_INSTALL=NO

xcodebuild -create-xcframework \
        -framework $(pwd)/build/Release-tvOS.xcarchive/Products/Library/Frameworks/ElasticApm.framework \
        -output ./build/ElasticApm_tvOS.xcframework


