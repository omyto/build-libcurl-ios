# libcurl for iOS

Build libcurl for iOS development.
This script will generate a XCFramework with embedded static libraries for arm64 and x86_64 (simulator) architectures.

The SSL library used is SecureTransport.

Script only, please download libcurl from here: http://curl.haxx.se/download.html

Tested with:

- Xcode 11.4
- macOS 10.15.3
- curl 7.69.1

# Usage

```bash
curl -O https://curl.haxx.se/download/curl-7.69.1.tar.gz
tar xf curl-7.69.1.tar.gz
bash build_libcurl_dist.sh curl-7.69.1
```

The resulting `curl.xcframework` will be created in a `dist` directory in the current directory.

# Using the created XCFramework in your project

Add the framework in the "General" tab of your target, in the "Frameworks, Libraries, and Embedded Content" section.

See [WWDC 2019 Session 416 : Binary Frameworks in Swift](https://developer.apple.com/videos/play/wwdc2019/416/) for more info.
