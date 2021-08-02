#!/usr/bin/env bash

# Configuration ###############################################################

# Each slice must follow the format "ARCH HOST PLATFORM"
SLICES=(
  "x86_64 x86_64-apple-darwin iphonesimulator"
  "arm64 arm-apple-darwin iphonesimulator"
  "arm64 arm-apple-darwin iphoneos"
)

NGHTTP2_VERSION="1.44.0"
IPHONEOS_DEPLOYMENT_TARGET="14.2"

###############################################################################

CURL_SRC_DIR="${1:-}"

set -euo pipefail

if [ ! -d "$CURL_SRC_DIR" ]; then
  echo "Expected the cURL directory as argument"
  exit 1
fi

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

THREADS="$(sysctl -n hw.logicalcpu_max)"

DFT_DIST_DIR="${CURRENT_DIR}/dist"
DIST_DIR=${DIST_DIR:-$DFT_DIST_DIR}

BUILD_DIR="$(mktemp -d)"
CURL_BUILD_DIR="$BUILD_DIR/curl"

NGHTTP2_TARBALL_URL="https://github.com/nghttp2/nghttp2/releases/download/v${NGHTTP2_VERSION}/nghttp2-${NGHTTP2_VERSION}.tar.bz2"
NGHTTP2_DIR="$BUILD_DIR/nghttp2"
NGHTTP2_BUILD_DIR="$NGHTTP2_DIR/build"
NGHTTP2_SRC_DIR="$NGHTTP2_DIR/src"
NGHTTP2_TARBALL_PATH="$NGHTTP2_DIR/nghttp2-${NGHTTP2_VERSION}.tar.bz2"

###############################################################################

function dirname_for_slice() {
  SLICE="$1"
  read -r -a SLICE_PARTS <<< "$SLICE"
  ARCH="${SLICE_PARTS[0]}"
  HOST="${SLICE_PARTS[1]}"
  PLATFORM="${SLICE_PARTS[2]}"
  echo "$PLATFORM/$ARCH"
}

function prepare_building_for_slice() {
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
}

function build_nghttp2_slice() {
  SLICE="$1"
  read -r -a SLICE_PARTS <<< "$SLICE"
  ARCH="${SLICE_PARTS[0]}"
  HOST="${SLICE_PARTS[1]}"
  PLATFORM="${SLICE_PARTS[2]}"

  mkdir -p "$NGHTTP2_BUILD_DIR"

  SLICE_DIRNAME=$(dirname_for_slice "$SLICE")
  PREFIX="${NGHTTP2_BUILD_DIR}/${SLICE_DIRNAME}"

  if [ ! -f "$NGHTTP2_TARBALL_PATH" ]; then
    curl -Lo "$NGHTTP2_TARBALL_PATH" "$NGHTTP2_TARBALL_URL"
    (
      pushd "$NGHTTP2_DIR"
      tar -xf "$NGHTTP2_TARBALL_PATH"
      mv "nghttp2-$NGHTTP2_VERSION" "$NGHTTP2_SRC_DIR"
      popd
    )
  fi

  (
    pushd "$NGHTTP2_SRC_DIR"

    make clean || :

    ./configure \
      --disable-shared \
      --enable-lib-only \
      --host="${HOST}" --prefix="${PREFIX}"

    xcrun make -j "$THREADS"
    xcrun make install

    popd
  )
}

function build_curl_slice() {
  SLICE="$1"
  read -r -a SLICE_PARTS <<< "$SLICE"
  ARCH="${SLICE_PARTS[0]}"
  HOST="${SLICE_PARTS[1]}"
  PLATFORM="${SLICE_PARTS[2]}"

  mkdir -p "$CURL_BUILD_DIR"

  SLICE_DIRNAME=$(dirname_for_slice "$SLICE")
  PREFIX="${CURL_BUILD_DIR}/${SLICE_DIRNAME}"

  NGHTTP2_SLICE_DIR="${NGHTTP2_BUILD_DIR}/${SLICE_DIRNAME}"

  echo "BUILDING CURL FOR ${PLATFORM}"
  echo "  ARCH = ${ARCH}"
  echo "  HOST = ${HOST}"
  echo "  SDKROOT = ${SDKROOT}"
  echo "  BUILD DIR = ${PREFIX}"
  echo

  (
    pushd "$CURL_SRC_DIR"

    make clean || :

    ./configure \
      --disable-dependency-tracking \
      --disable-shared \
      --enable-static \
      \
      --disable-debug \
      --disable-curldebug \
      --enable-optimize \
      --enable-warnings \
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
      --with-nghttp2="$NGHTTP2_SLICE_DIR" \
      \
      --host="${HOST}" --prefix="${PREFIX}"

      xcrun make -j "$THREADS"
      xcrun make install

      popd
    )
}

