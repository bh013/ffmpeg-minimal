#!/bin/bash
set -ex

export NDK_VERSION="21.4.7075529"

if [ -z "$ANDROID_NDK_HOME" ]; then
    echo "ANDROID_NDK_HOME is not set. Looking for NDK in default paths..."
    if [ -d "/usr/local/lib/android/sdk/ndk/$NDK_VERSION" ]; then
        export ANDROID_NDK_HOME="/usr/local/lib/android/sdk/ndk/$NDK_VERSION"
    else
        echo "Could not find NDK."
        exit 1
    fi
fi

export API=24
export ARCH=arm
export CPU=armv7-a
export TRIPLE=arm-linux-androideabi
export CC_TRIPLE=armv7a-linux-androideabi
export TOOLCHAIN=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64
export CC=$TOOLCHAIN/bin/${CC_TRIPLE}${API}-clang
export CXX=$TOOLCHAIN/bin/${CC_TRIPLE}${API}-clang++
export AR=$TOOLCHAIN/bin/llvm-ar
export AS=$CC
export LD=$TOOLCHAIN/bin/ld.lld
export RANLIB=$TOOLCHAIN/bin/llvm-ranlib
export STRIP=$TOOLCHAIN/bin/llvm-strip
export NM=$TOOLCHAIN/bin/llvm-nm

export CFLAGS="-march=armv7-a -mfpu=neon -mfloat-abi=softfp -fPIC -O3"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-pie -lm"

PREFIX=$(pwd)/build_out
mkdir -p $PREFIX
SRC_DIR=$(pwd)/src
mkdir -p $SRC_DIR

cd $SRC_DIR

# 1. libx264
if [ ! -d x264 ]; then
  git clone --depth 1 -b stable https://code.videolan.org/videolan/x264.git
fi
cd x264
./configure --prefix=$PREFIX \
  --host=arm-linux \
  --enable-static \
  --enable-pic \
  --disable-cli \
  --cross-prefix=$TOOLCHAIN/bin/llvm- \
  --sysroot=$TOOLCHAIN/sysroot \
  --extra-cflags="$CFLAGS" \
  --extra-ldflags="$LDFLAGS"
make -j$(nproc)
make install
cd ..

# 2. libx265 (Requires cmake)
if [ ! -d x265_git ]; then
  git clone --depth 1 -b master https://bitbucket.org/multicoreware/x265_git.git
fi
cd x265_git/build/linux
cmake -G "Unix Makefiles" \
    -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
    -DANDROID_ABI=armeabi-v7a \
    -DANDROID_PLATFORM=android-$API \
    -DCMAKE_INSTALL_PREFIX=$PREFIX \
    -DENABLE_SHARED=OFF \
    -DENABLE_CLI=OFF \
    -DCROSS_COMPILE_ARM=1 \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    ../../source
make -j$(nproc)
make install
cd ../../../

# 3. libvpx
if [ ! -d libvpx ]; then
  git clone --depth 1 -b main https://chromium.googlesource.com/webm/libvpx
fi
cd libvpx
./configure --prefix=$PREFIX \
    --target=armv7-linux-gcc \
    --enable-static \
    --disable-shared \
    --enable-pic \
    --disable-examples \
    --disable-tools \
    --disable-docs \
    --disable-unit-tests
make -j$(nproc)
make install
cd ..

# 4. aom
if [ ! -d aom ]; then
  git clone --depth 1 -b main https://aomedia.googlesource.com/aom
fi
mkdir -p aom_build && cd aom_build
cmake ../aom \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=armeabi-v7a \
  -DANDROID_PLATFORM=android-$API \
  -DCMAKE_INSTALL_PREFIX=$PREFIX \
  -DENABLE_TESTS=0 \
  -DENABLE_DOCS=0 \
  -DENABLE_EXAMPLES=0 \
  -DENABLE_TOOLS=0 \
  -DBUILD_SHARED_LIBS=0 \
  -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
make install
cd ..

# 5. svtav1
if [ ! -d SVT-AV1 ]; then
  git clone --depth 1 https://gitlab.com/AOMediaCodec/SVT-AV1.git
fi
cd SVT-AV1/Build
cmake .. -G"Unix Makefiles" \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=armeabi-v7a \
  -DANDROID_PLATFORM=android-$API \
  -DCMAKE_INSTALL_PREFIX=$PREFIX \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_TESTING=OFF \
  -DBUILD_APPS=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_ASM_FLAGS="-I$TOOLCHAIN/sysroot/usr/include" \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
make -j$(nproc)
make install
cd ../..

# 6. dav1d
if [ ! -d dav1d ]; then
  git clone --depth 1 https://code.videolan.org/videolan/dav1d.git
fi
cd dav1d
cat <<EOF > cross_file.txt
[binaries]
c = '$CC'
cpp = '$CXX'
ar = '$AR'
strip = '$STRIP'
pkgconfig = 'pkg-config'

[host_machine]
system = 'android'
cpu_family = 'arm'
cpu = 'armv7-a'
endian = 'little'

[built-in options]
c_args = ['-march=armv7-a', '-mfpu=neon', '-mfloat-abi=softfp', '-fPIC']
c_link_args = ['-pie', '-lm']
EOF
meson setup build --cross-file cross_file.txt \
  --prefix=$PREFIX \
  --default-library=static \
  -Denable_tools=false \
  -Denable_tests=false \
  -Dbuildtype=release
ninja -C build install
cd ..

# 7. FFmpeg
if [ ! -d FFmpeg ]; then
  git clone --depth 1 -b release/7.0 https://github.com/FFmpeg/FFmpeg.git
fi
cd FFmpeg

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/lib/arm-linux-androideabi/pkgconfig:$PREFIX/lib64/pkgconfig"

./configure \
    --prefix=$PREFIX/ffmpeg \
    --target-os=android \
    --arch=arm \
    --cpu=armv7-a \
    --enable-cross-compile \
    --cc=$CC \
    --cxx=$CXX \
    --ld=$CC \
    --ar=$AR \
    --nm=$NM \
    --ranlib=$RANLIB \
    --strip=$STRIP \
    --extra-cflags="-I$PREFIX/include -fPIC -mfpu=neon -march=armv7-a" \
    --extra-ldflags="-L$PREFIX/lib -pie" \
    --extra-libs="-lm -lz -lpthread -lc++_static -lc++abi" \
    --enable-static \
    --disable-shared \
    --disable-debug \
    --disable-doc \
    --enable-gpl \
    --enable-version3 \
    --enable-neon \
    --enable-libx264 \
    --enable-libx265 \
    --enable-libvpx \
    --enable-libaom \
    --enable-libsvtav1 \
    --enable-libdav1d
make -j$(nproc)
mkdir -p ../../app/src/main/assets/armeabi-v7a/
cp ffmpeg ../../app/src/main/assets/armeabi-v7a/ffmpeg
cd ../..

echo "FFmpeg build complete."