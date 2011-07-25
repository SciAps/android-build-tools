#!/bin/bash

EXPECTED_ARGS=1
if [ $# == $EXPECTED_ARGS ]
then
	echo "Assuming Default Locations for Prebuilt Images"
	$0 $1 Boot_Images/MLO Boot_Images/u-boot.bin Boot_Images/uImage Boot_Images/boot.scr Filesystem/rootfs* Media_Clips
	exit
fi

if [[ -z $1 || -z $2 || -z $3 || -z $4 ]]
then
	echo "mkmmc-android Usage:"
	echo "	mkmmc-android <device> <MLO> <u-boot.bin> <uImage> <boot.scr> <rootfs tar.bz2 > <Optional Media_Clips>"
	echo "	Example: mkmmc-android /dev/sdc MLO u-boot.bin uImage boot.scr rootfs.tar.bz2 Media_Clips"
	exit
fi

if ! [[ -e $2 ]]
then
	echo "Incorrect MLO location!"
	exit
fi

if ! [[ -e $3 ]]
then
	echo "Incorrect u-boot.bin location!"
	exit
fi

if ! [[ -e $4 ]]
then
	echo "Incorrect uImage location!"
	exit
fi

if ! [[ -e $5 ]]
then
	echo "Incorrect boot.scr location!"
	exit
fi

if ! [[ -e $6 ]]
then
	echo "Incorrect rootfs location!"
	exit
fi

echo "All data on "$1" now will be destroyed! Continue? [y/n]"
read ans
if ! [ $ans == 'y' ]
then
	exit
fi

echo "[Unmounting all existing partitions on the device ]"

umount $1*

echo "[Partitioning $1...]"

DRIVE=$1
dd if=/dev/zero of=$DRIVE bs=1024 count=1024 &>/dev/null
	 
SIZE=`fdisk -l $DRIVE | grep Disk | awk '{print $5}'`
	 
echo DISK SIZE - $SIZE bytes
 
CYLINDERS=`echo $SIZE/255/63/512 | bc`
 
echo CYLINDERS - $CYLINDERS
{
echo ,9,0x0C,*
echo ,$(expr $CYLINDERS / 2),,-
echo ,,0x0C,-
} | sfdisk -D -H 255 -S 63 -C $CYLINDERS $DRIVE &> /dev/null

echo "[Making filesystems...]"

mkfs.vfat -F 32 -n boot "$1"1 &> /dev/null
mkfs.ext3 -L rootfs "$1"2 &> /dev/null
mkfs.vfat -F 32 -n data "$1"3 &> /dev/null

echo "[Copying files...]"

mount "$1"1 /mnt
cp $2 /mnt/MLO
cp $3 /mnt/u-boot.bin
cp $4 /mnt/uImage
cp $5 /mnt/boot.scr
umount "$1"1

mount "$1"2 /mnt
tar jxvf $6 -C /mnt &> /dev/null
chmod 755 /mnt
umount "$1"2

if [ "$7" ]
then
	echo "[Copying all clips to data partition]"
	mount "$1"3 /mnt
	cp -r $7/* /mnt/
	umount "$1"3
fi

echo "[Done]"
