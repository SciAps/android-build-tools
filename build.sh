#!/bin/sh

# General configuration
TARGET_UBOOT=dm3730logic
TARGET_XLOADER=${TARGET_UBOOT}
TARGET_ANDROID=dm3730logic-eng
TARGET_KERNEL=omap3logic_android_defconfig

# The following come from u-boot/include/config.mk
UBOOT_BOARD=logic
UBOOT_VENDOR=ti
UBOOT_SOC=omap3

#######################################################
#    The rest of this file should remain untouched    #
#######################################################

# Normalize the path to the folder build.sh is located in.
cd `dirname \`which $0\``

setup_environment()
{
	# Setup some environment variables.
	TIMEFORMAT='%R seconds'
	ROOT=${PWD}
	JOBS=8
	CLEAN=0
	VERBOSE=0
	DEV=

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

setup_android_env()
{
	if [ "${TARGET_PRODUCT}" == "" ]
	then
		source build/envsetup.sh >/dev/null
		lunch ${TARGET_ANDROID} > /dev/null
	fi
}

find_removable_devices()
{
	list1=`grep -x 1 /sys/class/block/*/removable | sed s/.*block\\\\/// | sed s/\\\\/removable.*//`
	for i in ${list1}
	do
		if [ "`cat /sys/class/block/$i/size`" != "0" ]
		then
			list2+="${i} "
		fi
	done
	echo ${list2}
}

choose_removable_device()
{
	DEV_LIST=`find_removable_devices`

	# The following hack for TAB completion is from
	# http://www.linuxquestions.org/questions/linux-general-1/commandline-autocompletion-for-my-shell-script-668388/
	set -o emacs
	bind 'set show-all-if-ambiguous on'
	bind 'set completion-ignore-case on'
	COMP_WORDBREAKS=${COMP_WORDBREAKS//:}
	bind 'TAB:dynamic-complete-history'
	for i in ${DEV_LIST} ; do
		history -s $i
	done

	grep -qx 1 /sys/class/block/${DEV}/removable 2>/dev/null && return

	while true
	do
		for i in ${DEV_LIST}
		do
			echo "${i} is $((`cat /sys/class/block/${i}/size`*512)) bytes - `cat /sys/class/block/${i}/device/model`"
		done

		read -ep "Enter device: " DEV
		if grep -qx 1 /sys/class/block/${DEV}/removable 2>/dev/null
		then
			sudo -v
			sleep 1
			return 0
		fi
		echo "Enter a valid device."
		echo "You can choose one of ${DEV_LIST}"
	done
}

unmount_device()
{
	choose_removable_device

	MNT_POINTS=`cat /proc/mounts | grep $DEV | awk '{print $2}'`
	for I in ${MNT_POINTS}
	do
		echo "Unmounting ${I}"
		sudo umount ${I} || return 1
	done
}

format_device()
{
	choose_removable_device

	# Unmount the device
	unmount_device || return 1

	# Run FDISK

	echo "Setting up $DEV"
	echo
	echo -n "Do you wish to continue? (y/N) "
	read answer
	if [ "${answer^*}" == "Y" ]
	then
		sudo -v
		echo "Partitioning $DEV."
	FATEND=7
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

$FATEND
t
c
a
1
n
p
2


w
EOF
		sleep 2

		echo "[Making filesystems...]"

		sudo mkfs.vfat -F 32 -n boot /dev/${DEV}1 > /dev/null 2>&1
                sudo mkfs.ext3 -L rootfs /dev/${DEV}2 > /dev/null
	else
		exit 1
	fi
}

mount_bootloader()
{
	if [ "${MNT_BOOTLOADER}" == "" ]
	then
		choose_removable_device
		MNT_BOOTLOADER=`mktemp -d`
		echo "Mounting bootloader partition"
		sudo mount /dev/${DEV}1 ${MNT_BOOTLOADER} -o uid=`id -u`
	fi
}

mount_root()
{
	if [ "${MNT_ROOT}" == "" ]
	then
		choose_removable_device
		MNT_ROOT=`mktemp -d`
		echo "Mounting root partition"
		sudo mount /dev/${DEV}2 ${MNT_ROOT}
	fi
}

umount_all()
{
	if [ ! "${MNT_BOOTLOADER}" == "" ]
	then
		echo "Unmounting bootloader partition"
		sudo umount ${MNT_BOOTLOADER}
		rmdir ${MNT_BOOTLOADER}
	fi

	if [ ! "${MNT_ROOT}" == "" ]
	then
		echo "Unmounting root partition"
		sudo umount ${MNT_ROOT}
		rmdir ${MNT_ROOT}
	fi
}

check_component()
{
	if [ ! -e ${1} ]
	then
		echo "Missing \"${1}\"! Cannot continue."
		exit 1
	fi
}

copy_reflash_nand_sd()
{
	setup_android_env
	cd ${ROOT}
	mkdir -p $1/update

	# Update x-loader in place if possible.
	cat x-loader/x-load.bin.ift                                           > $1/MLO
	cp ${LINK} u-boot/u-boot-no-environ_bin                                 $1/u-boot.bin
	cp ${LINK} x-loader/x-load.bin.ift                                      $1/update/MLO
	cp ${LINK} u-boot/u-boot.bin.ift                                        $1/update
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

copy_update_cache()
{
	setup_android_env
	cd ${ROOT}

	mkdir -p $1

	cp ${LINK} u-boot/u-boot.bin.ift                                        $1
	cp ${LINK} x-loader/x-load.bin.ift                                      $1/MLO
	cp ${LINK} ${ANDROID_PRODUCT_OUT}/boot.img                              $1/uMulti-Image
	cp ${LINK} ${ANDROID_PRODUCT_OUT}/system.img                            $1
	cp ${LINK} ${ANDROID_PRODUCT_OUT}/userdata.img                          $1
	mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Update Script" \
		-d build-tools/remote_update_info/updatescr.txt \
		$1/updatescr.upt > /dev/null 2>&1
}

deploy_build_out()
{
	setup_android_env
	cd ${ROOT}

	# Check necessary files.
	check_component x-loader/x-load.bin.ift
	check_component u-boot/u-boot.bin
	check_component u-boot/u-boot-no-environ_bin
	check_component ${ANDROID_PRODUCT_OUT}/boot.img
	check_component ${ANDROID_PRODUCT_OUT}/system.img
	check_component ${ANDROID_PRODUCT_OUT}/userdata.img
	
	mkdir -p build-out/reflash_nand_sd/update
	mkdir -p build-out/update_cache

	rm -Rf build-out
	mkdir -p build-out
	
	# Copy over x-loader binaries
	cp -l x-loader/x-load.bin.ift build-out/MLO

	# Copy over u-boot binaries
	cp -l u-boot/u-boot.bin     build-out/
	cp -l u-boot/u-boot.bin.ift build-out/

	# Copy over to reflash_nand_sd
	LINK=-l copy_reflash_nand_sd build-out/reflash_nand_sd/

	# Copy over to update_cache
	LINK=-l copy_update_cache build-out/update_cache/
}

deploy_sd()
{
	setup_android_env
	cd ${ROOT}

	# Check necessary files.
	check_component x-loader/x-load.bin.ift
	check_component u-boot/u-boot.bin
	check_component kernel/arch/arm/boot/uImage
	check_component ${ANDROID_PRODUCT_OUT}/root.tar.bz2
	check_component ${ANDROID_PRODUCT_OUT}/system.tar.bz2
	check_component ${ANDROID_PRODUCT_OUT}/userdata.tar.bz2

	mount_bootloader
	mount_root

	# Using CAT to update the MLO file inplace;
	# this way it doesn't break the ability to boot.
	cat x-loader/x-load.bin.ift > ${MNT_BOOTLOADER}/MLO
	cp u-boot/u-boot.bin ${MNT_BOOTLOADER}
	cp kernel/arch/arm/boot/uImage ${MNT_BOOTLOADER}
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
	TMP_INIT=`mktemp`
	sudo cat init.rc | grep -v mtd > ${TMP_INIT}
	sudo cp ${TMP_INIT} init.rc
	rm ${TMP_INIT}

	cd ${ROOT}
	umount_all
}

deploy_nand()
{
	setup_android_env
	cd ${ROOT}

	# Check necessary files.
	check_component x-loader/x-load.bin.ift
	check_component u-boot/u-boot.bin
	check_component u-boot/u-boot-no-environ_bin
	check_component ${ANDROID_PRODUCT_OUT}/boot.img
	check_component ${ANDROID_PRODUCT_OUT}/system.img
	check_component ${ANDROID_PRODUCT_OUT}/userdata.img

	mount_bootloader

	# Install root files from the various tarballs
	rm -Rf ${MNT_BOOTLOADER}/update
	mkdir -p ${MNT_BOOTLOADER}/update
	copy_reflash_nand_sd ${MNT_BOOTLOADER}/
	umount_all
}

deploy_update_zip()
{
	setup_android_env
	cd ${ROOT}

	check_component ${ANDROID_PRODUCT_OUT}/boot.img
	check_component ${ANDROID_PRODUCT_OUT}/system.img
	check_component ${ANDROID_PRODUCT_OUT}/userdata.img

	cd ${ANDROID_PRODUCT_OUT}
	zip ${ROOT}/update.zip boot.img system.img userdata.img android-info.txt

	cd ${ROOT}
}

deploy_newer()
{
	setup_android_env
	cd ${ANDROID_PRODUCT_OUT}
	find system -type f -newer system.img   -print -exec adb push '{}' /'{}' ';'
	find data   -type f -newer userdata.img -print -exec adb push '{}' /'{}' ';'
}

build_android()
{
	setup_android_env
	if [ "$CLEAN" == "0" ]
	then
		make -j${JOBS}
		ERR=$?

		if [ -e "kernel/arch/arm/boot/zImage" ]
		then
			# Create boot.img
			mkimage -A arm -O linux -T multi -C none -a 0x82000000 -e 0x82000000 -n 'Logic PD' \
				-d kernel/arch/arm/boot/zImage:${ANDROID_PRODUCT_OUT}/ramdisk.img \
				${ANDROID_PRODUCT_OUT}/boot.img
		fi
	else
		make -j${JOBS} clean
		ERR=$?
	fi
	return ${ERR}
}

build_uboot()
{
	cd ${ROOT}/u-boot

	PATH=${BOOTLOADER_PATH}	

	BOARD=`cat include/config.mk 2>/dev/null | awk '/BOARD/ {print $3}'`
	VENDOR=`cat include/config.mk 2>/dev/null | awk '/VENDOR/ {print $3}'`
	SOC=`cat include/config.mk 2>/dev/null | awk '/SOC/ {print $3}'`

	if [ "$CLEAN" == "0" ]
	then
		# If the configuration isn't set, set it.
		if [ ! "$UBOOT_BOARD" == "$BOARD" ] ||
		   [ ! "$UBOOT_VENDOR" == "$VENDOR" ] ||
		   [ ! "$UBOOT_SOC" == "$SOC" ]
		then
			make ${TARGET_UBOOT}_config
		fi

		make -j${JOBS}
		ERR=$?
	else
		make -j${JOBS} distclean
		ERR=$?
		rm -f include/config.mk
	fi

	cd ${ROOT}
	return ${ERR}
}

build_uboot_no_env()
{
	if [ "${CLEAN}" == "1" ]
	then
		rm build-out/u-boot-no-environ_bin
	else
		if [ ! -e u-boot/u-boot-no-environ_bin ]
		then
			CLEAN=1 build_uboot
			CLEAN=0 CMDLINE_FLAGS=-DFORCED_ENVIRONMENT build_uboot
			cp u-boot/u-boot.bin u-boot/u-boot-no-environ_bin
			CLEAN=1 build_uboot
		fi
	fi
}

build_xloader()
{
	cd ${ROOT}/x-loader
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
		ERR=$?
	else
		make -j${JOBS} distclean
		ERR=$?
		rm -f include/config.mk
	fi

	cd ${ROOT}
	return ${ERR}
}

build_kernel()
{
	setup_android_env

	cd ${ROOT}/kernel
	PATH=${KERNEL_PATH}

	if [ "$CLEAN" == "0" ]
	then
		if [ ! -e ".config" ] 
		then
			echo "Using defualt kernel configuration."
			make ${TARGET_KERNEL} -j${JOBS}
		else
			echo "Using existing kernel configuration."
			echo "To reset to default configuration, do:"
			echo "  cd kernel"
			echo "  ARCH=arm make ${TARGET_KERNEL}"
			echo ""
		fi
		ERR=$?
		[ "$ERR" == "0" ] && make uImage -j${JOBS}
		ERR=$?

		if [ -e "${ANDROID_PRODUCT_OUT}/ramdisk.img" ]
		then
			cd ${ROOT}
			# Create boot.img
			mkimage -A arm -O linux -T multi -C none -a 0x82000000 -e 0x82000000 -n 'Logic PD' \
				-d kernel/arch/arm/boot/zImage:${ANDROID_PRODUCT_OUT}/ramdisk.img \
				${ANDROID_PRODUCT_OUT}/boot.img
		fi
	else
		make clean -j${JOBS}
		ERR=$?
	fi
	return ${ERR}
}

build_sub_module()
{
	cd ${ROOT}
	setup_android_env
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

build_sub_module_WiFi()
{
	cd ${ROOT}
	setup_android_env
	CMD="make -C $* ANDROID_ROOT_DIR=${ROOT} TOOLS_PREFIX=prebuilt/linux-x86/toolchain/arm-eabi-4.4.0/bin/arm-eabi- -j${JOBS}"
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

build_sgx_modules()
{
	# The make files for sgx are looking for the variable TARGET_ROOT
	# to help determine the version of android we're running.
	TARGET_ROOT=${ROOT}
	setup_android_env
	build_sub_module hardware/ti/sgx OMAPES=5.x
}

build_wl12xx_modules()
{
	build_sub_module_WiFi hardware/ti/wlan/WL1271_compat/drivers
}

build_kernel_modules()
{
	BOARD_OMAPES=5.x

	setup_android_env

	if [ "$CLEAN" == "0" ]
	then
		cd ${ROOT}/kernel
		PATH=${KERNEL_PATH}
		make modules -j${JOBS}
	fi
}

build_images()
{
	setup_android_env

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
		mkimage -A arm -O linux -T multi -C none -a 0x82000000 -e 0x82000000 -n 'Logic PD' \
			-d kernel/arch/arm/boot/zImage:${OUT}/ramdisk.img \
			${ANDROID_PRODUCT_OUT}/boot.img
	fi
}

build_fastboot()
{
	setup_android_env

	if [ "${FASTBOOT_PARAM}" == "all" ]
	then
		setup_android_env

		fastboot flash boot
		fastboot flash system
		fastboot flash userdata
		fastboot reboot
	else
		fastboot flash ${FASTBOOT_PARAM}
	fi
}

build()
{
	ERR=0
	TMP=`mktemp`
	TIME=`mktemp`

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
		time ( build_$1 2>&1 | tee ${TMP} ; [ "${PIPESTATUS[0]}" == "0" ] || false; ) 2> ${TIME}
		ERR=$?
		echo -en "Finished ${VERB_ACTIVE} ${NAME} - "
	else
		echo -en " - "
		time (build_$1 > $TMP 2>&1) 2> ${TIME}
		ERR=$?
	fi

	if [ "$ERR" != "0" ]
	then
		echo -en "failure ${VERB_ACTIVE}.\nSee ${ROOT}/error.log.\n"
		mv ${TMP} ${ROOT}/error.log
		rm ${TIME}
		exit 1
	else
		echo -en "took "
		echo -en `cat ${TIME}`
		echo -e " to ${VERB}."
		rm ${TMP}
	fi
	rm ${TIME}
}

deploy()
{
	echo "Deploying to $1"
	deploy_$1
}

print_help()
{
	cat <<EOF
Usage: $0:
 Targets:
  -A       Build all, and deploy to build-out
  -a       Build Android
  -u       Build U-Boot
  -x       Build X-Loader
  -k       Build Kernel
  -i       Build system.img, userdata.img, ramdisk.img, and boot.img

 Deployment options:
  -f [img] Fastboot partition image(s) (system, userdata, boot, or all)
  -F       Format SD card
  -B       Deploy to build-out folder
  -S       Deploy to SD card (copies to FAT and EXT2 partitions, and filters init.rc for mtd mounts)
  -N       Deploy to SD card (copies over scripts for reflashing nand and appropriate images)
  -U       Deploy to update.zip (compatible with "fastboot update update.zip")

  -Z       Deploy files that are newer than system.img and userdata.img by using "adb push"

 Job options:
  -j [num] How many simultaneous compiles to run
  -c       Clean object files

 Misc options:
  -s       Spawn a shell
EOF
	exit 2
}

choose_options()
{
	count=

	while getopts AZf:asuxkvij:c?bFSBNhU name
	do
		eval count=$((count+1))
		case $name in
			A) aflag=1;uflag=1;xflag=1;kflag=1;iflag=1;Bflag=1;;
			j) JOBS="$OPTARG";;
			c) CLEAN=1;;
			v) VERBOSE=1;;
			b) uflag=1;xflag=1;kflag=1;;
			f) fflag=1;FASTBOOT_PARAM="${OPTARG}";;
			\?) hflag=1;;
			*) eval ${name}flag=1;;
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

