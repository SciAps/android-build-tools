#!/bin/sh

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
	   [ "${ROOT}/.cached_android_env" -nt "${HOME}/.logicpd/android_build" ] ||
	   [ ! -e "${ROOT}/build/envsetup.sh" ]
	then
		source ${ROOT}/.cached_android_env
		export PATH=${PATH}${ANDROID_BUILD_PATHS}
		return
	fi

	echo "Updating Android build environment cache"
	(
		mktemp_env TMP
		mktemp_env UPT
		REGEX_CLEAN_ROOT=`echo -en "${ROOT}" | sed -re 's/(]|[[\\\/.+*?{\(\)\|\^])/\\\\\1/g'`

		export > ${TMP}
		. build/envsetup.sh
		echo lunch ${TARGET_ANDROID}
		lunch ${TARGET_ANDROID}
		export `cat ${ROOT}/build/core/version_defaults.mk | grep PLATFORM_VERSION[^_].*= | tr -d ': '`
		declare -x | sed -re 's|"('${REGEX_CLEAN_ROOT}')|"${ROOT}|g' > ${UPT}

		diff  --left-column ${TMP} ${UPT} |
			grep '^> ' |
			sed 's/^> //' |
			grep -v '^declare -x PATH=' |
			sed 's/^declare -x /export /' |
			sed -re 's|:('${REGEX_CLEAN_ROOT}')|:${ROOT}|g' > .cached_android_env
		rm -f ${UPT} ${TMP}
	) > /dev/null

	source ${ROOT}/.cached_android_env
	export PATH=${PATH}${ANDROID_BUILD_PATHS}
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
	cp ${LINK} ${PATH_TO_UBOOT}/u-boot.bin.ift                              $1/
	cp ${LINK} ${ANDROID_PRODUCT_OUT}/boot.img                              $1/
	cp ${LINK} ${ANDROID_PRODUCT_OUT}/system.img                            $1/
	cp ${LINK} ${ANDROID_PRODUCT_OUT}/userdata.img                          $1/
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
	check_component ${PATH_TO_UBOOT}/u-boot.bin.ift
	check_component ${PATH_TO_UBOOT}/u-boot-no-environ_bin
	check_component ${ANDROID_PRODUCT_OUT}/boot.img
	check_component ${ANDROID_PRODUCT_OUT}/system.img
	check_component ${ANDROID_PRODUCT_OUT}/userdata.img
	check_component ${ROOT}/device/logicpd/${TARGET_PRODUCT}/android.bmp
	check_component ${ROOT}/device/logicpd/${TARGET_PRODUCT}/android2.bmp
	check_component ${ROOT}/device/logicpd/${TARGET_PRODUCT}/done.bmp
	check_component device/logicpd/${TARGET_PRODUCT}/reflash_nand.cmd
	finished_checking_components
	
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
	#LINK=-l copy_update_cache build-out/update_cache/
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
	check_component ${ROOT}/device/logicpd/${TARGET_PRODUCT}/boot_sd.cmd
	finished_checking_components

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
	finished_checking_components

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
	finished_checking_components

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
		make -j${JOBS} SYSCFG_NAND_ECC_IN_CHIP=1
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
	local MODINST

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

		# Install modules and firmware.
		mktemp_env MODINST -d

		mkdir -p ${ANDROID_PRODUCT_OUT}/system/lib/modules
		mkdir -p ${ANDROID_PRODUCT_OUT}/system/etc/firmware
		make modules_install INSTALL_MOD_PATH=${MODINST}
		find ${MODINST}/lib/modules -name '*.ko' -exec cp '{}' ${ANDROID_PRODUCT_OUT}/system/lib/modules ';'
		cp -a ${MODINST}/lib/firmware ${ANDROID_PRODUCT_OUT}/system/etc

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

	if [ "$SKIP_SGX" == "1" ]
	then
		build_info "SKIP_SGX is set - skipping SGX build"
		return 0
	fi

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
# build_tarball <out.tar.{gz,bz2}> <folders>
#
# Creates a tarball, based on mktarball.sh, and it is safe for creating
# a tarball for the root filesystem as well (it has some local
# modifications)
##
build_tarball()
{
	local success
	local fs_get_stats
	local start_dir
	local dir_to_tar
	local target_tar
	local target_tarball

	mktemp_env target_tar
	target_tarball=$1

	echo "Creating tarball `basename ${target_tarball}`"

	rm ${target_tar} > /dev/null 2>&1
	pushd ${ANDROID_PRODUCT_OUT} >/dev/null 2>&1

	# Process all the partitions we're to integrate into the tarball
	for I in ${*:2}
	do
		dir_to_tar=$I
		fs_get_stats=${ROOT}/out/host/linux-x86/bin/fs_get_stats

		cd ${ANDROID_PRODUCT_OUT}
		
		echo "--> Adding partition ${dir_to_tar}"

		# do dirs first
		if [ "${dir_to_tar}" == "root" ]
		then
			subdirs=`find ${dir_to_tar} -type d -printf '%P\n'`
			files=`find ${dir_to_tar} \! -type d -printf '%P\n'`

			cd ${dir_to_tar}
		else
			subdirs=`find ${dir_to_tar} -type d -print`
			files=`find ${dir_to_tar} \! -type d -print`
		fi

		for f in ${subdirs} ${files} ; do
		    curr_perms=`stat -c 0%a $f`
		    [ -d "$f" ] && is_dir=1 || is_dir=0
		    new_info=`${fs_get_stats} ${curr_perms} ${is_dir} ${f}`
		    new_uid=`echo ${new_info} | awk '{print $1;}'`
		    new_gid=`echo ${new_info} | awk '{print $2;}'`
		    new_perms=`echo ${new_info} | awk '{print $3;}'`

		    tar --no-recursion --numeric-owner --owner $new_uid \
			--group $new_gid --mode $new_perms -p -rf ${target_tar} ${f}
		done
	done

	if [ $? -eq 0 ] ; then
	    case "${target_tarball}" in
	    *.bz2 )
		bzip2 -c ${target_tar} > ${target_tarball}
		;;
	    *.gz )
		gzip -c ${target_tar} > ${target_tarball}
		;;
	    esac
	    success=$?
	    [ $success -eq 0 ] || rm -f ${target_tarball}
	    rm -f ${target_tar}
	    popd >/dev/null 2>&1
	    return $success
	fi

	rm -f ${target_tar}
	popd >/dev/null 2>&1
	return 1
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
		build_tarball ${ANDROID_PRODUCT_OUT}/root.tar.bz2 root

		# Create fs.tar.bz2 (root + data + system)
		build_tarball ${ANDROID_PRODUCT_OUT}/fs.tar.bz2 root system data

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
	# Cause the device to reboot into the bootloader
	adb reboot bootloader || echo Not instructing device to reboot
	
	# Upload the appropriate images
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

	finished_checking_components

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
# build_omap3usbload
#
# Builds the tool required for booting over USB.  Useful for release
# folders.
##
build_omap3usbload()
{
	if [ ! -f "x-loader/scripts/omap3_usbload" ]
	then
		gcc -o x-loader/scripts/omap3_usbload x-loader/scripts/omap3_usbload.c -lusb
	fi
}

