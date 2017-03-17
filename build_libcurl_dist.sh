#!/bin/bash

set -euo pipefail

readonly XCODE_DEV="$(xcode-select -p)"

CURLDIR="$1"

if [ ! -d "$CURLDIR" ]; then
  echo "Expected the cURL directory as argument"
  exit 1
fi

DFT_DIST_DIR=${HOME}/Desktop/libcurl-ios-dist
DIST_DIR=${DIST_DIR:-$DFT_DIST_DIR}

IPHONEOS_DEPLOYMENT_TARGET="12.0"
TMP_DIR="$(mktemp -d)"

function build_for_arch() {
  ARCH=$1
  HOST=$2
  PLATFORM=$3

  SDKROOT="$(xcrun --sdk "$PLATFORM" --show-sdk-path)"
  export CC="$(xcrun -f clang)"
  export CFLAGS="-Os -arch ${ARCH} -pipe -miphoneos-version-min=${IPHONEOS_DEPLOYMENT_TARGET} -isysroot ${SDKROOT}"
  export LDFLAGS="-arch ${ARCH} -isysroot ${SDKROOT}"
  PREFIX="${TMP_DIR}/${ARCH}"

  echo "BUILDING FOR ARCH ${ARCH}"
  echo "  HOST = ${HOST}"
  echo "  SDKROOT = ${SDKROOT}"
  echo ""

  ./configure \
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

mkdir -p "${TMP_DIR}/lib/"

xcrun lipo \
	-arch x86_64 "${TMP_DIR}/x86_64/lib/libcurl.a" \
	-arch arm64 "${TMP_DIR}/arm64/lib/libcurl.a" \
	-output "${TMP_DIR}/lib/libcurl.a" -create

cp -r "${TMP_DIR}/arm64/include" "${TMP_DIR}/"

mkdir -p "${DIST_DIR}"
cp -r "${TMP_DIR}/include" "${TMP_DIR}/lib" "${DIST_DIR}"
