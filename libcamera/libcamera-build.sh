#! /usr/bin/env bash

set -e

rootdir=$(realpath "$(dirname "$(realpath "$0")")/..")

function usage {
cat << EOF
    $(basename "$0") [OPTIONS] CMD
        --help, -h
            This help message
        --verbose, -v
            Show some verbose logs
        --installdir, -n
            NFS directory
        --cross_compilation_conf, -c
            Meson cross compilation configuration file
        --sysrootdir, -s
            sysroot SDK directory
EOF
}

opts_short=hvc:s:n:b:
opts_long=help,verbose,cross_compilation_conf:,sysrootdir:,installdir:,buildenv:
options=$(getopt -o ${opts_short} -l ${opts_long} -- "$@" )

# shellcheck disable=SC2181
[ $? -eq 0 ] || {
    echo "Incorrect options provided"
    exit 1
}

eval set -- "$options"
while true; do
    case "$1" in
        --cross_compilation_conf | -c)
            shift
            cross_compilation_conf=$1
            ;;
        --help | -h)
            usage
            exit 0
            ;;
        --installdir | -n)
            shift
            installdir=$1
            ;;
        --buildenv | -b)
            shift
            buildenv=$1
            ;;
        --sysrootdir | -s)
            shift
            sysrootdir=$1
            ;;
        --verbose | -v)
            verbose=true
            ;;
        --)
            shift
            break
            ;;
        *)
            ;;
    esac
    shift
done

declare -a commands
commands+=("${@:-all}")
buildenv=${buildenv:-default}
export buildenv

# shellcheck disable=SC1091
. "${rootdir}"/common/utils.sh

export verbose
verbose=${verbose:-false}
sysrootdir=${sysrootdir:-${sysroot_target_default}}
installdir=${installdir:-${installdir_default}}
cross_compilation_conf=$(realpath "${cross_compilation_conf:-${cross_compilation_conf_default}}")

meson=/usr/bin/meson
ninja=/usr/bin/ninja

function generate_cross_compilation_conf {
	template_file="${rootdir}"/etc/cross-compilation.conf.template
	if [ "${template_file}" == "${cross_compilation_conf}".template ];
	then
		"${rootdir}"/bin/templatize-cross-compilation.sh
	fi
}

function do_clean {
    rm -Rf build
}

function do_config {
    generate_cross_compilation_conf

    ${meson} setup \
        --cross-file "${cross_compilation_conf}" \
        --prefix /usr \
        --wrap-mode=default \
        -Dipas=rkisp1 \
        -Dpipelines=rkisp1,simple \
        -Dcam=enabled \
        -Ddocumentation=enabled \
        -Dpycamera=enabled \
        -Dtest=false \
        --buildtype=debug \
        build
}

function do_compile {
    ${ninja} -C build
}

function do_install {
    sudo \
        DESTDIR="${installdir}" \
        ${ninja} -C build \
        install
    set -x
    sudo rsync -arzv "${installdir}"/usr/lib/libcamera "${sysrootdir}"/usr/lib/libcamera
    sudo rsync -arzv "${installdir}"/usr/lib/libcamera.so* "${sysrootdir}"/usr/lib
    sudo rsync -arzv "${installdir}"/usr/lib/libcamera-base.so* "${sysrootdir}"/usr/lib

}

function do_build {
    do_compile
    do_install
}

for cmd in "${commands[@]}";
do
    case "$cmd" in
        "clean")
            echo Cleaning ...
            do_clean
            ;;
        "config")
            echo Configuring ...
            do_config
            ;;
        "compile")
            echo Compiling...
            do_compile
            ;;
        "build")
            echo Building...
            do_build
            ;;
        "install")
            echo Installing...
            do_install
            ;;
        "all")
            do_clean
            do_config
            do_build
            ;;
        "*")
            echo "Running $cmd..."
            echo "Running custom $cmd..."
            ninja -C build "$cmd"
            ;;
    esac
done

