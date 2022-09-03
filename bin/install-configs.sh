#! /usr/bin/env bash

rootdir=$(dirname "$(realpath "$0")")/..

if [ ! "$#" == 1 ];
then
	echo "Must have the configuration directory as argument"
	exit 1
fi
configdir=$(realpath "$1")
if [ ! -d "$configdir" ];
then
	echo Configuration directory "$configdir" does not exit
	exit 1
fi

readarray -d '' configs < <(find "${configdir}" -maxdepth 2  -iname 'env-*.sh'  -print0)

for config in "${configs[@]}";
do
	name=$(basename "$config")
	target=${rootdir}/etc/"${name}"

	if [ ! -L "${target}" ] || [ "$config" != "$(realpath "${target}")" ] ;
	then
		echo "Creating symbolic link $name ${target}"
		ln -sf "${config}" "${target}"
	else
		echo "${target}" already exists
	fi
done