#! /usr/bin/env bash

rootdir=$(realpath "$(dirname "$(realpath "$0")")/..")
# shellcheck disable=SC1091
. "${rootdir}"/common/utils.sh


template_file=${rootdir}/etc/cross-compilation.conf.template

python_script=$(dirname "$(realpath "$0")")/$(basename "$0" .sh).py

if [ ! -e "${python_script}" ];
then
	fatal "$python_script does not exist"
fi

log "Executing ${python_script} ${template_file}"
"$python_script" "$template_file"
