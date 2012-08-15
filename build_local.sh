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

##
# build_uboot_fastboot
#
# Compiles u-boot with the environment setting CMDLINE_FLAGS=-DFORCED_ENVIRONMENT
# to build a u-boot with the environment variables in u-boot not being stored
# in NAND, but defaults only.  Needs a modified u-boot build environment.
#
# (Useful for when one wants to make a NAND update card not pay attention
# to the existing NAND environment)
##
build_uboot_fastboot()
{
	local CLEAN

	if [ "${CLEAN}" == "1" ]
	then
		rm -f build-out/u-boot-fastboot-only
        else
		if [ ! -e ${PATH_TO_UBOOT}/u-boot-fastboot-only ]
		then
			CLEAN=1 build_uboot
			CLEAN=0 CMDLINE_FLAGS="-DFORCED_ENVIRONMENT -DFASTBOOT_ONLY" build_uboot
			cp ${PATH_TO_UBOOT}/u-boot.bin ${PATH_TO_UBOOT}/u-boot-fastboot-only
			CLEAN=1 build_uboot
		fi
	fi
}

deploy_usb()
{
	check_component x-loader/x-load.bin
	check_component x-loader/x-load.bin.ift
	check_component u-boot/u-boot.bin.ift
	check_component u-boot/u-boot-fastboot-only
	check_component ${ANDROID_PRODUCT_OUT}/boot.img
	check_component ${ANDROID_PRODUCT_OUT}/system.img
	check_component ${ANDROID_PRODUCT_OUT}/userdata.img
	check_component x-loader/scripts/omap3_usbload.c
	finished_checking_components

	cd ${ROOT}

	x-loader/scripts/omap3_usbload -f x-loader/x-load_usb.bin -a 0x80400000 -f u-boot/u-boot-fastboot-only -j 0x80400000

	# Flash everything, then finish by "continuing"
	fastboot flash x-loader x-loader/x-load.bin.ift
	fastboot flash u-boot u-boot/u-boot.bin.ift
	fastboot erase u-boot-env
	fastboot flash boot
	fastboot flash system
	fastboot flash userdata
	fastboot erase cache
	fastboot reboot
}

build_omap3usbload()
{
	if [ ! -f "x-loader/scripts/omap3_usbload" ]
	then
		gcc -o x-loader/scripts/omap3_usbload x-loader/scripts/omap3_usbload.c -lusb
	fi
}



# Ensure ordering of new uboot build command.
build_del i "build images"
build_add u "build uboot_fastboot"
build_add X "build_omap3usbload"
build_add X "deploy usb" "Deploy over USB"
build_add i "build images" "Build (system/userdata/boot).img, and (root/system/userdata).tar.bz2"

build_del k "build wl12xx_modules"