run_options()
{
	if [ "$sflag" == "1" ]
	then
		export BOOTLOADER_PATH
		export KERNEL_PATH
		setup_android_env
	
		${SHELL}
		exit 0
	fi

	if [ "$xflag" == "1" ]
	then
		build xloader
	fi
	
	if [ "$uflag" == "1" ]
	then
		build uboot_no_env
		build uboot
	fi
	
	if [ "$kflag" == "1" ]
	then
		build kernel
		build kernel_modules
	fi
	
	if [ "$aflag" == "1" ]
	then
		build android
	fi

	if [ "$kflag" == "1" ]
	then
		build sgx_modules
		build wl12xx_modules
	fi
	
	if [ "$iflag" == "1" ]
	then
		build images
	fi
	
	if [ "$fflag" == "1" ]
	then
		build fastboot
	fi
	
	if [ "$Fflag" == "1" ]
	then
		format_device		
	fi

	if [ "$Sflag" == "1" ]
	then
		deploy sd
	fi

	if [ "$Bflag" == "1" ]
	then
		deploy build_out
	fi

	if [ "$Nflag" == "1" ]
	then
		deploy nand
	fi

	if [ "$Uflag" == "1" ]
	then
		deploy update_zip
	fi

	if [ "$Zflag" == "1" ]
	then
		deploy newer
	fi
}

setup_environment
choose_options $*
run_options

