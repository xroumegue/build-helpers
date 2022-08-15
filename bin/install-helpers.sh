#! /usr/bin/env bash

rootdir=$(dirname "$(realpath "$0")")/..
readarray -d '' scripts < <(find "${rootdir}" -maxdepth 2  -iname '*-build.sh'  -print0)

for script in "${scripts[@]}";
do
	name=$(basename "$script")
	target=~/.local/bin/"${name}"

	if [ ! -L "${target}" ];
	then
		echo "Creating symbolic link ${target}"
		ln -s "${script}" "${target}"
	fi
done