function check_identical_headers() {
  LIB_BUILD_DIR="$1"

  # Ensure all the generated 'include' directories are identical
  for SLICE_INDEX in $(seq 1 $((${#SLICES[@]} - 1))); do
    PREV_SLICE_INDEX=$((SLICE_INDEX - 1))
    PREV_SLICE_DIR="$(dirname_for_slice "${SLICES[PREV_SLICE_INDEX]}")"
    PREV_INCLUDE_DIR="$LIB_BUILD_DIR/${PREV_SLICE_DIR}/include"

    SLICE_DIR="$(dirname_for_slice "${SLICES[$SLICE_INDEX]}")"
    INCLUDE_DIR="$LIB_BUILD_DIR/${SLICE_DIR}/include"

    if ! diff -r "$PREV_INCLUDE_DIR" "$INCLUDE_DIR" > /dev/null 2>&1 ; then
      echo "Error: The generated /include directories are not identical"
      echo "\"$PREV_INCLUDE_DIR\" and \"$INCLUDE_DIR\" are different"
      exit 2
    fi
  done
}

function build_xcframework() {
  LIBNAME="$1"
  LIB_BUILD_DIR="$2"

  # lipo slices together per platform
  # https://developer.apple.com/forums/thread/666335
  LIB_ARGS=()
  PLATFORM_COUNT=0
  for PLATFORM in "$LIB_BUILD_DIR"/*; do
    PLATFORM=$(basename "$PLATFORM")
    OUTPUT="$LIB_BUILD_DIR/$PLATFORM/lib${LIBNAME}.a"
    xcrun lipo -create "$LIB_BUILD_DIR/$PLATFORM"/*"/lib/lib${LIBNAME}.a" -output "$OUTPUT"
    LIB_ARGS+=('-library' "$OUTPUT")
    PLATFORM_COUNT=$(( PLATFORM_COUNT + 1 ))
  done

  echo

  INCLUDE_DIR="$LIB_BUILD_DIR/$(dirname_for_slice "${SLICES[0]}")/include"
  XCFRAMEWORK_PATH="$DIST_DIR/$LIBNAME.xcframework"

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

  echo "Built $LIBNAME XCFramework in $DIST_DIR"
}

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# Build a "slice" for each supported platform x arch combo
for SLICE in "${SLICES[@]}"; do
  prepare_building_for_slice "$SLICE"

  build_nghttp2_slice "$SLICE"
  build_curl_slice "$SLICE"
done

check_identical_headers "$NGHTTP2_BUILD_DIR"
check_identical_headers "$CURL_BUILD_DIR"

build_xcframework "nghttp2" "$NGHTTP2_BUILD_DIR"
build_xcframework "curl" "$CURL_BUILD_DIR"

NGHTTP2_VERSION=$(grep 'nghttp2 VERSION' "$NGHTTP2_SRC_DIR/CMakeLists.txt" | sed -Ee 's/.+VERSION ([[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+)\)/\1/')
echo "$NGHTTP2_VERSION" > "${DIST_DIR}/nghttp2.xcframework/VERSION"

CURL_VERSION=$(/usr/libexec/PlistBuddy "$CURL_SRC_DIR/lib/libcurl.plist" -c 'Print :CFBundleVersion')
echo "$CURL_VERSION" > "${DIST_DIR}/curl.xcframework/VERSION"

echo "Frameworks built successfully!"
