#!/bin/bash
set -e
OUT=/dev/null
#OUT=/dev/stdout
#set -x

MAX_ALLOWED_DISK_SIZE=4095737856
EXPECTED_ARGS=1
if [ $# == $EXPECTED_ARGS ]
then
	echo "Assuming Default Locations for Prebuilt Images"
	$0 $1 ./MLO ./u-boot.bin ./uImage ./boot.scr ./rootfs.tar.bz2 ./Media_Clips ./START_HERE
	exit
fi

if [[ -z $1 || -z $2 || -z $3 || -z $4 ]]
then
	echo "mkmmc-android Usage:"
	echo "	mkmmc-android <device>"
	echo "	  Uses default locations and names of source files/directories"
	echo "	mkmmc-android <device> <MLO> <u-boot.bin> <uImage> <boot.scr> <rootfs tar.bz2 > <Optional Media_Clips> <Optional START_HERE folder>"
	echo "	Example: mkmmc-android /dev/sdc MLO u-boot.bin uImage boot.scr rootfs.tar.bz2 Media_Clips START_HERE"
	exit
fi

DRIVE=$1
DEVICE=`basename $DRIVE`

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

if ! [ -e $DRIVE ]
then
	echo "Error: $DRIVE not found!"
	exit
fi

# Simplistic sanity check to prevent selecting a larger device
# such as a secondary hard drive, or attached backup drive.
DISKSIZE=`sudo fdisk -l $DRIVE | grep Disk | grep $DRIVE`
SIZE=`echo $DISKSIZE | awk '{print $5}'`
if [ $SIZE -gt $MAX_ALLOWED_DISK_SIZE ]
then
	echo ""
	echo "*** Warning! Device reports > MAX_ALLOWED_DISK_SIZE ($MAX_ALLOWED_DISK_SIZE). ***"
	echo "  $DISKSIZE"
	echo "Are you sure you selected the correct device? [y/n]"
	read ans
	if ! [[ $ans == 'y' ]]
	then
		exit
	fi
fi

for file in $(find /sys/block/$DEVICE/device/ /sys/block/$DEVICE/ -maxdepth 1 2>/dev/null \
 |egrep '(vendor|model|manfid|name|/size|/sys/block/[msh][mdr]./$|/sys/block/mmcblk./$)'|sort);
do [ -d $file ] && echo -e "\n  -- DEVICE $(basename $file) --" && continue;
grep -H . $file|sed -e 's|^/sys/block/||;s|/d*e*v*i*c*e*/*\(.*\):| \1 |'|awk '{if($2 == "size") {printf "%-3s %-6s: %d MB\n", $1,$2,(($3 * 512)/1048576)} else {printf "%-3s %-6s: ", $1,$2;for(i=3;i<NF;++i) printf "%s ",$i;print $(NF) };}';
done
echo "";

echo "[Unmounting all existing partitions on the device ]"

devices=`ls /sys/block/$DEVICE/$DEVICE* -d | sed "s^/sys/block/$DEVICE/^^"`
for f in $devices; do
	MOUNTCHECK=`mount | grep "^/dev/$f" | wc -l`
	if [[ $MOUNTCHECK = '1' ]]
	then
		MOUNTINFO=`mount | grep "^/dev/$f" | awk '{ print $1 " " $2 " " $3 " " $4 " " $5 }' `
		echo "  unmounting $f ($MOUNTINFO)"
		sudo umount /dev/$f
	fi
done
#sudo umount $DRIVE

echo ""
echo "All data on $DRIVE now will be destroyed! Continue? [y/n]"
read ans
if ! [ $ans == 'y' ]
then
	exit
fi

echo "[Partitioning $DRIVE...]"

SIZE=`sudo fdisk -l $DRIVE | grep Disk | awk '{print $5}'`
	 
echo DISK SIZE - $SIZE bytes
 
CYLINDERS=`echo $SIZE/255/63/512 | bc`
 
echo CYLINDERS - $CYLINDERS

sudo dd if=/dev/zero of=$DRIVE bs=1024 count=1024 &> $OUT

{
echo ,9,0x0C,*
echo ,$(expr $CYLINDERS / 2),,-
echo ,,0x0C,-
} | sudo sfdisk -D -H 255 -S 63 -C $CYLINDERS $DRIVE &> $OUT

sudo partprobe $DRIVE

sudo dd if=/dev/zero of="${DRIVE}${PART}1" bs=512 count=1 &> $OUT
sudo dd if=/dev/zero of="${DRIVE}${PART}2" bs=512 count=1 &> $OUT
sudo dd if=/dev/zero of="${DRIVE}${PART}3" bs=512 count=1 &> $OUT

echo "[Making filesystems...]"

if [ $DRIVE == '/dev/mmcblk0' ]
then
	PART='p'
else
	PART=''
fi

sudo mkfs.vfat -F 32 -n boot "${DRIVE}${PART}1" &> $OUT
sudo mkfs.ext3 -L rootfs "${DRIVE}${PART}2" &> $OUT
sudo mkfs.vfat -F 32 -n data "${DRIVE}${PART}3" &> $OUT

echo "[Copying files...]"

sudo mount "${DRIVE}${PART}1" /mnt
sudo cp $2 /mnt/MLO
sync
sudo cp $3 /mnt/u-boot.bin
sync
sudo cp $4 /mnt/uImage
sudo cp $5 /mnt/boot.scr
if [ "$8" ] && [ -d $8 ]
then
        echo "[Copying START_HERE directory to boot partition]"
        sudo cp -r $8 /mnt/START_HERE
fi

sudo umount "${DRIVE}${PART}1"

sudo mount "${DRIVE}${PART}2" /mnt
sudo tar jxvf $6 -C /mnt &> $OUT
#sudo chmod 755 /mnt
sudo umount "${DRIVE}${PART}2"

if [ "$7" ] && [ -d $7 ]
then
	echo "[Copying all clips to data partition]"
	sudo mount "${DRIVE}${PART}3" /mnt
	if [ "$(ls -A $7/*)" ]; then
		sudo cp -r $7/* /mnt/
	else
		echo "no media clips to copy"
	fi
	sudo umount "${DRIVE}${PART}3"
fi

echo "[Done]"
