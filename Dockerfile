# A one-command toolchain image for the armv7 iOS 10.3 cross build kit.
#
#   docker build -t ios-armv7-toolchain .
#   docker run --rm ios-armv7-toolchain   # re-runs the smoke test
#
# The heavy downloads (conda cross packages ~60 MB, SDK ~80 MB) happen inside
# tools/bootstrap-toolchain.sh; mount a cache to avoid re-downloading:
#   docker run --rm -v ios-tool-cache:/opt/ios-tool/bootstrap-cache ios-armv7-toolchain
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        clang llvm lld cmake ninja-build git xz-utils zstd patch unzip \
        libplist-dev \
        autoconf automake libtool-bin pkg-config make perl python3 file \
        curl ca-certificates sudo \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . /src

# bootstrap-toolchain.sh is idempotent per stage; stages already done are
# skipped, so a cached image rebuild is cheap.
RUN tools/bootstrap-toolchain.sh --prefix=/opt/ios-tool

# The export block every build.sh expects (docs/toolchain.md section 1)
ENV IOS_SYSROOT=/opt/ios-tool/iPhoneOS10.3.sdk \
    IOS_STUBDIR=/opt/ios-tool \
    IOS_LD64=/opt/ios-tool/x-ld64/bin/x86_64-apple-darwin13.4.0-ld \
    LD_LIBRARY_PATH=/opt/ios-tool/x-libdispatch/lib:/opt/ios-tool/x-tapi/lib

CMD ["tools/bootstrap-toolchain.sh", "--stage=5", "--prefix=/opt/ios-tool"]
