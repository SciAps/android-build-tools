#!/bin/bash

#############################################################
# This file should remain untouched for local changes       #
#                                                           #
# Please use build_local.sh, and ~/.logicpd/android_build   #
# for local (and user) customizations.                      #
#                                                           #
# See function check_environment() for required definitions #
#############################################################

if echo $- | grep -q i
then
	echo 'Do not source the build script!'
	return
fi

SELF=`which -- $0`

# Normalize the path to the folder build.sh is located in.
cd $(readlink -f $(dirname $(which -- $SELF)))

##
# generic_error
#
# Generic error handler - it receives _ALL_ unhandled command errors.
##
generic_error()
{
        LINE=`caller | awk '{print $1}'`
        FILE=`caller | awk '{print $2}'`
        echo -e "\033[1mUnhandled error executing:\033[0m ${BASH_COMMAND}"
        echo -e "(Error at line ${LINE} in ${FILE})"
        exit 1
}

##
# Checks ot see if mkimage is installed
#
##
check_mkimage()
{
	if ! which mkimage &>/dev/null
	then
		echo "Missing tool mkimage!"
		echo "Please install package u-boot-tools (Ubuntu) for mkimage."
		echo "    sudo apt-get install u-boot-tools"
		exit 1
	fi
}

##
# Cleans up all tmp files created by mktemp_env
##
mktemp_env_cleanup()
{
	# Ensure any mount points are umounted before erasing files!
	umount_all && [ ! "${#TMP_FILES[*]}" == "0" ] && rm -rf ${TMP_FILES[*]}
}