##
# deploy_usb
#
# Pushes all pertinent files over USB for running out of NAND
##
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

	echo "Turn off devkit; ensure USB OTG cable is plugged in"
	echo "Turn on the devkit to start the update process."

	echo Waiting for devkit turn-on
	x-loader/scripts/omap3_usbload -f x-loader/x-load_usb.bin \
		-a 0x80400000 -f u-boot/u-boot-fastboot-only      \
		-j 0x80400000 > /dev/null

	# Flash everything, then finish by "continuing"
	echo -n Flashing...
	
	echo -n x-loader...
	fastboot flash x-loader x-loader/x-load.bin.ift > /dev/null 2>&1

	echo -n u-boot...
	(fastboot flash u-boot u-boot/u-boot.bin.ift
	fastboot erase u-boot-env) > /dev/null 2>&1

	echo -n kernel...
	fastboot flash boot > /dev/null 2>&1

	echo -n system...
	fastboot flash system > /dev/null 2>&1

	echo -n userdata...
	(fastboot flash userdata
	fastboot erase cache) > /dev/null 2>&1
	
	echo -en "\nSetting up environment to boot from NAND\n"
	(fastboot oem env default -f
	fastboot oem setenv kernel_location nand
	fastboot oem setenv preboot
	fastboot oem setenv bootdelay 1
	fastboot oem saveenv) > /dev/null 2>&1
	
	echo -en "Rebooting"
	fastboot reboot > /dev/null 2>&1
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
# setup_default_environment
#
# Sets up default environmental settings for script in general,
# including paths, etc.  Can be overridden on a per-project basis
# later.
##
setup_default_environment()
{
	PATH_TO_KERNEL=${ROOT}/kernel
	PATH_TO_UBOOT=${ROOT}/u-boot
	PATH_TO_XLOADER=${ROOT}/x-loader

	export ARCH=arm
	export CROSS_COMPILE=arm-none-linux-gnueabi-

	ORIG_PATH=${PATH}

	KERNEL_PATH=${PATH}:${ROOT}/codesourcery/arm-2009q1-203/bin
	BOOTLOADER_PATH=${KERNEL_PATH}

	export PATH=${BOOTLOADER_PATH}
	
	if [ -f /etc/gentoo-release ]
	then
		# If we're on Gentoo, we can easily specify what java toolset we want to use
		export GENTOO_VM=sun-jdk-1.6
		export PATH=$(java-config -O)/bin:${PATH}
	fi
}

