#!/bin/sh

# Uncomment to enable debugging
# set -x

### DO NOT MODIFY! ###
OUT="/dev/null"
VERBOSE=0
JNUM=4
TOPDIR=${PWD}
BUILD="NONE"
DEPLOY="NONE"
FORMAT="NONE"
CLEANTARGET="NONE"
FAT32="W95"
EXT3="Linux"
UBOOT_DIR=$TOPDIR/u-boot
XLOADER_DIR=$TOPDIR/x-loader
BUILDOUTPUT=$TOPDIR/build-out
### DO NOT MODIFY! ###

# Devices to avoid to use for deployment
FORBIDDEN_DEVICES=(sda)

# Set the configs for X-Loader, U-Boot, Kernel and Android Target using
# the guide below.
#
# OMAP3530 SOM-LV/Torpedo
# -----------------------
# XLOADER_CONFIG="omap3530lv_som_config"
# UBOOT_CONFIG="omap3_logic_config"
# KERNEL_CONFIG="omap3_logic_android_defconfig"
# ANDROID_TARGET="omap3logic"
#
# DM3730 SOM-LV/Torpedo
# -----------------------
# XLOADER_CONFIG="dm3730logic_config"
# UBOOT_CONFIG="dm3730logic_config"
# KERNEL_CONFIG="dm3730_logic_android_defconfig"
# ANDROID_TARGET="dm3730logic"

XLOADER_CONFIG="INVALID"
UBOOT_CONFIG="INVALID"
KERNEL_CONFIG="INVALID"
ANDROID_TARGET="INVAILD"

# Is the script configured?
# Set the value to "YES" once the values above are properly
# set up.
CONFIGURED="NO"

############################
#
#
#
############################
function showHelp
{
    echo "Build Script"
    echo "---------------"
    echo -e "Usage: $0 [-b (x-load | u-boot | kernel | wifi | android | android-sdk | android-sdk-addon | all)]\n\t\t  [-c] [-C (x-load | u-boot | kernel | android | all)]\n\t\t  [-v] [-h] [-t X]\n\t\t  [-d (x-load | u-boot | kernel | android)]\n\t\t  [-F] [-D /dev/xxx]"
    echo
    echo -e "\t-b\t\tBuild specific target"
    echo -e "\t-c\t\tClean output directory"
    echo -e "\t-p\t\tPackage specific target"
    echo -e "\t-C\t\tClean specific target"
    echo -e "\t-v\t\tVerbose build output"
    echo -e "\t-h\t\tShow this help"
    echo -e "\t-t\t\tNumber of threads for Make (Default 4)"
    echo -e "\t-d\t\tDeploy specific target [Requires -D]"
    echo -e "\t-D\t\tDevice to use"
    echo -e "\t-F\t\tFormat the SD card  [Requires -D]"
    exit 0
}

############################
#
#
#
############################
function cleanBuild
{
    for i in MLO u-boot.bin uImage rootfs.tar.bz2
    do
	rm -rf $BUILDOUTPUT/$i
    done
    exit 0
}

