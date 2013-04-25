#!/bin/sh

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
	if trap | grep mktemp_env_cleanup
	then
		unset TMP_FILES
		set | grep TMP_FILES
		trap mktemp_env_cleanup EXIT
	fi
	local MKTEMP_OUT
	MKTEMP_OUT=`mktemp ${*:2}`
	TMP_FILES[${#TMP_FILES[*]}]="${MKTEMP_OUT}"
	eval $1=${MKTEMP_OUT}
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
		     ) 2>${TIME} 3>&1
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
		     ) 2> ${TIME} 3>&1
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

	MNT_POINTS=`cat /proc/mounts | grep $DEV | awk '{print $2}' | sed 's/\\\\0/\\\\00/g'`
	for I in ${MNT_POINTS}
	do
		echo -e "Unmounting ${I}"
		sudo umount "`echo -e ${I}`" || return 1
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
		sudo fdisk /dev/$DEV >/dev/null 2>&1 <<-EOF
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
	if [ ! -e "${1}" ]
	then
		echo "Missing \"${1}\"! Cannot continue."
		exit 1
	fi
	if [ "${CHECKING_COMPONENTS}" == "1" ]
	then
		if [ ! "${1:0:1}" == "/" ]
		then
			echo -en "${ROOT}" 1>&4
		fi
		echo "${1}" 1>&4
	fi
}

##
#
#
##
finished_checking_components()
{
	if [ "${CHECKING_COMPONENTS}" == "1" ]
	then
		exit 255
	fi
}

##
# create_release
#
#
##
create_release()
{
	local i
	local match="deploy "
	local files=( )
	local components
	local components_sorted
	local tmp
	local NAME
	local REL_NAME
	local REGEX_CLEAN_ROOT
	local REGEX_CLEAN_NAME
	local MD5
	mktemp_env components
	mktemp_env components_sorted

	for ((i=0;i<${#BUILD_OPTION[*]};++i))
	do
		tmp=${BUILD_COMMAND[i]}
		tmp=${tmp:0:${#match}}

		if [ "${tmp}" == "${match}" ]
		then
			local cmd=`echo ${BUILD_COMMAND[i]} | sed 's/deploy /deploy_/'`
			((CHECKING_COMPONENTS=1 ${cmd} 4>&1 &>/dev/null) || echo -en) >> ${components}
		fi
	done

	# Create a script for the generating the files in element form, and source it
	cat ${components} | sort -u | awk '{print "files[${#files[@]}]=\"" $0 "\""}' > ${components_sorted}
	. ${components_sorted}

	REGEX_CLEAN_ROOT=`echo -en "${ROOT}" | sed -re 's/(]|[[\\\/.+*?{\(\)\|\^])/\\\\\1/g'`
	NAME=`date +Release_%Y%m%d`
	REGEX_CLEAN_NAME=`echo -en "${NAME}" | sed -re 's/(]|[[\\\/.+*?{\(\)\|\^])/\\\\\1/g'`

	for((i=0;i<${#files[@]};++i))
	do
		files[i]=`echo ${files[i]} | sed -re 's|^('${REGEX_CLEAN_ROOT}')/*|'${REGEX_CLEAN_NAME}'/|g'`
	done

	echo "Creating release"
	echo -n " - Generating tarball"
	cd ${ROOT}
	rm -f ${NAME};ln -fs . ${NAME}
	tar chf ${NAME}.tar "${files[@]}" ${NAME}/build-tools/ ${NAME}/build.sh ${NAME}/.cached_android_env --exclude \.git
	rm -f ${NAME};mkdir ${NAME}
	repo manifest -r -o ${NAME}/manifest.xml &>/dev/null
	tar -p -rf ${NAME}.tar ${NAME}/manifest.xml
	MD5=`md5sum ${NAME}/manifest.xml`
	REL_NAME=${NAME}_`echo $MD5 | head -c 8`
	rm -Rf ${NAME}

	mkdir -p releases
	mv ${NAME}.tar releases/${REL_NAME}.tar
	echo -en "\n - Release posted to releases/${REL_NAME}.tar\n"
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
parse_options_int()
{
	local count=
	local availopts=Aj:cvh?D:

	# Reset the hflag and rerun parse_options; it's possible this
	# got set before all the build options were added.
	hflag=0

	for ((i=0;i<${#BUILD_OPTION[*]};++i))
	do
		OPT=`eval echo $"${BUILD_OPTION[i]}"`
		CMD=`eval echo $"${BUILD_COMMAND[i]}"`
		FLAG=${OPT:0:2}
		availopts=${availopts}${FLAG}
	done
	
	# Reset getopts
	unset OPTARG
	unset OPTIND
	
	while getopts ${availopts} name
	do
		eval count=$((count+1))
		case $name in
			A) build_all;;
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
		hflag=1
	fi
}

parse_options()
{
	parse_options_int $* >/dev/null 2>&1
}

##
# choose_options [command line arguments to script]
#
# Parses command line arguments against build options added by
# "build_add" to the script.
##
choose_options()
{
	parse_options "${@}"

	if [ "$hflag" == "1" ]
	then
		print_help
	fi
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
#
#
#
##
find_build_options()
{
	local i
	local match="build "
	local tmp
	for ((i=0;i<${#BUILD_OPTION[*]};++i))
	do
		tmp=${BUILD_COMMAND[i]}
		tmp=${tmp:0:${#match}}

		if [ "${tmp}" == "${match}" ]
		then
			echo $i
		fi
	done
}

# Query distribution information
DISTRIB_ID=`lsb_release -i | sed 's/^[^:]*:[[:blank:]]*//'`
DISTRIB_RELEASE=`lsb_release -r | sed 's/^[^:]*:[[:blank:]]*//'`

SELF=`which -- $0`

# Normalize the path to the folder build.sh is located in.
cd $(readlink -f $(dirname $(which -- $SELF)))

BUILD_TARGETS=

# Setup some environment variables.
TIMEFORMAT='%R seconds'
ROOT=${PWD}
JOBS=8
CLEAN=0
VERBOSE=0
DEV=
EXIT_ON_ERROR=1
