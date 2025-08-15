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
ZIPNAME="AdrenalinKernel-${DEVICE}-${DATE}.zip"

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

# Include KernelSU if specified
if [ "$INCLUDE_KSU" = true ]; then
    echo "Including KernelSU Next... Save your stuff!"
    curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -s v1.0.9
    git clone https://github.com/WildKernels/kernel_patches.git kernel_patches
    cd KernelSU-Next
    wget -q https://github.com/devnoname120/susfs4ksu-toco/raw/refs/heads/kernel-4.14-backport/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch
    patch -p1 --forward < 10_enable_susfs_for_ksu.patch
    for file in $(find ./kernel -maxdepth 2 -name "*.rej" -printf "%f\n" | cut -d'.' -f1); do
        echo "Patching file: $file.c with fix_$file.c.patch"
        patch -p1 --forward < "../kernel_patches/next/susfs_fix_patches/v1.5.9/fix_$file.c.patch"
    done
    sed -i '/susfs_set_kernel_sid();/d' kernel/selinux/rules.c
    cd ..
fi

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
