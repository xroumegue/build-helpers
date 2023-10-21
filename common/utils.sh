#! /usr/bin/env bash

function log {
    local msg
    msg="$1"

    if [ -n "${verbose}" ] && $verbose;
    then
        echo "$msg"
    fi
}

function fatal {
    local msg
    msg="$1"

    echo "$msg"
    exit 1
}

function list_configurations {
	(
    # shellcheck disable=SC2154
	cd "${rootdir}"/etc/ || exit
	for f in env-default-*.sh;
	do
		a=${f#env-default-*}
		echo "${a%*.sh}"
	done
	)
}

function get_default {
    if [ -z ${buildenv+x} ];
    then
        buildenv=default
    fi

    # shellcheck disable=SC2154
    envfile="${rootdir}"/etc/env-"${buildenv}".sh

    if [ ! -e "${envfile}" ];
    then
        fatal "Environment ${envfile} file not found"
    fi

    # shellcheck disable=SC1090
    . "${envfile}"

    envfile_host="${rootdir}"/etc/env-"$(hostname -s)".sh
    if [ -e "${envfile_host}" ];
    then
    # shellcheck disable=SC1090
        . "${envfile_host}"
    fi
}

get_default