##
# Checks to see if mkimage is installed
#
##
check_mkimage()
{
	local pkg
	if ! which mkimage &>/dev/null
	then
		echo "Missing tool mkimage!"
		case ${DISTRIB_ID} in
			Ubuntu)
				case ${DISTRIB_RELEASE} in
					10.*) pkg=uboot-mkimage;;
					11.*) pkg=u-boot-tools;;
					12.*) pkg=u-boot-tools;;
					*) pkg=uboot-mkimage/u-boot-tools;;
				esac
				echo "Please install package ${pkg} for mkimage"
				echo "    sudo apt-get install ${pkg}"
				;;
			Gentoo)
				echo "Please install package u-boot-tools for mkimage"
				echo "    sudo emerge -av u-boot-tools"
				;;
			*)
				echo "Please install whatever package your distribution has"
				echo "for the utility make image.  It may be called u-boot-tools."
				;;
		esac
		exit 1
	fi
}

##
# Check to see what build options should be dynamically removed.
##
check_remove_build_options()
{
	if [ ! -e "${ROOT}/build/envsetup.sh" ]
	then
		local opts
		local I
		opts=`find_build_options | sort -rn`
		for I in `echo $opts`
		do
			array_delete_index BUILD_OPTION ${I}
			array_delete_index BUILD_COMMAND ${I}
			array_delete_index BUILD_HELP ${I}
		done
	fi
}

# General configuration
TARGET_UBOOT=omap3logic
TARGET_XLOADER=dm3730logic
TARGET_ANDROID=dm3730logic-eng
TARGET_KERNEL=omap3logic_android_defconfig

# The following come from u-boot/include/config.mk
UBOOT_BOARD=logic
UBOOT_VENDOR=ti
UBOOT_SOC=omap3

# Add all of our build targets.
build_add K  "kernel_config"		'Run "make menuconfig" inside the kernel folder.'
build_add x  "build xloader" 		"Build X-Loader"
build_add u  "build uboot_no_env"
build_add u  "build uboot_fastboot"
build_add u  "build uboot" 		"Build U-Boot"
build_add k  "build kernel" 		"Build Kernel"
build_add a  "build android" 		"Build Android"
build_add k  "build sgx_modules"
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
build_add R  "create_release"		"Create a release binary blob"
build_add X  "build_omap3usbload"
build_add X  "deploy usb"		"Deploy over USB"

# Amend paths to have uboot tools in them.
BOOTLOADER_PATH=${PATH_TO_UBOOT}/tools:${BOOTLOADER_PATH}
KERNEL_PATH=${PATH_TO_UBOOT}/tools:${KERNEL_PATH}
ORIG_PATH=${PATH_TO_UBOOT}/tools:${ORIG_PATH}
PATH=${PATH_TO_UBOOT}/tools:${PATH}

# Override default build scripting to use code sourcery toolchain.

if [ -e "${HOME}/.logicpd/android_build" ]
then
	source ${HOME}/.logicpd/android_build
fi

# Update flagset parsed.
parse_options "${@}"

# If we're building the images target (and not cleaning),
# we need to also build the kernel target.
if [ "$iflag" == "1" ] &&
   [ "${CLEAN}" == "0" ]
then
        kflag=1
fi

setup_default_environment

# If we're showing the help, don't run the android environment setup.
if [ "$hflag" != "1" ]
then
        setup_android_env
fi

check_remove_build_options
