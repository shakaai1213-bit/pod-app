#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

scheme="${SCHEME:-pod}"
configuration="${CONFIGURATION:-Debug}"
device_id="${IPAD_DEVICE_ID:-00008030-0006644A0130C02E}"
if [[ -d /Volumes/DockerExt ]]; then
  default_build_root="/Volumes/DockerExt/coral-builds/pod"
else
  default_build_root="$HOME/.openclaw/tmp/pod-build"
fi
build_root="${POD_BUILD_ROOT:-$default_build_root}"
source_packages_dir="${SOURCE_PACKAGES_DIR:-$build_root/SourcePackages}"
derived_data_dir="${DERIVED_DATA_DIR:-${TMPDIR:-/tmp}/pod-derived-data}"
destination="${DESTINATION:-generic/platform=iOS Simulator}"
install_after_build=false

case "${1:-sim}" in
  sim)
    ;;
  ipad)
    destination="platform=iOS,id=$device_id"
    ;;
  ipad-install)
    destination="platform=iOS,id=$device_id"
    install_after_build=true
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
    echo "Usage: ./build.sh [sim|ipad|ipad-install|resolve]"
    echo "Override with DESTINATION=..., CONFIGURATION=..., SCHEME=..., POD_BUILD_ROOT=..., DERIVED_DATA_DIR=..."
    exit 2
    ;;
esac

mkdir -p "$source_packages_dir"
mkdir -p "$derived_data_dir"
echo "Building scheme=$scheme configuration=$configuration"
echo "Destination: $destination"
echo "SwiftPM cache: $source_packages_dir"
echo "Derived data: $derived_data_dir"

xcodebuild \
  -project pod.xcodeproj \
  -scheme "$scheme" \
  -destination "$destination" \
  -configuration "$configuration" \
  -derivedDataPath "$derived_data_dir" \
  -clonedSourcePackagesDirPath "$source_packages_dir" \
  build

if [[ "$install_after_build" == true ]]; then
  app_path="$derived_data_dir/Build/Products/$configuration-iphoneos/pod.app"
  xcrun devicectl device install app --device "$device_id" "$app_path"
fi
