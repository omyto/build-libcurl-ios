#!/bin/bash

# Configuration ###############################################################

# Each slice must follow the format "ARCH HOST PLATFORM"
SLICES=(
  "x86_64 x86_64-apple-darwin iphonesimulator"
  "arm64 arm-apple-darwin iphoneos"
)

###############################################################################

CURLDIR="${1:-}"

set -euo pipefail

if [ ! -d "$CURLDIR" ]; then
  echo "Expected the cURL directory as argument"
  exit 1
fi

CURL_VERSION=$(grep -i CURLVERSION "$CURLDIR/Makefile")
CURL_VERSION="${CURL_VERSION//CURLVERSION = /}"

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

DFT_DIST_DIR="${CURRENT_DIR}/dist"
DIST_DIR=${DIST_DIR:-$DFT_DIST_DIR}

XCFRAMEWORK_PATH="$DIST_DIR/curl.xcframework"

IPHONEOS_DEPLOYMENT_TARGET="13.0"
TMP_DIR="$(mktemp -d)"

# Remove any already existing .xcframework from the DIST_DIR
rm -rf "$XCFRAMEWORK_PATH"

function build_for_arch() {
  ARCH=$1
  HOST=$2
  PLATFORM=$3

  SDKROOT="$(xcrun --sdk "$PLATFORM" --show-sdk-path)"
  CC="$(xcrun -f clang)"
  CPP="$CC -E"
  export CC
  export CPP
  export CFLAGS="-Os -miphoneos-version-min=${IPHONEOS_DEPLOYMENT_TARGET} -isysroot ${SDKROOT}"
  export CPPFLAGS="-arch ${ARCH} -I${SDKROOT}/usr/include"
  export LDFLAGS="-arch ${ARCH} -isysroot ${SDKROOT}"

  PREFIX="${TMP_DIR}/${ARCH}"

  make clean

  echo "BUILDING FOR ${PLATFORM}"
  echo "  ARCH = ${ARCH}"
  echo "  HOST = ${HOST}"
  echo "  SDKROOT = ${SDKROOT}"
  echo ""

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
    --with-darwinssl \
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
  read -r -a SLICE <<< "$SLICE"
  ARCH="${SLICE[0]}"
  HOST="${SLICE[1]}"
  PLATFORM="${SLICE[2]}"
  build_for_arch "$ARCH" "$HOST" "$PLATFORM" || exit 1

  LIB_ARGS+=('-library' "${TMP_DIR}/${ARCH}/lib/libcurl.a")
done

# Ensure the two generated 'include' directories are identical
if ! diff -r "${TMP_DIR}"/{x86_64,arm64}/include > /dev/null 2>&1 ; then
    echo "Error: The generated /include directories are not identical"
    exit 2
fi

echo

xcrun xcodebuild -create-xcframework \
  "${LIB_ARGS[@]}" \
  -headers "${TMP_DIR}/${SLICE[0]}/include" \
  -output "${XCFRAMEWORK_PATH}"

# Fix the 'Headers' directory location in the xcframework, and update the
# Info.plist accordingly for all slices.
XCFRAMEWORK_HEADERS_PATH=$(find "${XCFRAMEWORK_PATH}" -name 'Headers')
mv "$XCFRAMEWORK_HEADERS_PATH" "$XCFRAMEWORK_PATH"

for I in $(seq 0 $((${#SLICES[@]} - 1))); do
  plutil -replace "AvailableLibraries.$I.HeadersPath" -string '../Headers' "$XCFRAMEWORK_PATH/Info.plist"
done


echo "$CURL_VERSION" > "${XCFRAMEWORK_PATH}/VERSION"

echo "Built XCFramework in $DIST_DIR"
