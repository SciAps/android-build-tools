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

source build-tools/build_core.sh

# Source additional build scripts
for I in build-tools/build_*.sh
do
	if [ "$I" != "build-tools/build_core.sh" ]
	then
		source $I
	fi
done

check_environment

trap generic_error ERR
set -E

choose_options "${@}"
run_options