############################
#
#
#
############################
function cleanTarget
{
    echo "=== Cleaning $CLEANTARGET ==="

    if [ "$CLEANTARGET" == "ALL" ] || [ "$CLEANTARGET" == "X_LOAD" ]; then
	pushd $TOPDIR/x-loader > /dev/null 2>&1
	make CROSS_COMPILE=arm-eabi- clean > /dev/null 2>&1 
	make CROSS_COMPILE=arm-eabi- mrproper > /dev/null 2>&1
	make CROSS_COMPILE=arm-eabi- distclean > /dev/null 2>&1
	popd > /dev/null 2>&1

	echo "X-Load cleaned"
    fi
    
    if [ "$CLEANTARGET" == "ALL" ] || [ "$CLEANTARGET" == "U_BOOT" ]; then
	pushd $TOPDIR/u-boot > /dev/null 2>&1
	make CROSS_COMPILE=arm-eabi- clean > /dev/null 2>&1
	make CROSS_COMPILE=arm-eabi- mrproper > /dev/null 2>&1
	make CROSS_COMPILE=arm-eabi- distclean > /dev/null 2>&1
	popd > /dev/null 2>&1

	echo "U-boot cleaned"
    fi
    
    if [ "$CLEANTARGET" == "ALL" ] || [ "$CLEANTARGET" == "KERNEL" ]; then
	pushd $TOPDIR/kernel > /dev/null 2>&1
	make ARCH=arm CROSS_COMPILE=arm-eabi- clean > /dev/null 2>&1
	make ARCH=arm CROSS_COMPILE=arm-eabi- mrproper > /dev/null 2>&1
	make ARCH=arm CROSS_COMPILE=arm-eabi- distclean > /dev/null 2>&1
	popd > /dev/null 2>&1

	echo "Kernel cleaned"
    fi

    if [ "$CLEANTARGET" == "ALL" ] || [ "$CLEANTARGET" == "WIFI" ]; then
	pushd $TOPDIR/hardware/ti/wlan/wl1271/platforms/os/linux &> /dev/null

	export CROSS_COMPILE=arm-eabi-
	export ARCH=arm
	export HOST_PLATFORM=logicpd
	export KERNEL_DIR=$TOPDIR/kernel

	make clean &> /dev/null

	popd &> /dev/null
    fi

    if [ "$CLEANTARGET" == "ALL" ] || [ "$CLEANTARGET" == "ANDROID" ]; then
	pushd $TOPDIR > /dev/null 2>&1
	make clean > /dev/null 2>&1
	make mrproper > /dev/null 2>&1
	make distclean > /dev/null 2>&1

	rm -rf $BUILDOUTPUT

	popd > /dev/null 2>&1

	echo "Android cleaned"
    fi

    exit 0
}

