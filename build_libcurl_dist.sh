#!/bin/bash

# Configuration ###############################################################

# Each slice must follow the format "ARCH HOST PLATFORM"
SLICES=(
  "x86_64 x86_64-apple-darwin iphonesimulator"
  "arm64 arm-apple-darwin iphonesimulator"
  "arm64 arm-apple-darwin iphoneos"
)

###############################################################################

CURLDIR="${1:-}"

set -euo pipefail

if [ ! -d "$CURLDIR" ]; then
  echo "Expected the cURL directory as argument"
  exit 1
fi

CURL_VERSION=$(/usr/libexec/PlistBuddy "$CURLDIR/lib/libcurl.plist" -c 'Print :CFBundleVersion')

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

DFT_DIST_DIR="${CURRENT_DIR}/dist"
DIST_DIR=${DIST_DIR:-$DFT_DIST_DIR}

XCFRAMEWORK_PATH="$DIST_DIR/curl.xcframework"

IPHONEOS_DEPLOYMENT_TARGET="13.0"
TMP_DIR="/Users/guillaume/Projects/Ipso/build-libcurl-ios/build"

# Remove any already existing .xcframework from the DIST_DIR
rm -rf "$XCFRAMEWORK_PATH"

function dirname_for_slice() {
  read -r -a SLICE_PARTS <<< "$SLICE"
  ARCH="${SLICE_PARTS[0]}"
  HOST="${SLICE_PARTS[1]}"
  PLATFORM="${SLICE_PARTS[2]}"
  echo "$PLATFORM/$ARCH"
}

function build_slice() {
  SLICE="$1"
  read -r -a SLICE_PARTS <<< "$SLICE"
  ARCH="${SLICE_PARTS[0]}"
  HOST="${SLICE_PARTS[1]}"
  PLATFORM="${SLICE_PARTS[2]}"

  DESTINATION="$PLATFORM"
  if [[ "$DESTINATION" =~ "simulator" ]]; then
    DESTINATION="simulator"
  fi

  SDKROOT="$(xcrun --sdk "$PLATFORM" --show-sdk-path)"
  CC="$(xcrun -f clang)"
  CPP="$CC -E"
  export CC
  export CPP
  export CFLAGS="-Os -miphoneos-version-min=${IPHONEOS_DEPLOYMENT_TARGET} -isysroot ${SDKROOT} -target ${ARCH}-apple-ios${IPHONEOS_DEPLOYMENT_TARGET}-${DESTINATION}"
  export CPPFLAGS="-arch ${ARCH} -I${SDKROOT}/usr/include"
  export LDFLAGS="-arch ${ARCH} -isysroot ${SDKROOT}"

  SLICE_DIRNAME=$(dirname_for_slice "$SLICE")
  PREFIX="${TMP_DIR}/${SLICE_DIRNAME}"

  make clean

  echo "BUILDING FOR ${PLATFORM}"
  echo "  ARCH = ${ARCH}"
  echo "  HOST = ${HOST}"
  echo "  SDKROOT = ${SDKROOT}"
  echo "  BUILD DIR = ${PREFIX}"
  echo

  ./configure \
    --disable-dependency-tracking \
    --disable-shared \
    --enable-static \
    \
    --disable-debug \
    --enable-optimize \
    --enable-warnings \
    --disable-curldebug \
    --enable-symbol-hiding \
    \
    --disable-ares \
    \
    --enable-http \
    --disable-ftp \
    --disable-file \
    --disable-ldap \
    --disable-ldaps \
    --disable-rtsp \
    --disable-proxy \
    --disable-dict \
    --disable-telnet \
    --disable-tftp \
    --disable-pop3 \
    --disable-imap \
    --disable-smb \
    --disable-smtp \
    --disable-gopher \
    --disable-manual \
    --disable-libcurl-option \
    --enable-ipv6 \
    \
    --enable-threaded-resolver \
    --disable-sspi \
    --disable-crypto-auth \
    --disable-tls-srp \
    \
    --without-winssl \
    --without-schannel \
    --with-secure-transport \
    \
    --without-libidn2 \
    \
    --with-nghttp2 \
    \
    --host="${HOST}" --prefix="${PREFIX}" && xcrun make -j "$(sysctl -n hw.logicalcpu_max)" && xcrun make install
}

cd "${CURLDIR}"

LIB_ARGS=()
for SLICE in "${SLICES[@]}"; do
  build_slice "$SLICE" || exit 1

  SLICE_DIRNAME=$(dirname_for_slice "$SLICE")
done

# Ensure all the generated 'include' directories are identical
for SLICE_INDEX in $(seq 1 $((${#SLICES[@]} - 1))); do
  PREV_SLICE_INDEX=$((SLICE_INDEX - 1))
  PREV_SLICE_DIR="$(dirname_for_slice "${SLICES[PREV_SLICE_INDEX]}")"
  PREV_INCLUDE_DIR="$TMP_DIR/${PREV_SLICE_DIR}/include"

  SLICE_DIR="$(dirname_for_slice "${SLICES[$SLICE_INDEX]}")"
  INCLUDE_DIR="$TMP_DIR/${SLICE_DIR}/include"

  if ! diff -r "$PREV_INCLUDE_DIR" "$INCLUDE_DIR" > /dev/null 2>&1 ; then
    echo "Error: The generated /include directories are not identical"
    echo "\"$PREV_INCLUDE_DIR\" and \"$INCLUDE_DIR\" are different"
    exit 2
  fi
done

# lipo slices together per platform
# https://developer.apple.com/forums/thread/666335
PLATFORM_COUNT=0
for PLATFORM in "$TMP_DIR"/*; do
  PLATFORM=$(basename "$PLATFORM")
  OUTPUT="$TMP_DIR/$PLATFORM/libcurl.a"
  xcrun lipo -create "$TMP_DIR/$PLATFORM"/*"/lib/libcurl.a" -output "$OUTPUT"
  LIB_ARGS+=('-library' "$OUTPUT")
  ((PLATFORM_COUNT++))
done

echo

xcrun xcodebuild -create-xcframework \
  "${LIB_ARGS[@]}" \
  -headers "${INCLUDE_DIR}" \
  -output "${XCFRAMEWORK_PATH}"

# Fix the 'Headers' directory location in the xcframework, and update the
# Info.plist accordingly for all slices.
XCFRAMEWORK_HEADERS_PATH=$(find "${XCFRAMEWORK_PATH}" -name 'Headers')
mv "$XCFRAMEWORK_HEADERS_PATH" "$XCFRAMEWORK_PATH"

for I in $(seq 0 $((PLATFORM_COUNT - 1))); do
  xcrun plutil -replace "AvailableLibraries.$I.HeadersPath" -string '../Headers' "$XCFRAMEWORK_PATH/Info.plist"
done


echo "$CURL_VERSION" > "${XCFRAMEWORK_PATH}/VERSION"

echo "Built XCFramework in $DIST_DIR"
