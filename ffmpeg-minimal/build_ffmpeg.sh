#!/bin/bash
set -e

# Setup paths and environment variables
export ANDROID_NDK_HOME=${ANDROID_NDK_HOME:-/usr/local/lib/android/sdk/ndk/21.4.7075529}
export TOOLCHAIN=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64
export API=24
export TARGET=armv7a-linux-androideabi
export ARCH=arm
export CPU=armv7-a

export AR=$TOOLCHAIN/bin/arm-linux-androideabi-ar
export AS=$TOOLCHAIN/bin/arm-linux-androideabi-as
export CC=$TOOLCHAIN/bin/${TARGET}${API}-clang
export CXX=$TOOLCHAIN/bin/${TARGET}${API}-clang++
export LD=$TOOLCHAIN/bin/arm-linux-androideabi-ld
export RANLIB=$TOOLCHAIN/bin/arm-linux-androideabi-ranlib
export STRIP=$TOOLCHAIN/bin/arm-linux-androideabi-strip
export NM=$TOOLCHAIN/bin/arm-linux-androideabi-nm

export PREFIX=$(pwd)/build_android
export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig

mkdir -p $PREFIX

# --- libx264 ---
if [ ! -d x264 ]; then
    git clone --depth 1 https://code.videolan.org/videolan/x264.git
fi
cd x264
./configure --prefix=$PREFIX --host=arm-linux --enable-static --disable-cli --enable-pic
make -j$(nproc)
make install
cd ..

# --- libx265 ---
if [ ! -d x265 ]; then
    git clone --depth 1 https://bitbucket.org/multicoreware/x265_git.git x265
fi
cd x265/build/arm-linux
cmake -G "Unix Makefiles" \
    -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
    -DANDROID_ABI=armeabi-v7a \
    -DANDROID_PLATFORM=android-$API \
    -DCMAKE_INSTALL_PREFIX=$PREFIX \
    -DENABLE_SHARED=OFF \
    -DENABLE_CLI=OFF \
    -DENABLE_PIC=ON \
    ../../source
make -j$(nproc)
make install
cd ../../..

# --- libvpx ---
if [ ! -d libvpx ]; then
    git clone --depth 1 https://chromium.googlesource.com/webm/libvpx
fi
cd libvpx
# libvpx might complain about target if using generic clang. We'll use armv7-android-gcc and let it use $CC we defined
./configure --prefix=$PREFIX --target=armv7-android-gcc \
    --disable-examples --disable-tools --disable-docs \
    --enable-static --disable-shared --enable-pic \
    --sdk-path=$ANDROID_NDK_HOME
make -j$(nproc)
make install
cd ..

# --- libaom ---
if [ ! -d aom ]; then
    git clone --depth 1 https://aomedia.googlesource.com/aom
fi
mkdir -p aom_build
cd aom_build
cmake -G "Unix Makefiles" \
    -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
    -DANDROID_ABI=armeabi-v7a \
    -DANDROID_PLATFORM=android-$API \
    -DCMAKE_INSTALL_PREFIX=$PREFIX \
    -DBUILD_SHARED_LIBS=0 \
    -DENABLE_EXAMPLES=0 \
    -DENABLE_TESTS=0 \
    -DENABLE_TOOLS=0 \
    ../aom
make -j$(nproc)
make install
cd ..

# --- SVT-AV1 ---
if [ ! -d SVT-AV1 ]; then
    git clone --depth 1 https://gitlab.com/AOMediaCodec/SVT-AV1.git
fi
mkdir -p SVT-AV1/build_android
cd SVT-AV1/build_android
cmake -G "Unix Makefiles" \
    -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
    -DANDROID_ABI=armeabi-v7a \
    -DANDROID_PLATFORM=android-$API \
    -DCMAKE_INSTALL_PREFIX=$PREFIX \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_APPS=OFF \
    -DBUILD_DEC=ON \
    -DBUILD_ENC=OFF \
    ..
make -j$(nproc)
make install
cd ../..

# --- libdav1d ---
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
EOF

meson setup build --cross-file cross_file.txt \
    --prefix=$PREFIX \
    --default-library=static \
    -Dbuild_tools=false \
    -Dbuild_tests=false \
    -Dbuild_examples=false \
    -Denable_asm=true
ninja -C build install
cd ..

# --- FFmpeg ---
if [ ! -d ffmpeg ]; then
    git clone --depth 1 https://git.ffmpeg.org/ffmpeg.git
fi
cd ffmpeg
./configure \
    --prefix=$PREFIX \
    --target-os=android \
    --arch=arm \
    --cpu=armv7-a \
    --enable-neon \
    --enable-cross-compile \
    --sysroot=$TOOLCHAIN/sysroot \
    --cc=$CC \
    --cxx=$CXX \
    --enable-gpl \
    --enable-libx264 \
    --enable-libx265 \
    --enable-libvpx \
    --enable-libaom \
    --enable-libsvtav1 \
    --enable-libdav1d \
    --pkg-config=pkg-config \
    --pkg-config-flags="--static" \
    --extra-cflags="-I$PREFIX/include" \
    --extra-ldflags="-L$PREFIX/lib -lm" \
    --extra-libs="-lc++_static -lm" \
    --disable-shared \
    --enable-static \
    --disable-doc \
    --disable-programs \
    --enable-ffmpeg \
    --disable-ffplay \
    --disable-ffprobe
make -j$(nproc)
make install
cd ..

cp build_android/bin/ffmpeg app/src/main/assets/armeabi-v7a/