############################
#
#
#
############################
function packageTarget
{
    echo -e "*****\nPackaging $PACKAGE\n*****"

    pushd $TOPDIR/$BUILDOUTPUT/target/product/dm3730logic &> /dev/null

    if [ -e android_rootfs ]; then
	rm -rf android_rootfs
    fi

    mkdir android_rootfs
    cp -r root/* android_rootfs
    cp -r system android_rootfs

    echo "Creating RFS tarball, might ask for SUDO password"

    sudo ../../../../build/tools/mktarball.sh ../../../host/linux-x86/bin/fs_get_stats android_rootfs . rootfs rootfs.tar.bz2
    cp rootfs.tar.bz2 $BUILDOUTPUT/rootfs.tar.bz2

    popd &> /dev/null
}


############################
#
#
#
############################
function buildXLoader
{
    # Build X-Loader
    echo -e "*****\nBuilding X-Loader\n*****"
    pushd $XLOADER_DIR > /dev/null 2>&1
    if [ ! -e include/config.mk ]; then
	make $XLOADER_CONFIG > ${OUT} 2>&1
    fi
    
    # Erase existing binary
    if [ -e x-load.bin ]; then
	rm -rf x-load.bin
    fi
    make CROSS_COMPILE=arm-eabi- all > ${OUT} 2>&1
    
    if [ $? -eq 0 ] && [ -e x-load.bin ]; then
	echo "X-Loader sucessfully built."
	scripts/signGP
	cp x-load.bin.ift $BUILDOUTPUT/MLO
    else
	echo "+++++++++"
	echo "ERROR: X-Loader build failed!"
	if [ $OUT != "" ]; then
	    echo "Enable '-v' option and re-run to see error."
	fi
	echo "+++++++++"
	exit 1
    fi
    
    popd > /dev/null 2>&1
}

############################
#
#
#
############################
function buildUBoot
{
    # Build U-Boot
    echo -e "*****\nBuilding U-Boot\n*****"
    pushd $UBOOT_DIR > /dev/null 2>&1
    # If U-boot has already been configured for build, skip else configure
    if [ ! -e include/config.mk ]; then
	make $UBOOT_CONFIG > ${OUT} 2>&1
    fi
    
    # Erase existing binary
    if [ -e u-boot.bin ]; then
	rm -rf u-boot.bin
    fi
    
    make CROSS_COMPILE=arm-eabi- all > ${OUT} 2>&1
    
    # Did U-Boot build?
    if [ $? -eq 0 ] && [ -e u-boot.bin ]; then
	echo "U-Boot sucessfully built."
	cp u-boot.bin $BUILDOUTPUT
    else
	echo "+++++++++"
	echo "ERROR: U-Boot build failed!"
	if [ $OUT != "" ]; then
	    echo "Enable '-v' option and re-run to see error."
	fi
	echo "+++++++++"
	exit 2
    fi
    popd > /dev/null 2>&1
}

############################
#
#
#
############################
function buildKernel
{
    KVERSION=`cat $TOPDIR/kernel/Makefile | grep "^VERSION" | awk '{print $3}'`
    KPATCHLEVEL=`cat $TOPDIR/kernel/Makefile | grep "^PATCHLEVEL" | awk '{print $3}'`
    KSUBLEVEL=`cat $TOPDIR/kernel/Makefile | grep "^SUBLEVEL" | awk '{print $3}'`
    KEXTRAVERSION=`cat $TOPDIR/kernel/Makefile | grep "^EXTRAVERSION" | awk '{print $3}'`

    echo -ne "*****\nBuilding Kernel $KVERSION.$KPATCHLEVEL.$KSUBLEVEL"
    if [ ! -e $KEXTRAVERSION ]; then
	echo -e "-$KEXTRAVERSION\n*****"
    else
	echo -e "\n*****"
    fi
    pushd $TOPDIR/kernel > /dev/null 2>&1

    # Has the Kernel been configured?
    if [ ! -e .config ]; then
	make ARCH=arm $KERNEL_CONFIG > ${OUT} 2>&1
    fi
    
    # Erase existing binary
    if [ -e arch/arm/boot/uImage ]; then
	rm arch/arm/boot/uImage
    fi
    
    # Perform Make
    make ARCH=arm CROSS_COMPILE=arm-eabi- uImage -j${JNUM} > ${OUT} 2>&1
    
    # Did the binary get created?
    if [ $? -eq 0 ] && [ -e arch/arm/boot/uImage ]; then
	echo "Kernel successfully built."
	cp arch/arm/boot/uImage $BUILDOUTPUT/uImage
    else
	echo "+++++++++"
	echo "ERROR: Kernel build failed!"
	if [ $OUT != "" ]; then
	    echo "Enable '-v' option and re-run to see error."
	fi
	echo "+++++++++"
	popd > /dev/null 2>&1
	exit 3
    fi
    popd > /dev/null 2>&1
}

############################
#
#
#
############################
function buildWifiDriver
{
    # Build TI WiFi Driver
    echo -e "*****\nBuilding TI WiFi Driver\n*****"

    WIFIPATH=$TOPDIR/hardware/ti/wlan/wl1271
    SDIOKOPATH=$WIFIPATH/external_drivers/logicpd/Linux/sdio 

    pushd $WIFIPATH/platforms/os/linux &> /dev/null

    if [ -e tiwlan_drv.ko ]; then
       rm tiwlan_drv.ko
    fi

    export CROSS_COMPILE=arm-eabi-
    export ARCH=arm
    export HOST_PLATFORM=logicpd
    export KERNEL_DIR=$TOPDIR/kernel

    make &> ${OUT}

    if [ $? -eq 0 ] && [ -e tiwlan_drv.ko ]; then
	mkdir $BUILDOUTPUT/wifi
	for file in firmware.bin sdio.ko tiwlan_drv.ko ../../../config/tiwlan.ini; do
	    cp $file $TOPDIR/$BUILDOUTPUT/target/product/dm3730logic/system/etc/wifi
	done
    else
       echo "+++++++++"
       echo "ERROR: TI WiFi driver build failed!"
       if [ $OUT != "" ]; then
           echo "Enable '-v' option and re-run to see error."
       fi
       echo "+++++++++"
       popd > /dev/null 2>&1
       exit 4
    fi

    popd &> /dev/null
}

############################
#
#
#
############################
function buildAndroid
{
    # Build Android FS
    echo -e "*****\nBuilding Android $ANDROID_KERNEL_VERSION\n*****"
    pushd $TOPDIR > /dev/null 2>&1
    if [ $VERBOSE -eq 2 ]; then
    	make TARGET_PRODUCT=dm3730logic showcommands -j${JNUM} OMAPES=5.x > ${OUT} 2>&1
    else
    	make TARGET_PRODUCT=dm3730logic -j${JNUM} OMAPES=5.x > ${OUT} 2>&1
    fi
    
    if [ $? -eq 0 ]; then
	cd out/target/product/dm3730logic
	
	if [ -e android_rootfs ]; then
	    rm -rf android_rootfs
	fi
	
	mkdir android_rootfs
	cp -r root/* android_rootfs
	cp -r system android_rootfs
	
	echo "Creating RFS tarball, might ask for SUDO password"
	
	sudo ../../../../build/tools/mktarball.sh ../../../host/linux-x86/bin/fs_get_stats android_rootfs . rootfs rootfs.tar.bz2
	cp rootfs.tar.bz2 $BUILDOUTPUT/rootfs.tar.bz2
    else
	echo "+++++++++"
	echo "ERROR: Android build failed!"
	if [ $OUT != "" ]; then
	    echo "Enable '-v' option and re-run to see error."
	fi
	echo "+++++++++"
	popd > /dev/null 2>&1
	exit 4
	
    fi
    popd > /dev/null 2>&1
}

############################
#
#
#
############################
function buildAndroidSdk
{
    # Build Android SDK
    echo -e "*****\nBuilding Android SDK\n*****"
    pushd $TOPDIR > /dev/null 2>&1
    make -j${NUM} sdk > ${OUT} 2>&1
    if [ -e out/host/linux-x86/sdk/android-sdk_eng.`whoami`_linux-x86.zip ];
    then
	cp out/host/linux-x86/sdk/android-sdk_eng.`whoami`_linux-x86.zip \
	    $BUILDOUTPUT/android-sdk_eng.`whoami`_linux-x86.zip
    else
	echo "+++++++++"
	echo "ERROR: Android SDK build failed!"
	if [ $OUT != "" ]; then
	    echo "Enable '-v' option and re-run to see error."
	fi
	echo "+++++++++"
	popd > /dev/null 2>&1
	exit 5
    fi
    popd > /dev/null 2>&1
}

############################
#
#
#
############################
function buildAndroidSdkAddon
{
    # Build Android SDK Add on
    echo -e "*****\nBuilding Android SDK Addon\n*****"
    pushd $TOPDIR > /dev/null 2>&1
    make -j${JNUM} PRODUCT-logicpd_addon-sdk_addon > ${OUT} 2>&1
    cd out/host/linux-x86/sdk_addon
    for file in `ls *.zip`; do
	cp $file $BUILDOUTPUT
    done
    popd > /dev/null 2>&1
}

############################
#
#
#
############################
function findPartition
{
    PART=`sudo fdisk -l $DEV | grep "^$DEV" | grep $1 | awk '{print $1}'`
    
    if [ -z $PART ]; then
	echo "***"
	echo "SD card doesn't contain a $1 partition."
	echo "***"
	exit 3
    else
	echo "Found and using $PART"
    fi
}

############################
#
#
#
############################
function mountPartition
{
    COUNT=0
    while [ 1 ]; do
	COUNT=$((COUNT+1))
	sudo mount $1 $2 > mount.log 2>&1
	RET=$?
	if [ $RET -eq 0 ]; then
	    rm -f mount.log
	    break
	elif [ $RET -eq 1 ] || [ $RET -eq 16 ] || [ $RET -eq 32 ]; then
		echo "***"
		echo "Can't mount parition '$1'"
		cat mount.log
		echo "***"
		rm -f mount.log
		exit 4
	else
	    if [ $COUNT -gt 10 ]; then
		echo "***"
		echo "Can't mount parition '$1'"
		echo "***"
		rm mount.log
		exit 5
	    fi
	fi
    done
}

############################
#
#
#
############################
function unmountSD
{
    MOUNTS=`mount | grep $DEV`
    if [ "$MOUNTS" != "" ]; then

	MNT=`mount | grep "$DEV"1 | awk '{print $3}'`
	if [ "$MNT" != "" ]; then
	    sudo umount $MNT
	fi
	
	MNT=`mount | grep "$DEV"2 | awk '{print $3}'`
	if [ "$MNT" != "" ]; then
	    sudo umount $MNT
	fi
    fi
}

##
# Main code starts here...
##

if [ "$CONFIGURED" != "YES" ]; then
    echo "****"
    echo "The script isn't configured! The default values must be properly"
    echo "configured. Please refer to the description in the file for"
    echo "guidance."
    echo "****"
    exit 0
fi

if [ $# -eq 0 ]; then
    showHelp
    exit 0
fi

# Setup the path to use prebuild Android toolchain
PATH=${TOPDIR}/prebuilt/linux-x86/toolchain/arm-eabi-4.4.0/bin:${TOPDIR}/Tools:${PATH}

while getopts "cfvhFt:b:d:D:C:V:p:" flag
do
    case "$flag" in
	b)
	    if [ "$OPTARG" == "x-load" ]; then
		BUILD="X_LOAD"
	    elif [ "$OPTARG" == "u-boot" ]; then
		BUILD="U_BOOT"
	    elif [ "$OPTARG" == "kernel" ]; then
		BUILD="KERNEL"
	    elif [ "$OPTARG" == "wifi" ]; then
		BUILD="WIFI"
	    elif [ "$OPTARG" == "android" ]; then
		BUILD="ANDROID"
	    elif [ "$OPTARG" == "android-sdk" ]; then
		BUILD="ANDROID-SDK"
	    elif [ "$OPTARG" == "android-sdk-addon" ]; then
		BUILD="ANDROID-SDK-ADDON"
	    elif [ "$OPTARG" == "all" ]; then
		BUILD="ALL"
	    else
		echo "Invalid build target. Use:"
		echo -e "\tx-load"
		echo -e "\tu-boot"
		echo -e "\tkernel"
		echo -e "\twifi"
		echo -e "\tandroid"
		echo -e "\tandroid-sdk"
		echo -e "\tandroid-sdk-addon"
		echo -e "\tall"
		exit 1
	    fi
	    ;;
	c)
	    cleanBuild
	    ;;
	p)
            if [ "$OPTARG" == "android" ]; then
		PACKAGE="ANDROID"
            else
		echo "Invalid package target. Use:"
		echo -e "\tandroid"
		exit 1
            fi
            packageTarget
            ;;
	C)
	    if [ "$OPTARG" == "x-load" ]; then
		CLEANTARGET="X_LOAD"
	    elif [ "$OPTARG" == "u-boot" ]; then
		CLEANTARGET="U_BOOT"
	    elif [ "$OPTARG" == "kernel" ]; then
		CLEANTARGET="KERNEL"
	    elif [ "$OPTARG" == "wifi" ]; then
		CLEANTARGET="WIFI"
	    elif [ "$OPTARG" == "android" ]; then
		CLEANTARGET="ANDROID"
	    elif [ "$OPTARG" == "all" ]; then
		CLEANTARGET="ALL"
	    else
		echo "Invalid clean target. Use:"
		echo -e "\tx-load"
		echo -e "\tu-boot"
		echo -e "\tkernel"
		echo -e "\twifi"
		echo -e "\tandroid"
		echo -e "\tall"
		exit 1
	    fi
	    cleanTarget
	    ;;
	v) 
	    VERBOSE=$(($VERBOSE + 1))    
	    OUT="/dev/stdout"
	    ;;
	h) 
	    showHelp
	    ;;
	t)
	    JNUM=$OPTARG
	    ;;
	d)
	    if [ "$OPTARG" == "x-load" ]; then
		DEPLOY="X_LOAD"
	    elif [ "$OPTARG" == "u-boot" ]; then
		DEPLOY="U_BOOT"
	    elif [ "$OPTARG" == "kernel" ]; then
		DEPLOY="KERNEL"
	    elif [ "$OPTARG" == "android" ]; then
		DEPLOY="ANDROID"
	    else
		echo "Invalid deploy target. Use:"
		echo -e "\tx-load"
		echo -e "\tu-boot"
		echo -e "\tkernel"
		echo -e "\tandroid"
		exit 1
	    fi
	    ;;
	D)
	    for device in ${FORBIDDEN_DEVICES[*]}; do
		if [[ $OPTARG =~ $device ]]; then
		    echo "***"
		    echo "'$OPTARG' is a forbidden device!"
		    echo
		    echo -n "Forbidden devices: "
		    echo ${FORBIDDEN_DEVICES[*]}
		    echo "***"
		    exit 1
		fi
	    done
	    DEV=$OPTARG
	    ;;
	F)
	    FORMAT="format"
	    ;;
    esac
done

if [ "$DEPLOY" != "NONE" ] && [ -z $DEV ]; then
    echo "No device provided. Use $0 -d $2 -D /dev/xxx"
    exit 2
fi

if [ "$FORMAT" != "NONE" ] && [ -z $DEV ]; then
    echo "No device provided. User $0 -F -D /dev/xxx"
    exit 2
fi

# Create the output directory
if [ ! -e ${BUILDOUTPUT} ]; then
    mkdir ${BUILDOUTPUT}
fi

if [ "$BUILD" == "ALL" ] || [ "$BUILD" == "X_LOAD" ]; then
    buildXLoader
fi

if [ "$BUILD" == "ALL" ] || [ "$BUILD" == "U_BOOT" ]; then
    buildUBoot
fi

if [ "$BUILD" == "ALL" ] || [ "$BUILD" == "KERNEL" ]; then
    buildKernel
fi

if [ "$BUILD" == "ALL" ] || [ "$BUILD" == "WIFI" ]; then
    buildWifiDriver
fi

if [ "$BUILD" == "ALL" ] || [ "$BUILD" == "ANDROID" ]; then
    buildAndroid
fi

if [ "$BUILD" == "ANDROID-SDK" ]; then
    buildAndroidSdk
fi

if [ "$BUILD" == "ANDROID-SDK-ADDON" ]; then
    buildAndroidSdkAddon
fi

if [ "$DEPLOY" != "NONE" ]; then
    echo
    echo "Deployment uses 'sudo' which will prompt you for your"
    echo "password. Do not run this script with 'sudo'."
    echo
    # Create the boot script for sdcard
    mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Logic PD Android SD Boot" -d device/logicpd/dm3730logic/boot_sd.cmd out/target/product/dm3730logic/boot_sd.scr > mkimage.log 2>&1
    RET=$?
    if [ $RET -ne 0 ]; then
	    echo "***"
        echo "Unable to create the boot script:"
        cat mkimage.log
	    echo "***"
        rm mkimage.log
    fi
    if [ -e out/target/product/dm3730logic/boot_sd.scr ]; then
        cp out/target/product/dm3730logic/boot_sd.scr $BUILDOUTPUT/boot_sd.scr
    fi

    if [ "$DEPLOY" != "X_LOAD" ]; then
        findPartition $FAT32
        mountPartition $PART /mnt/fat32

        sudo cp $BUILDOUTPUT/boot_sd.scr /mnt/fat32/boot.scr 2>&1
        sync; sudo umount /mnt/fat32
    fi
fi

if [ "$DEPLOY" == "ALL" ] || [ "$DEPLOY" == "X_LOAD" ]; then
    unmountSD

    if [ ! -e /mnt/fat32 ]; then
	sudo mkdir /mnt/fat32
    fi    

    findPartition $FAT32

    mountPartition $PART /mnt/fat32
    
    sudo cp $BUILDOUTPUT/MLO /mnt/fat32 > cp.log 2>&1
    RET=$?
    sync; sudo umount /mnt/fat32
    
    if [ $RET -eq 0 ]; then
	echo "X-Loader deployed, SD card can be removed"
	rm -f cp.log
    else
	echo "***"
	echo "Can't deploy X-Loader to '$DEV'"
	cat cp.log
	echo "***"
	rm -f cp.log
    fi	
fi

if [ "$DEPLOY" == "ALL" ] || [ "$DEPLOY" == "U_BOOT" ]; then
    unmountSD

    if [ ! -e /mnt/fat32 ]; then
	sudo mkdir /mnt/fat32
    fi

    findPartition $FAT32

    mountPartition $PART /mnt/fat32

    sudo cp $BUILDOUTPUT/u-boot.bin /mnt/fat32 > cp.log 2>&1
    RET=$?
    sync; sudo umount /mnt/fat32

    if [ $RET -eq 0 ]; then
	echo "U-boot deployed, SD card can be removed"
	rm -f cp.log
    else
	echo "***"
	echo "Can't deploy U-Boot to '$DEV'"
	cat cp.log
	echo "***"
	rm -f cp.log
    fi	
fi

if [ "$DEPLOY" == "ALL" ] || [ "$DEPLOY" == "KERNEL" ]; then
    unmountSD

    if [ ! -e /mnt/fat32 ]; then
	sudo mkdir /mnt/fat32
    fi

    findPartition $FAT32

    mountPartition $PART /mnt/fat32

    sudo cp $BUILDOUTPUT/uImage /mnt/fat32/uImage > cp.log 2>&1
    RET=$?
    sync; sudo umount /mnt/fat32
    
    if [ $RET -eq 0 ]; then
	echo "Kernel deployed, SD card can be removed"
	rm -f cp.log
    else
	echo "***"
	echo "Can't deploy Kernel to '$DEV'"
	cat cp.log
	echo "***"
	rm -f cp.log
    fi		
fi

if [ "$DEPLOY" == "ALL" ] || [ "$DEPLOY" == "ANDROID" ]; then
    unmountSD

    if [ ! -e /mnt/ext3 ]; then
	sudo mkdir /mnt/ext3
    fi

    findPartition $EXT3

    mountPartition $PART /mnt/ext3

    sudo tar -jxf $BUILDOUTPUT/rootfs.tar.bz2 --numeric-owner -C /mnt/ext3 > tar.log 2>&1
    RET=$?
    sync; sudo umount /mnt/ext3

    if [ $RET -eq 0 ]; then
	echo "Android deployed, SD card can be removed"
	rm -f tar.log
    else
	echo "***"
	echo "Can't deploy Android to '$DEV'"
	cat tar.log
	echo "***"
	rm -f tar.log
    fi	
fi

if [ "$FORMAT" == "format" ]; then
    # Cause the SUDO password to be asked before we start
    # since the next 2 commands is making us ask for the
    # password twice.
    DISKNAME=`sudo fdisk -l $DEV | grep $DEV:`
    if [ "$DISKNAME" == "" ]; then
	echo "***"
	echo "Can't find '$DEV'"
	echo "***"
	exit 4
    fi

    unmountSD

    echo "Formatting $DISKNAME"
    echo
    echo -n "Do you wish to continue? (y/N) "
    read answer
    if [ "$answer" == "y" ] || [ "$answer" == "Y" ]; then
	SDSIZE=`echo $DISKNAME | awk '{print$(NF-1)}'`
	FATEND=7
	
	echo "[Partitioning $DEV...]"
	
	sudo fdisk "$DEV" &> /dev/null << EOF
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
	unmountSD

	echo "[Making filesystems...]"
	
	sudo mkfs.vfat -F 32 -n boot "$DEV"1 > /dev/null 2>&1
	sudo mkfs.ext3 -L rootfs "$DEV"2 > /dev/null 2>&1
    fi
fi
