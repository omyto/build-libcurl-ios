#!/bin/bash

set -euo pipefail

CURLDIR="$1"

CURL_VERSION=$(grep -i CURLVERSION "$CURLDIR/Makefile")
CURL_VERSION="${CURL_VERSION//CURLVERSION = /}"

if [ ! -d "$CURLDIR" ]; then
  echo "Expected the cURL directory as argument"
  exit 1
fi

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

build_for_arch x86_64 x86_64-apple-darwin iphonesimulator || exit 2
build_for_arch arm64 arm-apple-darwin iphoneos || exit 3

# Ensure the two generated 'include' directories are identical
if ! diff -r "${TMP_DIR}"/{x86_64,arm64}/include > /dev/null 2>&1 ; then
    echo "The generated /include directories are not identical"
fi

xcrun xcodebuild -create-xcframework \
  -library "${TMP_DIR}/x86_64/lib/libcurl.a" \
  -library "${TMP_DIR}/arm64/lib/libcurl.a" \
  -headers "${TMP_DIR}/arm64/include" \
  -output "${XCFRAMEWORK_PATH}"

echo "$CURL_VERSION" > "${XCFRAMEWORK_PATH}/VERSION"

echo "Built XCFramework in $DIST_DIR"
