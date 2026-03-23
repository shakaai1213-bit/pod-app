#!/bin/bash
cd ~/pod-app
xcodebuild -project pod.xcodeproj -scheme pod -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