##
# mktemp_env [env] [mktemp args]
#
# Calls mktemp, sets [env] to the result, and stores the resulting file
# in a list for cleanup when the script exits
##
mktemp_env()
{
	# Ensure the cleanup function is trapped.
	trap mktemp_env_cleanup EXIT
	local MKTEMP_OUT
	MKTEMP_OUT=`mktemp ${*:2}`
	TMP_FILES[${#TMP_FILES[*]}]="${MKTEMP_OUT}"
	eval $1=${MKTEMP_OUT}
}

##
# setup_android_env
#
# Generates and caches the android environment into
# .cached_android_env for usage in later calls to the script
##
setup_android_env()
{
	# check to make sure none of the contributing files are newer
	if [ -e "${ROOT}/.cached_android_env" ] &&
	   [ "${ROOT}/.cached_android_env" -nt "${SELF}" ] &&
	   [ "${ROOT}/.cached_android_env" -nt "build-tools/build_local.sh" ] &&
	   [ "${ROOT}/.cached_android_env" -nt "${HOME}/.logicpd/android_build" ]
	then
		source ${ROOT}/.cached_android_env
		export PATH=${PATH}${ANDROID_BUILD_PATHS}
		return
	fi

	echo "Updating Android build environment cache"
	(
		mktemp_env TMP
		mktemp_env UPT

		export > ${TMP}
		. build/envsetup.sh
		echo lunch ${TARGET_ANDROID}
		lunch ${TARGET_ANDROID}
		export `cat ${ROOT}/build/core/version_defaults.mk | grep PLATFORM_VERSION[^_].*= | tr -d ': '`
		declare -x > ${UPT}

		diff  --left-column ${TMP} ${UPT} | grep '^> ' | sed 's/^> //' | grep -v '^declare -x PATH=' | sed 's/^declare -x /export /' > .cached_android_env
		rm -f ${UPT} ${TMP}
	) > /dev/null

	source ${ROOT}/.cached_android_env
	export PATH=${PATH}${ANDROID_BUILD_PATHS}
}

if [ ! -e "build-tools/build_local.sh" ]
then
	echo "Please setup a build-tools/build_local.sh file for build customizations."
	exit 0
fi

BUILD_TARGETS=

##
# setup_default_environment
#
# Sets up default environmental settings for script in general,
# including paths, etc.  Can be overridden on a per-project basis
# later.
##
setup_default_environment()
{
	# Setup some environment variables.
	TIMEFORMAT='%R seconds'
	ROOT=${PWD}
	JOBS=8
	CLEAN=0
	VERBOSE=0
	DEV=
	EXIT_ON_ERROR=1

	PATH_TO_KERNEL=${ROOT}/kernel
	PATH_TO_UBOOT=${ROOT}/u-boot
	PATH_TO_XLOADER=${ROOT}/x-loader

	export ARCH=arm
	export CROSS_COMPILE=arm-eabi-

	BOOTLOADER_PATH=${ROOT}/prebuilt/linux-x86/toolchain/arm-eabi-4.4.0/bin:${PATH}
	KERNEL_PATH=${ROOT}/prebuilt/linux-x86/toolchain/arm-eabi-4.4.3/bin:${PATH}
	ORIG_PATH=${PATH}

	export PATH=${BOOTLOADER_PATH}
	
	if [ -f /etc/gentoo-release ]
	then
		# If we're on Gentoo, we can easily specify what java toolset we want to use
		export GENTOO_VM=sun-jdk-1.6
		export PATH=$(java-config -O)/bin:${PATH}
	fi
}

check_environment()
{
	if [ "${TARGET_UBOOT}" == "" ] ||
	   [ "${TARGET_XLOADER}" == "" ] ||
	   [ "${TARGET_ANDROID}" == "" ] ||
	   [ "${TARGET_KERNEL}" == "" ] ||
	   [ "${UBOOT_BOARD}" == "" ] ||
	   [ "${UBOOT_VENDOR}" == "" ] ||
	   [ "${UBOOT_SOC}" == "" ]
	then
		echo "Please setup build_local.sh properly."
		exit 0
	fi
}

##
# array_delete_index [array_env] [index to delete]
#
# Removes an index from an array, and moves all existing entries
# up one index to compensate for index removed.
##
array_delete_index()
{
	local i
	local start
	local cnt
	local end

	start=${2}
	cnt=$(eval echo \${#"${1}"[*]})
	end=$((cnt))

	for((i=start;i<end;++i))
	do
		POS_CUR=$1'['$i']'
		POS_NEXT='${'$1'['$((i+1))']}'
		eval ${POS_CUR}=${POS_NEXT}
	done
	eval unset $1'['$((i-1))']'
}

##
# array_insert_index [array_env] [index to insert]
#
# Inserts an empty index into given index position, and pushes back
# the rest of the array to compensate.
##
array_insert_index()
{
	local i
	local start
	local cnt
	local end

	start=${2}
	cnt=$(eval echo \${#"${1}"[*]})
	end=$((cnt))

	for((i=end;i>=start;--i))
	do
		POS_CUR=$1'['$i']'
		POS_NEXT='${'$1'['$((i-1))']}'
		eval ${POS_CUR}=${POS_NEXT}
	done
	eval $1'['$((i+1))']'="${3}"
}

##
# build_add [command line option] [command to run] [help for command]
#
# Adds a build option into the build system.
##
build_add()
{
	local cnt=${#BUILD_OPTION[*]}

	# Add a build target
	BUILD_OPTION[${#BUILD_OPTION[*]}]="$1"
	BUILD_COMMAND[${cnt}]="$2"
	BUILD_HELP[${cnt}]="${*:3}"
}

##
# build_del [command line option] [command to run]
#
# Finds a specific command line option/command to run combination, removes it,
# and removes its help.  Useful for local customizations.
##
build_del()
{
	local i
	for ((i=0;i<${#BUILD_OPTION[*]};++i))
	do
		if [ "${BUILD_OPTION[i]}" == "$1" ] &&
		   [ "${BUILD_COMMAND[i]}" == "$2" ]
		then
			array_delete_index BUILD_OPTION ${i}
			array_delete_index BUILD_COMMAND ${i}
			array_delete_index BUILD_HELP ${i}
			return
		fi
	done
}

##
# copy_function [original] [new]
#
# Copies a function from one name, to another name.
#
# copy_function() taken from
# http://stackoverflow.com/questions/1203583/how-do-i-rename-a-bash-function
##
copy_function() {
	declare -F $1 > /dev/null || return 1
	eval "$(echo "${2}()"; declare -f ${1} | tail -n +2)"
}

##
# bytes_to_human_readable [size]
#
# Formats the argument [size] into human readable sizes.
##
bytes_to_human_readable()
{
	local spaces="     "
	local prefix=" kMGTPE"
	local val=$1
	local pos=0
	local precision=10
	local divider=1024
	local compare
	local digits
	local end

	((val = val * precision))
	((compare = divider * precision))
	while [ ${val} -gt ${compare} ]
	do
		((pos++))
		((val = val / divider))
	done

	digits=${#val}
	((end=digits-${#precision}+1))
	echo "${spaces:digits}${val::end}.${val:end}${prefix:pos:1}B"
}

##
# is_valid_removable_device [block name]
#
# Checks to see if a given removable device is valid (e.g. seems to be a SD type device)
is_valid_removable_device()
{
	local capability

	capability=0x0`cat /sys/block/$1/capability 2>/dev/null`

	if (( (capability & 0x41) == 0x41 )) &&
	   [ "`cat /sys/class/block/$1/size`" != "0" ]
	then
		return 0
	fi
	return 1
}

##
# find_removable_devices [environment variable]
#
# Sets the environment variable to the list of all devices available
# in the systemthat have the "removable" attribute.  Useful for 
# finding SD cards.
#
# (Looks for GENHD_FL_EXT_DEVT and GENHD_FL_REMOVABLE
#  in the capability file)
##
find_removable_devices()
{
	local i
	local dev
	local capability
	local cnt=0

	for i in /sys/block/*
	do
		dev=`echo $i | awk -F / '{print $4}'`
		if is_valid_removable_device ${dev}
		then
			eval $1[$cnt]=${dev}
			((cnt++)) || true
		fi
	done
}

##
# choose_removable_device
#
# Presents a user with a list of removable devices to choose from, and
# stores the result into the environment variable DEV
##
choose_removable_device()
{
	local DEV_LIST[0]
	local i

	if is_valid_removable_device ${DEV}
	then
		return 0
	fi

	if [ ! "${DEV}" == "" ]
	then
		echo "Overriding invalid device selection ${DEV}"
	fi

	while true
	do
		find_removable_devices DEV_LIST

		if [ "${#DEV_LIST[*]}" == "0" ]
		then
			echo "Error: No possible SD devices found on system."
			return 1
		fi

		# The following hack for TAB completion is from
		# http://www.linuxquestions.org/questions/linux-general-1/commandline-autocompletion-for-my-shell-script-668388/
		set -o emacs
		bind 'set show-all-if-ambiguous on'
		bind 'set completion-ignore-case on'
		COMP_WORDBREAKS=${COMP_WORDBREAKS//:}
		bind 'TAB:dynamic-complete-history'
		for i in ${DEV_LIST[*]} ; do
			history -s $i
		done

		echo Devices available:
		for i in ${DEV_LIST[*]}
		do
			local size
			size=$((`cat /sys/block/${i}/size`*512))
			size=`bytes_to_human_readable ${size}` || true

			echo "  ${i} is ${size} - `cat /sys/block/${i}/device/model`"
		done

		read -ep "Enter device: " DEV
		if is_valid_removable_device ${DEV}
		then
			if ! sudo -v -p "Enter %p's password, for SD manipulation permissions: "
			then
				echo "Cannot continue; you did not authenticate with sudo."
				return 1
			fi
			sleep 1
			echo
			return 0
		fi
		echo "Enter a valid device."
		echo "You can choose one of ${DEV_LIST[*]}"
	done
}

##
# find_device_partition [env] [dev] [number]
#
# Finds a device's partition name for a specific number.
# It compensates for cases such as mmcblk0p1, etc.
##
find_device_partition()
{
	local find_part
	local I
	for I in /sys/block/$2/*/partition
	do
		find_part=`echo $I | awk -F / '{print $5}'`
		if echo ${find_part} | grep -q "[^0123456789]$3\$"
		then
			eval $1=${find_part}
			return 0
		fi
	done
	echo "Unable to find partition #$3 for $2"
	return 1
}

##
# umount_device [dev]
#
# Finds all mountings of a given device, and unmounts them
##
unmount_device()
{
	local I
	local MNT_POINTS

	choose_removable_device

	MNT_POINTS=`cat /proc/mounts | grep $DEV | awk '{print $2}'`
	for I in ${MNT_POINTS}
	do
		echo "Unmounting ${I}"
		sudo umount ${I} || return 1
	done
}

##
# format_device
#
# Formats a removable device chosen by the user with two partitions
# 1. FAT
# 2. EXT2
##
format_device()
{
	local answer
	local part1
	local part2
	local size

	choose_removable_device

	# Unmount the device
	unmount_device || return 1

	# Run FDISK

	size=$((`cat /sys/block/${DEV}/size`*512))
	size=`bytes_to_human_readable ${size}` || true

	echo "About to erase and format $DEV (${size} - `cat /sys/block/${DEV}/device/model`)"
	echo -n "Do you wish to continue? (y/N) "
	read answer
	if [ "${answer^*}" == "Y" ]
	then
		sudo -v
		echo "Partitioning $DEV."
		sudo fdisk /dev/$DEV >/dev/null 2>&1 <<EOF
o
x
h
255
s
63
c
$NUMCYL
r
n
p
1

+300M
t
c
a
1
n
p
2


w
EOF
		# Wait a little bit for devices to appear in /dev
		sleep 2

		find_device_partition part1 ${DEV} 1
		find_device_partition part2 ${DEV} 2

		echo "Formatting SD card."

		sudo mkfs.vfat -F 32 -n boot /dev/${part1} > /dev/null 2>&1
		sudo mkfs.ext3 -L rootfs /dev/${part2} > /dev/null 2>&1
	else
		exit 1
	fi
}

##
# mount_bootloader
#
# Mounts partition 1 of the device specified in DEV, and stores the
# mount point location in ${MNT_BOOTLOADER}
##
mount_bootloader()
{
	local part

	if [ "${MNT_BOOTLOADER}" == "" ]
	then
		choose_removable_device
		mktemp_env MNT_BOOTLOADER -d
		find_device_partition part ${DEV} 1
		echo "Mounting bootloader partition"
		sudo mount /dev/${part} ${MNT_BOOTLOADER} -o uid=`id -u`
	fi
}

##
# mount_root
#
# Mounts partition 2 of the device specified in DEV, and stores the
# mount point location in ${MNT_ROOT}
##
mount_root()
{
	local part

	if [ "${MNT_ROOT}" == "" ]
	then
		choose_removable_device
		mktemp_env MNT_ROOT -d
		find_device_partition part ${DEV} 2
		echo "Mounting root partition"
		sudo mount /dev/${part} ${MNT_ROOT}
	fi
}

##
# build_info [message]
#
# Prints to file descriptor 3 a message passed in the command line arguments.  Used
# for printing a message while inside a build that has verbosity turned off.
##
build_info()
{
	echo -en "\033[1m$* - \033[0m" 1>&3
}

##
# umount_all
#
# Unmounts all partitions mounted in the script - specifically, MNT_BOOTLOADER and
# MNT_ROOT.
##
umount_all()
{
	if [ ! "${MNT_BOOTLOADER}" == "" ] ||
	   [ ! "${MNT_ROOT}" == "" ]
	then
		echo "Flushing data to SD card"
		sync
	fi

	cd ${ROOT}

	if [ ! "${MNT_BOOTLOADER}" == "" ]
	then
		echo "Unmounting bootloader partition"
		sudo umount ${MNT_BOOTLOADER}
		rmdir ${MNT_BOOTLOADER}
		MNT_BOOTLOADER=
	fi

	if [ ! "${MNT_ROOT}" == "" ]
	then
		echo "Unmounting root partition"
		sudo umount ${MNT_ROOT}
		rmdir ${MNT_ROOT}
		MNT_ROOT=
	fi
}

##
# check_component [filename]
#
# Checks to see if a given file is in the filesystem.  If it isn't, it prints
# a warning and exits.
##
check_component()
{
	if [ ! -e ${1} ]
	then
		echo "Missing \"${1}\"! Cannot continue."
		exit 1
	fi
}

##
# copy_reflash_nand_sd [destination folder]
#
# Copies the filelist for a reflash nand SD to a given target folder.
##
copy_reflash_nand_sd()
{
	echo "Copying reflash nand SD components."
	cd ${ROOT}
	mkdir -p $1/update

	# Update x-loader in place if possible.
	cat ${PATH_TO_XLOADER}/x-load.bin.ift                                 > $1/MLO
	cp ${LINK} ${PATH_TO_UBOOT}/u-boot-no-environ_bin                       $1/u-boot.bin
	cp ${LINK} ${PATH_TO_XLOADER}/x-load.bin.ift                            $1/update/MLO
	cp ${LINK} ${PATH_TO_UBOOT}/u-boot.bin.ift                              $1/update
	cp ${LINK} ${ANDROID_PRODUCT_OUT}/boot.img                              $1/update/uMulti-Image
	cp ${LINK} ${ANDROID_PRODUCT_OUT}/system.img                            $1/update
	cp ${LINK} ${ANDROID_PRODUCT_OUT}/userdata.img                          $1/update
	cp ${LINK} device/logicpd/${TARGET_PRODUCT}/android.bmp                 $1/update
	cp ${LINK} device/logicpd/${TARGET_PRODUCT}/android2.bmp                $1/update
	cp ${LINK} device/logicpd/${TARGET_PRODUCT}/done.bmp                    $1/update
	mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n \
	        "Logic PD Android SD Boot" -d \
        	device/logicpd/${TARGET_PRODUCT}/reflash_nand.cmd \
		${1}/boot.scr > /dev/null 2>&1
}

##
# copy_update_cache [destination folder]
#
# Copies the filelist for the update cache script to a given target folder.
##
copy_update_cache()
{
	check_mkimage

	cd ${ROOT}
	mkdir -p $1

	cp ${LINK} ${PATH_TO_UBOOT}/u-boot.bin.ift                              $1
	cp ${LINK} ${PATH_TO_XLOADER}/x-load.bin.ift                            $1/MLO
	cp ${LINK} ${ANDROID_PRODUCT_OUT}/boot.img                              $1/uMulti-Image
	cp ${LINK} ${ANDROID_PRODUCT_OUT}/system.img                            $1
	cp ${LINK} ${ANDROID_PRODUCT_OUT}/userdata.img                          $1
	mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Update Script" \
		-d build-tools/remote_update_info/updatescr.txt \
		$1/updatescr.upt > /dev/null 2>&1
}

##
# deploy_build_out
#
# Copies files (or links) from the actual build output folder into build-out/
# to make it easier to find the various files created by the build system
##
deploy_build_out()
{
	if [ "$CLEAN" == "1" ]
	then
		echo "Removing build-out."
		rm -Rf build-out
		return 0
	fi

	cd ${ROOT}

	# Check necessary files.
	check_component ${PATH_TO_XLOADER}/x-load.bin.ift
	check_component ${PATH_TO_UBOOT}/u-boot.bin
	check_component ${PATH_TO_UBOOT}/u-boot-no-environ_bin
	check_component ${ANDROID_PRODUCT_OUT}/boot.img
	check_component ${ANDROID_PRODUCT_OUT}/system.img
	check_component ${ANDROID_PRODUCT_OUT}/userdata.img
	
	mkdir -p build-out/reflash_nand_sd/update
	mkdir -p build-out/update_cache

	rm -Rf build-out
	mkdir -p build-out
	
	# Copy over x-loader binaries
	cp -l ${PATH_TO_XLOADER}/x-load.bin.ift build-out/MLO

	# Copy over u-boot binaries
	cp -l ${PATH_TO_UBOOT}/u-boot.bin     build-out/
	cp -l ${PATH_TO_UBOOT}/u-boot.bin.ift build-out/

	# Copy over to reflash_nand_sd
	LINK=-l copy_reflash_nand_sd build-out/reflash_nand_sd/

	# Copy over to update_cache
	LINK=-l copy_update_cache build-out/update_cache/
}

deploy_sd_unmount_all_and_check()
{
	if umount_all
	then
		if cat /proc/mounts | grep -q ${DEV}
		then
			echo -e "Image deployed, but \033[1mthe SD card is mounted by the system.\033[0m"
			echo "Please safely remove your SD card."
		else
			echo "Image deployed. SD card can be removed."
		fi
	else
		echo "Image deployment failed!"
	fi
}

##
# deploy_sd
#
# Creates a bootable SD card that runs the entire android environment
# off of the SD card.
##
deploy_sd()
{
	check_mkimage

	local TMP_INIT

	if [ "$CLEAN" == "1" ]
	then
		echo "Nothing to be done for clean when deploying to SD"
		return 0
	fi

	cd ${ROOT}

	# Check necessary files.
	check_component ${PATH_TO_XLOADER}/x-load.bin.ift
	check_component ${PATH_TO_UBOOT}/u-boot.bin
	check_component ${PATH_TO_KERNEL}/arch/arm/boot/uImage
	check_component ${ANDROID_PRODUCT_OUT}/root.tar.bz2
	check_component ${ANDROID_PRODUCT_OUT}/system.tar.bz2
	check_component ${ANDROID_PRODUCT_OUT}/userdata.tar.bz2

	mount_bootloader
	mount_root

	# Using CAT to update the MLO file inplace;
	# this way it doesn't break the ability to boot.
	cat ${PATH_TO_XLOADER}/x-load.bin.ift > ${MNT_BOOTLOADER}/MLO
	cp ${PATH_TO_UBOOT}/u-boot.bin ${MNT_BOOTLOADER}
	cp ${PATH_TO_KERNEL}/arch/arm/boot/uImage ${MNT_BOOTLOADER}
	mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n \
	        "Logic PD Android SD Boot" -d \
        	device/logicpd/${TARGET_PRODUCT}/boot_sd.cmd \
		${MNT_BOOTLOADER}/boot.scr > /dev/null 2>&1

	# Install root files from the various tarballs
	cd ${MNT_ROOT}
	sudo rm -Rf ${MNT_ROOT}/*

	echo Extracting root tarball
	sudo tar --numeric-owner -xjf ${ANDROID_PRODUCT_OUT}/root.tar.bz2

	echo Extracting system tarball
	sudo tar --numeric-owner -xjf ${ANDROID_PRODUCT_OUT}/system.tar.bz2

	echo Extracting userdata tarball
	sudo tar --numeric-owner -xjf ${ANDROID_PRODUCT_OUT}/userdata.tar.bz2

	echo Filtering init.rc for mtd mount commands
	mktemp_env TMP_INIT
	sudo cat init.rc | egrep -v 'mount.*(mtd@|rootfs.*remount)' > ${TMP_INIT}
	sudo cp ${TMP_INIT} init.rc
	rm ${TMP_INIT}

	deploy_sd_unmount_all_and_check
}

##
# deploy_nand
#
# Creates a SD card that burns everything needed to boot Android
# out of NAND, into NAND.  This includes the bootloader, kernel, and
# userspace environment.
##
deploy_nand()
{
	if [ "$CLEAN" == "1" ]
	then
		echo "Nothing to be done for clean when deploying to SD NAND"
		return 0
	fi

	cd ${ROOT}

	# Check necessary files.
	check_component ${PATH_TO_XLOADER}/x-load.bin.ift
	check_component ${PATH_TO_UBOOT}/u-boot.bin
	check_component ${PATH_TO_UBOOT}/u-boot-no-environ_bin
	check_component ${ANDROID_PRODUCT_OUT}/boot.img
	check_component ${ANDROID_PRODUCT_OUT}/system.img
	check_component ${ANDROID_PRODUCT_OUT}/userdata.img

	mount_bootloader

	# Install root files from the various tarballs
	rm -Rf ${MNT_BOOTLOADER}/update
	mkdir -p ${MNT_BOOTLOADER}/update
	copy_reflash_nand_sd ${MNT_BOOTLOADER}/

	deploy_sd_unmount_all_and_check
}

##
# deploy_update_zip
#
# Creates an update.zip file that can be used with
#
#    fastboot update update.zip
#
# to update the NAND file system and kernel.
##
deploy_update_zip()
{
	if [ "$CLEAN" == "1" ]
	then
		echo "Removing update.zip"
		rm ${ROOT}/update.zip
		return 0
	fi

	cd ${ROOT}

	check_component ${ANDROID_PRODUCT_OUT}/boot.img
	check_component ${ANDROID_PRODUCT_OUT}/system.img
	check_component ${ANDROID_PRODUCT_OUT}/userdata.img

	cd ${ANDROID_PRODUCT_OUT}
	zip ${ROOT}/update.zip boot.img system.img userdata.img android-info.txt

	cd ${ROOT}
}

##
# deploy_newer
#
# Pushes files over ADB that are newer than the currently built system.img and userdata.img.
##
deploy_newer()
{
	if [ "$CLEAN" == "1" ]
	then
		echo "Nothing to be done for clean with deploy newer."
	fi

	cd ${ANDROID_PRODUCT_OUT}
	find system -type f -newer system.img   -print -exec adb push '{}' /'{}' ';'
	find data   -type f -newer userdata.img -print -exec adb push '{}' /'{}' ';'
}

##
# update_boot_img
#
# Creates boot.img if the requisite files are present.
##
update_boot_img()
{
	check_mkimage

	if [ -e "${PATH_TO_KERNEL}/arch/arm/boot/zImage" ] &&
	   [ -e "${ANDROID_PRODUCT_OUT}/ramdisk.img" ]
	then
		# Create boot.img
		mkimage -A arm -O linux -T multi -C none -a 0x82000000 -e 0x82000000 -n 'Logic PD' \
			-d ${PATH_TO_KERNEL}/arch/arm/boot/zImage:${ANDROID_PRODUCT_OUT}/ramdisk.img \
			${ANDROID_PRODUCT_OUT}/boot.img
	fi
}

##
# build_android
#
# Builds the Android environment
##
build_android()
{
	cd ${ROOT}

	if [ "$CLEAN" == "0" ]
	then
		make -j${JOBS}
		update_boot_img
	else
		make -j${JOBS} clean
	fi
}

##
# uboot_check_config
#
# Checks to see if the uboot configuration needs to be changed to match the
# configuration choices present in the script by inspecting u-boot/include/config.mk
##
uboot_check_config()
{
	local BOARD
	local VENDOR
	local SOC

	BOARD=`cat include/config.mk 2>/dev/null | awk '/BOARD/ {print $3}'`
	VENDOR=`cat include/config.mk 2>/dev/null | awk '/VENDOR/ {print $3}'`
	SOC=`cat include/config.mk 2>/dev/null | awk '/SOC/ {print $3}'`

	# If the configuration isn't set, set it.
	if [ ! "$UBOOT_BOARD" == "$BOARD" ] ||
	   [ ! "$UBOOT_VENDOR" == "$VENDOR" ] ||
	   [ ! "$UBOOT_SOC" == "$SOC" ]
	then
		make ${TARGET_UBOOT}_config
	fi
}

##
# build_uboot
#
# Compiles u-boot
##
build_uboot()
{
	cd ${PATH_TO_UBOOT}

	PATH=${BOOTLOADER_PATH}	

	if [ "$CLEAN" == "0" ]
	then
		uboot_check_config
		make -j${JOBS}
	else
		make -j${JOBS} distclean
		rm -f include/config.mk
	fi
}

##
# build_uboot_no_env
#
# Compiles u-boot with the environment setting CMDLINE_FLAGS=-DFORCED_ENVIRONMENT
# to build a u-boot with the environment variables in u-boot not being stored
# in NAND, but defaults only.  Needs a modified u-boot build environment.
#
# (Useful for when one wants to make a NAND update card not pay attention
# to the existing NAND environment)
##
build_uboot_no_env()
{
	local CLEAN

	if [ "${CLEAN}" == "1" ]
	then
		rm -f build-out/u-boot-no-environ_bin
	else
		if [ ! -e ${PATH_TO_UBOOT}/u-boot-no-environ_bin ]
		then
			CLEAN=1 build_uboot
			CLEAN=0 CMDLINE_FLAGS=-DFORCED_ENVIRONMENT build_uboot
			cp ${PATH_TO_UBOOT}/u-boot.bin ${PATH_TO_UBOOT}/u-boot-no-environ_bin
			CLEAN=1 build_uboot
		fi
	fi
}

##
# build_xloader
#
# Builds x-loader.
##
build_xloader()
{
	local PATH
	local TARGET

	cd ${PATH_TO_XLOADER}
	PATH=${BOOTLOADER_PATH}
	TARGET=`cat include/config.mk 2>/dev/null | awk '/BOARD/ {print $3}'`

	if [ "$CLEAN" == "0" ]
	then
		# If the configuration isn't set, set it.
		if [ ! "$TARGET_XLOADER" == "$TARGET" ]
		then
			make ${TARGET_XLOADER}_config
		fi

		# X-Loader sometimes fails with multiple build jobs.
		make
	else
		make -j${JOBS} distclean
		rm -f include/config.mk
	fi
}

##
# build_kernel
#
# Builds the kernel (and modules)
##
build_kernel()
{
	local PATH

	cd ${PATH_TO_KERNEL}
	PATH=${KERNEL_PATH}

	if [ "$CLEAN" == "0" ]
	then
		if [ ! -e ".config" ] 
		then
			echo "Using default kernel configuration."
			make ${TARGET_KERNEL} -j${JOBS} && make uImage modules -j${JOBS}
		else
			echo "Using existing kernel configuration."
			echo "To reset to default configuration, do:"
			echo "  cd kernel"
			echo "  ARCH=arm make ${TARGET_KERNEL}"
			echo ""
			make uImage modules -j${JOBS}
		fi
		update_boot_img
	else
		make clean -j${JOBS}
	fi
}

##
# build_sub_module [path] [arguments to make]
#
# Builds a folder with the intention that the folder run against
# the kernel make system.  Used for build_sgx_modules and
# build_wl12xx_modules.
##
build_sub_module()
{
	local CMD
	local PATH

	cd ${ROOT}
	CMD="make -C $* ANDROID_ROOT_DIR=${ROOT} -j${JOBS}"
	PATH=${KERNEL_PATH}

	if [ "$CLEAN" == "0" ]
	then
		echo ${CMD}
		${CMD}
		${CMD} install
	else
		${CMD} clean
	fi
}

##
# build_sgx_modules
#
# Builds the SGX kernel modules.
##
build_sgx_modules()
{
	local TARGET_ROOT

	if [ "$CLEAN" == "0" ] && 
           [ ! -e "${ANDROID_PRODUCT_OUT}/obj/lib/crtbegin_dynamic.o" ]
	then
		build_info needs Android built to finish
		return 0
	fi

	# The make files for sgx are looking for the variable TARGET_ROOT
	# to help determine the version of android we're running.
	TARGET_ROOT=${ROOT}

	# Make sure the output folder exists (the compile requires this!)
	[ "$CLEAN" == "0" ] && mkdir -p ${ANDROID_PRODUCT_OUT}

	build_sub_module hardware/ti/sgx OMAPES=5.x PLATFORM_VERSION=${PLATFORM_VERSION}
}

##
# build_wl12xx_modules
#
# Builds the wl12xx kernel modules
##
build_wl12xx_modules()
{
        build_sub_module hardware/ti/wlan/WL1271_compat/drivers
}

##
# build_images
#
# Ensures the Android images are in a sane state; i.e. by wiping
# the currently generated system.img, userdata.img, etc, and calling
# the build system again.
##
build_images()
{
	# Remove old, stale image files.
	rm -f `find out -iname system.img`
	rm -f `find out -iname system.tar.bz2`
	rm -f `find out -iname userdata.img`
	rm -f `find out -iname userdata.tar.bz2`
	rm -f `find out -iname ramdisk.img`
	rm -f `find out -iname boot.img`

	if [ "${CLEAN}" == "1" ]
	then
		# Force removal of output folders
		rm -Rf ${ANDROID_PRODUCT_OUT}/root
		rm -Rf ${ANDROID_PRODUCT_OUT}/data
		rm -Rf ${ANDROID_PRODUCT_OUT}/system
	else
		# Do normal Android image creation (including tarball images)
		make systemimage userdataimage ramdisk systemtarball userdatatarball

		# Create root.tar.bz2
		cd ${ANDROID_PRODUCT_OUT}
		../../../../build/tools/mktarball.sh ../../../host/linux-x86/bin/fs_get_stats root . root.tar root.tar.bz2
		cd ${ROOT}

		# Create boot.img
		update_boot_img
	fi
}

##
# build_fastboot [arg]
#
# Calls
#
#    fastboot flash [arg]
#
# when [arg] is not "all".  Otherwise, it calls boot, system, and userdata
# in lieu of "all" when all is specified.
##
build_fastboot()
{
	if [ "$1" == "all" ]
	then
		fastboot flash boot
		fastboot flash system
		fastboot flash userdata
		fastboot reboot
	else
		fastboot flash $1
	fi
}

##
# build_error
#
# Callback for build errors via "trap".  Causes the function
# called to exit back out to the build() routine upon any error.
##
build_error()
{
	exit 1
}

##
# build [target] [args to target]
#
# Calls
#
#    build_[target] [args to target]
#
# wrapped around storing the output into a temporary file in /tmp
# as well as managing verbosity, and timing of how long the build
# took.
##
build()
{
	local ERR=0
	local TMP
	local TIME
	local NAME
	local VERB
	local VERB_ACTIVE

	mktemp_env TMP
	mktemp_env TIME

	if [ "${CLEAN}" == "1" ]
	then
		VERB="clean"
		VERB_ACTIVE="cleaning"
	else
		VERB="build"
		VERB_ACTIVE="building"
	fi

	NAME=`printf "%-15s" ${1}`

	echo -en "${VERB_ACTIVE^*} ${NAME}"

	if [ "${VERBOSE}" == "1" ]
	then
		echo ""
		set +E
		trap - ERR
		time ((
			trap build_error ERR
			set -E
			build_$1 2>&1
		      ) | tee ${TMP}
		      [ "${PIPESTATUS[0]}" == "0" ] || false
		     ) 2>${TIME}
		[ ! "$?" == "0" ] && ERR=1
		echo -en "Finished ${VERB_ACTIVE} ${NAME} - "
		trap generic_error ERR
		set -E
	else
		echo -en " - "
		set +E
		trap - ERR
		time (
			trap build_error ERR
			set -E
			build_$1 &> ${TMP}
		     ) 2> ${TIME}
		[ ! "$?" == "0" ] && ERR=1
		trap generic_error ERR
		set -E
	fi

	if [ "$ERR" != "0" ]
	then
		echo -en "failure ${VERB_ACTIVE}.\nSee ${ROOT}/error.log.\n"
		mv ${TMP} ${ROOT}/error.log
		if [ "${EXIT_ON_ERROR}" == "1" ]
		then
			rm ${TIME}
			exit 1
		fi
	else
		echo -en "took "
		echo -en `cat ${TIME}`
		echo -e " to ${VERB}."
		rm ${TMP}
	fi
	rm ${TIME}

	return ${ERR}
}

##
# deploy_fastboot
#
# Waits for device to be present in fastboot mode, builds the kernel, and sends it.
# If the kernel build has issues, it views error.log, and rebuilds the kernel after
# the user as finished looking at the error log.
##
deploy_fastboot()
{
	if [ "$CLEAN" == "1" ]
	then
		echo "Nothing to do for clean while deploying to fastboot."
		return 0
	fi

	while true
	do
		echo "Waiting for device"
		while [ "`fastboot devices | wc -l`" == "0" ]
		do
			sleep 1
		done

		while ! EXIT_ON_ERROR=0 build kernel
		do
			less ${ROOT}/error.log
		done
		fastboot boot ${ANDROID_PRODUCT_OUT}/boot.img
		sleep 10
	done
}


##
# deploy [target] [target arguments]
#
# Wrapper for calling
#
#    deploy_[target] [arguments]
#
# while giving a common header for all deploy targets.
##
deploy()
{
	echo "Deploying to $1"
	deploy_$1 ${*:2}
}

##
# print_help_match_cmd [match]
#
# Finds all help for any command starting with [match] added
# by "build_add" to the build system, and removes the help
# associated with the command after.
##
print_help_match_cmd()
{
	local match=$1
	local tmp
	local i

	for ((i=0;i<${#BUILD_OPTION[*]};++i))
	do
		tmp=${BUILD_COMMAND[i]}
		tmp=${tmp:0:${#match}}

		if [ ! "${BUILD_HELP[i]}" == "" ] &&
		   [ "${tmp}" == "${match}" ]
		then
			if [ "${BUILD_OPTION[i]:1:2}" == ":" ]
			then
				echo "  -${BUILD_OPTION[i]:0:1} [arg] ${BUILD_HELP[i]}"
			else
				echo "  -${BUILD_OPTION[i]:0:1}       ${BUILD_HELP[i]}"
			fi
			eval unset BUILD_HELP[$i]
		fi
	done
}

##
# print_help
#
# Prints help for build targets, deployment options, and other misc. commands.
##
print_help()
{
	cat <<-EOF
		Usage: $0:
		 Targets:
		  -A       Build all, and deploy to build-out
	EOF
	print_help_match_cmd "build "
	echo -e "\n Deployment options:"
	print_help_match_cmd "deploy "
	cat <<-EOF
		
		 Job options:
		  -j [num] How many simultaneous compiles to run (currently ${JOBS})
		  -c       Clean object files
	
		 Misc options:
		  -D [dev] Specify a device, such as "sdb" to use for SD deployment options
	EOF

	print_help_match_cmd ""

	exit 2
}

##
# build_all
#
# Finds all commands added to the build system with "build " at the
# front of the command and runs them.
##
build_all()
{
	local i
	local match="build "
	for ((i=0;i<${#BUILD_OPTION[*]};++i))
	do
		tmp=${BUILD_COMMAND[i]}
		tmp=${tmp:0:${#match}}

		if [ "${tmp}" == "${match}" ]
		then
			eval ${BUILD_OPTION[i]:0:1}flag=1
		fi
	done
}

##
# choose_options [command line arguments to script]
#
# Parses command line arguments against build options added by
# "build_add" to the script.
##
choose_options()
{
	local count=
	local availopts=Aj:cvh?D:

	for ((i=0;i<${#BUILD_OPTION[*]};++i))
	do
		OPT=`eval echo $"${BUILD_OPTION[i]}"`
		CMD=`eval echo $"${BUILD_COMMAND[i]}"`
		FLAG=${OPT:0:2}
		availopts=${availopts}${FLAG}
	done
	
	while getopts ${availopts} name
	do
		eval count=$((count+1))
		case $name in
			A) build_all;Bflag=1;;
			D) DEV="$OPTARG";;
			j) JOBS="$OPTARG";;
			c) CLEAN=1;;
			v) VERBOSE=1;;
			\?) hflag=1;;
			*) eval ${name}flag=1;eval ${name}arg='${OPTARG}';;
		esac
	done
	
	if [ "$count" == "" ]
	then
		print_help
	fi
	
	if [ "$hflag" == "1" ]
	then
		print_help
	fi
	
	# If we're building the images target (and not cleaning),
	# we need to also build the kernel target.
	if [ "$iflag" == "1" ] &&
	   [ "${CLEAN}" == "0" ]
	then
		kflag=1
	fi
}

##
# shell
#
# Spawns a shell with the Android environment.
##
shell()
{
	export BOOTLOADER_PATH
	export KERNEL_PATH
	
	exec ${SHELL} --rcfile build/envsetup.sh
	exit 0
}

##
# kernel_config
#
# Runs "make menuconfig" in the kernel folder.
##
kernel_config()
{
	cd ${PATH_TO_KERNEL}
	make menuconfig
}

##
# run_options
#
# Runs all the options parsed out by choose_options.
##
run_options()
{
	for ((i=0;i<${#BUILD_OPTION[*]};++i))
	do
		OPT=`eval echo $"${BUILD_OPTION[i]}"`
		CMD=`eval echo $"${BUILD_COMMAND[i]}"`
		FLAG=${OPT:0:1}
		FLAGVAL=`eval echo \\$"${FLAG}flag"`
		FLAGARG=`eval echo \\$"${FLAG}arg"`

		if [ "${FLAGVAL}" == "1" ]
		then
			${CMD} ${FLAGARG}
		fi
	done

	return
}

##
# build_add_default
#
# Adds default build options.
##
build_add_default()
{
	build_add K  "kernel_config"		'Run "make menuconfig" inside the kernel folder.'
	build_add x  "build xloader" 		"Build X-Loader"
	build_add u  "build uboot_no_env"
	build_add u  "build uboot" 		"Build U-Boot"
	build_add k  "build kernel" 		"Build Kernel"
	build_add a  "build android" 		"Build Android"
	build_add k  "build sgx_modules"
	build_add k  "build wl12xx_modules"
	build_add i  "build images" 		"Build (system/userdata/boot).img, and (root/system/userdata).tar.bz2"
	build_add f: "build_fastboot" 		"Fastboot partition image(s) (system, userdata, boot, or all)"
	build_add F  "format_device" 		"Format SD card"
	build_add B  "deploy build_out" 	"Deploy to build-out folder"
	build_add S  "deploy sd" 		"Deploy to SD card (copies to FAT and EXT2 partitions, and filters init.rc for mtd mounts)"
	build_add N  "deploy nand" 		'Deploy to SD card (copies over scripts for reflashing nand and appropriate images)"'
	build_add U  "deploy update_zip" 	'Deploy to update.zip (compatible with "fastboot update update.zip")'
	build_add Z  "deploy newer" 		'Deploy files that are newer than system.img and userdata.img by using "adb push"'
	build_add T  "deploy fastboot" 		'Build, and deploy kernel image on-demand over fastboot'
	build_add s  "shell"			'Spawn a shell'
}

build_add_default
setup_default_environment

# Source the build_local.sh here so it has access to all environment stuff
source build-tools/build_local.sh

if [ -e "${HOME}/.logicpd/android_build" ]
then
	source ${HOME}/.logicpd/android_build
fi

# Amend paths to have uboot tools in them.
BOOTLOADER_PATH=${PATH_TO_UBOOT}/tools:${BOOTLOADER_PATH}
KERNEL_PATH=${PATH_TO_UBOOT}/tools:${KERNEL_PATH}
ORIG_PATH=${PATH_TO_UBOOT}/tools:${ORIG_PATH}
PATH=${PATH_TO_UBOOT}/tools:${PATH}

setup_android_env
check_environment
choose_options "${@}"

trap generic_error ERR
set -E

run_options
