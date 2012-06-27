# General configuration
TARGET_UBOOT=omap3logic
TARGET_XLOADER=dm3730logic
TARGET_ANDROID=dm3730logic-eng
TARGET_KERNEL=omap3logic_android_defconfig

# The following come from u-boot/include/config.mk
UBOOT_BOARD=logic
UBOOT_VENDOR=ti
UBOOT_SOC=omap3

# Override default build scripting to use code sourcery toolchain.
KERNEL_PATH=${PATH}:${ROOT}/prebuilt/linux-x86/toolchain/CodeSourcery-arm-2009q1-203/bin
BOOTLOADER_PATH=${KERNEL_PATH}
CROSS_COMPILE=arm-none-linux-gnueabi-

build_del k  "build wl12xx_modules"
build_del k  "build sgx_modules"

