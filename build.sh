#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

scheme="${SCHEME:-pod}"
configuration="${CONFIGURATION:-Debug}"
source_packages_dir="${SOURCE_PACKAGES_DIR:-$HOME/.openclaw/tmp/pod-sourcepackages}"
destination="${DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}"

case "${1:-sim}" in
  sim)
    ;;
  ipad)
    destination="platform=iOS,id=00008030-0006644A0130C02E"
    ;;
  resolve)
    mkdir -p "$source_packages_dir"
    xcodebuild -resolvePackageDependencies \
      -project pod.xcodeproj \
      -scheme "$scheme" \
      -clonedSourcePackagesDirPath "$source_packages_dir"
    exit 0
    ;;
  *)
    echo "Usage: ./build.sh [sim|ipad|resolve]"
    echo "Override with DESTINATION=..., CONFIGURATION=..., SCHEME=..., SOURCE_PACKAGES_DIR=..."
    exit 2
    ;;
esac

mkdir -p "$source_packages_dir"
echo "Building scheme=$scheme configuration=$configuration"
echo "Destination: $destination"
echo "SwiftPM cache: $source_packages_dir"

xcodebuild \
  -project pod.xcodeproj \
  -scheme "$scheme" \
  -destination "$destination" \
  -configuration "$configuration" \
  -clonedSourcePackagesDirPath "$source_packages_dir" \
  build
