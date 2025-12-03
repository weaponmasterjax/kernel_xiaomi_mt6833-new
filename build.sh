#!/bin/bash

# Compile script for Hydrogen kernel
# Optimized by ChatGPT

# Prebuild hacks
rm -rf .config .config.old .tmp_versions
rm -rf include/generated include/config
rm -rf arch/arm64/include/generated
rm -rf vmlinux* System.map modules.builtin*
rm -f Module.symvers modules.order
rm -rf scripts/kconfig/.tmp*

# Date/Time
SECONDS=0
DATE=$(date '+%Y%m%d-%H%M')

# Toolchain
TC_DIR="$HOME/toolchains/neutron-clang"
CURRENT_DIR=$(pwd)

# Device Configs
DEVICE="everpal"
DEFCONFIG="${DEVICE}_defconfig"
# Read kernel localversion from defconfig (if present) and sanitize for filename
LOCALVER=""
if [ -f "arch/arm64/configs/${DEFCONFIG}" ]; then
    # Extract the value of CONFIG_LOCALVERSION if set (may contain quotes)
    LOCALVER_RAW=$(grep -E '^CONFIG_LOCALVERSION=' arch/arm64/configs/${DEFCONFIG} || true)
    if [ -n "$LOCALVER_RAW" ]; then
        # Remove prefix and strip surrounding quotes (single or double)
        LOCALVER=${LOCALVER_RAW#CONFIG_LOCALVERSION=}
        # Strip surrounding single quotes (in case)
        LOCALVER=${LOCALVER#\'}
        LOCALVER=${LOCALVER%\'}
    fi
fi

# Sanitize localversion to be filename-safe: replace non-alnum with _ and trim leading non-alnum
if [ -n "$LOCALVER" ]; then
    LOCALVER_SAFE=$(echo "$LOCALVER" | sed 's/[^A-Za-z0-9._-]/_/g' | sed 's/^[^A-Za-z0-9]*//')
    ZIPNAME="AdrenalinKernel-${DEVICE}${LOCALVER_SAFE:+-${LOCALVER_SAFE}}-${DATE}.zip"
else
    ZIPNAME="AdrenalinKernel-${DEVICE}-${DATE}.zip"
fi

# Ensure the toolchain is available
if [ ! -d "$TC_DIR" ]; then
    mkdir -p "$TC_DIR" && cd "$TC_DIR" || exit
    bash <(curl -s "https://raw.githubusercontent.com/Neutron-Toolchains/antman/main/antman") -S=05012024
    bash <(curl -s "https://raw.githubusercontent.com/Neutron-Toolchains/antman/main/antman") --patch=glibc
    cd "$CURRENT_DIR" || exit
fi

export PATH="$TC_DIR/bin:$PATH"

# Process options
CLEAN_BUILD=false
INCLUDE_KSU=false

for arg in "$@"; do
    case $arg in
        -c) CLEAN_BUILD=true ;;
        -ksu) 
            INCLUDE_KSU=true
            ZIPNAME="AdrenalinKernel-KSU-${DEVICE}-${DATE}.zip"
            ;;
    esac
done

# Perform clean build if specified
[ "$CLEAN_BUILD" = true ] && rm -rf out

# Compilation process
mkdir -p out
make O=out ARCH=arm64 "$DEFCONFIG"

echo -e "\nStarting compilation...\n"
if make -j12 O=out ARCH=arm64 CC="ccache clang" LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- Image.gz; then
    echo -e "\nKernel compiled successfully! Zipping up...\n"

    # Clone AnyKernel3 and create zip
    git clone -q --depth=1 https://github.com/weaponmasterjax/AnyKernel3 AnyKernel3
    cp out/arch/arm64/boot/Image.gz AnyKernel3
    (cd AnyKernel3 && zip -r9 "../$ZIPNAME" * -x '*.git*' README.md '*placeholder')
    rm -rf AnyKernel3 out/arch/arm64/boot

    # Clean up KernelSU changes if applied
    if [ "$INCLUDE_KSU" = true ]; then
        git restore drivers/{Makefile,Kconfig}
        rm -rf KernelSU drivers/kernelsu
    fi

    echo -e "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s)!"
    echo "Zip: $ZIPNAME"
else
    echo -e "\nCompilation failed!"
fi
