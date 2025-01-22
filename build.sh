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
ZIPNAME="AdrenalinKernel-V2-${DEVICE}-${DATE}.zip"

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
            ZIPNAME="AdrenalinKernel-V2-KSU-${DEVICE}-${DATE}.zip"
            ;;
    esac
done

# Perform clean build if specified
[ "$CLEAN_BUILD" = true ] && rm -rf out

# Include KernelSU if specified
if [ "$INCLUDE_KSU" = true ]; then
    echo "Including KernelSU... Save your stuff!"
    curl -LSs "https://raw.githubusercontent.com/rifsxd/KernelSU-Next/next/kernel/setup.sh" | bash -
    git clone https://github.com/cvnertnc/susfs4ksu-begonia -b kernel-4.14 temp-patch
    cd temp-patch
    cp ./kernel_patches/0001-KernelSU-Next-Implement-susfs-v1.5.3-plus-non-gki.patch ../KernelSU-Next/
    cp ./kernel_patches/fs/* ../fs/
    #cp ./kernel_patches/include/linux/* ../include/linux/
    cd ../KernelSU-Next
    patch -p1 < 0001-KernelSU-Next-Implement-susfs-v1.5.3-plus-non-gki.patch
    cd ..
    rm -rf temp-patch
fi

# Compilation process
mkdir -p out
make O=out ARCH=arm64 "$DEFCONFIG"

echo -e "\nStarting compilation...\n"
if make -j12 O=out ARCH=arm64 CC="ccache clang" LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- Image.gz; then
    echo -e "\nKernel compiled successfully! Zipping up...\n"

    # Clone AnyKernel3 and create zip
    git clone -q -b pro --depth=1 https://github.com/weaponmasterjax/AnyKernel3 AnyKernel3
    cp out/arch/arm64/boot/Image.gz AnyKernel3
    (cd AnyKernel3 && zip -r9 "../$ZIPNAME" * -x '*.git*' README.md *placeholder)
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
