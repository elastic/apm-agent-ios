#!/bin/bash

xcodebuild clean archive -scheme ElasticApm_iOS \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath Release-iOS.xcarchive \
  -derivedDataPath derivedDataPath \
  SKIP_INSTALL=NO
  
xcodebuild clean archive -scheme ElasticApm_iOS \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -archivePath Release-iphonesimulator.xcarchive \
  -derivedDataPath derivedDataPath \
  SKIP_INSTALL=NO

xcodebuild clean archive -scheme ElasticApm_macOS \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath Release-macOS.xcarchive \
  -derivedDataPath derivedDataPath \
  SKIP_INSTALL=NO


xcodebuild clean archive -scheme ElasticApm_tvOS \
  -configuration Release \
  -destination 'generic/platform=tvOS' \
  -archivePath Release-tvOS.xcarchive \
  -derivedDataPath derivedDataPath \
  SKIP_INSTALL=NO

xcodebuild -create-xcframework \
    -framework $(pwd)/Release-iOS.xcarchive/Products/Library/Frameworks/ElasticApm.framework \
    -framework $(pwd)/Release-iphonesimulator.xcarchive/Products/Library/Frameworks/ElasticApm.framework \
    -framework $(pwd)/Release-macOS.xcarchive/Products/Library/Frameworks/ElasticApm.framework \
    -framework $(pwd)/Release-tvOS.xcarchive/Products/Library/Frameworks/ElasticApm.framework \
    -output ElasticApm.xcframework


