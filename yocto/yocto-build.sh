#! /usr/bin/env bash

rootdir=$(dirname "$(realpath "$0")")/..
# shellcheck disable=SC1091
. "${rootdir}"/common/utils.sh

function usage {
cat << EOF
    $(basename "$0") [OPTIONS] CMD
        --help, -h
            This help message
        --verbose, -v
            Show some verbose logs
        --image, -i
            Image name to build
        --builddir, -b
            build directory name, default to build-\$image
        --sdkdir, -s
            Yocto SDK directory
        --installdir, -n
            NFS directory
        --workdir, -w
            Working directory
        --update, -u
            Update the git repositories

    Possible commands:
        setup
        build
        sdk
        deploy
        deploy-sdk
EOF
}

opts_short=vhui:b:s:n:w:
opts_long=verbose,help,update,image:,builddir:,sdkdir:,installdir:,workdir:

options=$(getopt -o ${opts_short} -l ${opts_long} -- "$@" )

# shellcheck disable=SC2181
[ $? -eq 0 ] || {
    echo "Incorrect options provided"
    exit 1
}

eval set -- "$options"
while true; do
    case "$1" in
        --verbose | -v)
            verbose=true
            ;;
        --help | -h)
            usage
            exit 0
            ;;
        --image | -i)
            shift
            image=$1
            ;;
        --builddir | -b)
            shift
            builddir=$1
            ;;
        --sdkdir | -s)
            shift
            sdkdir=$1
            ;;
        --installdir | -n)
            shift
            installdir=$1
            ;;
        --workdir | w)
            shift
			workdir=$(realpath "$1")
            ;;
        --update | u)
            update=true
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

image=${image:-core-image-base}
machine=${machine:-generic-arm64}
builddir=${builddir:-build-"${image}"}
verbose=${verbose:-false}
update=${update:-false}
installdir=${installdir:-${installdir_default}}
sdkdir=${sdkdir:-${sdkdir_default}}
workdir=${workdir:-$(pwd)}

function add_repo {
    local git_repository
    local git_name
    local git_branch

    git_repository="$1"
    git_name=$(basename "$1")
    git_branch="$2"

    if [ ! -d "${git_name}" ];
    then
        git clone "${git_repository}"
    else
        log "${git_name} already exists..fetching."
        if "${update}";
        then
            git -C "${git_name}" fetch --all --prune
        fi
    fi

    log "Checkout-ing ${git_branch} in ${git_name}"
    git -C "${git_name}" checkout origin/"${git_branch}"
}

function add_layer {
    local layer_name="$1"
    if [  "$(grep -c -E "${layer_name}\s+" conf/bblayers.conf)" -ne 1 ];
    then
        bitbake-layers add-layer  "${layer_name}"
    else
        log "Layer $(basename "${layer_name}") already exists"
    fi
}

function do_enter_env {
    if [ -z "$OEROOT" ];
    then
        # shellcheck disable=SC1091
        . poky/oe-init-build-env "${builddir}"
    fi
}

function do_setup {
    log "Setup environment"
    add_repo git://git.yoctoproject.org/poky master
    add_repo git://git.yoctoproject.org/meta-arm master
    add_repo git://git.openembedded.org/meta-openembedded master
    add_repo git@github.com:xroumegue/meta-staging main

    do_enter_env

    echo "${workdir}"/meta-arm/meta-arm-toolchain
    add_layer "${workdir}"/meta-arm/meta-arm-toolchain
    add_layer "${workdir}"/meta-arm/meta-arm
    add_layer "${workdir}"/meta-openembedded/meta-oe
    add_layer "${workdir}"/meta-openembedded/meta-python
    add_layer "${workdir}"/meta-openembedded/meta-multimedia
    add_layer "${workdir}"/meta-staging

    if [ "$(grep -c -E "# Customization" conf/local.conf)" -eq 0 ]
    then
    cat <<EOF >> conf/local.conf
# Customization
MACHINE = "${machine}"
DL_DIR = "${workdir}/downloads"
SSTATE_DIR = "${workdir}/sstate-cache"
EXTRA_IMAGE_FEATURES += "\
  debug-tweaks \
  nfs-client \
  ssh-server-openssh \
  tools-debug \
"

PACKAGECONFIG:append:pn-libcamera = " gst python"

IMAGE_INSTALL:append = "\
     libcamera \
     libcamera-gst \
     libcamera-python \
     v4l-utils \
     yavta \
"

DISTRO_FEATURES += " systemd"
VIRTUAL-RUNTIME_init_manager = "systemd"
DISTRO_FEATURES_BACKFILL_CONSIDERED += "sysvinit"
IMAGE_FSTYPES = "tar.bz2"

# Set generic-arm64 to compatible machine in linux-yocto-dev.bb
#PREFERRED_PROVIDER_virtual/kernel = "linux-yocto-dev"
#PREFERRED_PROVIDER_virtual/kernel = "linux-dummy"
SERIAL_CONSOLES = "115200;ttymxc1"

# Use by mount-dev to get the nfs server ip address
IMAGE_INSTALL:append = " mount-dev "
#CONF_CUSTOM_NFS_IP_ADDRESS = "xxx.xxx.xxx.xxx"

# No TRNG, accelerate boot time
PACKAGECONFIG:remove:pn-openssh = "rng-tools"
MACHINE_EXTRA_RRECOMMENDS += "ssh-pregen-hostkeys"

EOF
    fi

}

function do_build {
    log "Building image ${image}"
    do_enter_env
    bitbake "${image}"
}

function do_deploy {
    log "Deploying ${image}"
    rootfsimage=$(find "${builddir}/tmp/deploy/images" -regextype posix-extended -regex ".*/${image}-${machine}\.tar\.bz2")
    [ -e "${rootfsimage}" ] || fatal "root fs image not found"
    log "Deploying rootfsimage $rootfsimage to ${installdir}"
    sudo --preserve-env bash -c "rm -Rf ${installdir}; mkdir -p ${installdir}; tar -C ${installdir} -xjf ${rootfsimage};"
}

function do_sdk {
    log "Building SDK"
    do_enter_env
    bitbake "${image}" -c populate_sdk
}

function do_deploy_sdk {
    log "Deploying SDK"

    sdkimage=$(find "${builddir}/tmp/deploy/sdk" -regextype posix-extended -regex ".*/poky-glibc-x86_64-${image}-armv8a-${machine}-toolchain-([0-9]\.[0-9]).*\.sh")
    [ -e "${sdkimage}" ] || fatal "sdk image not found"
    echo "Find sdimage $sdkimage"

    [[ "$sdkimage" =~ poky-glibc-x86_64-${image}-armv8a-${machine}-toolchain-([0-9]\.[0-9]).*\.sh ]]
    [ ${#BASH_REMATCH[@]} -eq 2 ] || fatal "Invalid sdkimage!"
    sdkversion=${BASH_REMATCH[1]}
    echo "$sdkversion"
    sudo rm -Rf "${sdkdir}/$sdkversion"
    sudo "${sdkimage}" -y -d "${sdkdir}/$sdkversion"
}

if [ ! -d "${workdir}" ];
then
    mkdir -p "${workdir}"
fi

cd "${workdir}" || fatal "Change to working directory failed"

for cmd in "${commands[@]}";
do
    case "$cmd" in
        "setup")
            do_setup
            ;;
        "build")
            do_build
            ;;
        "deploy")
            do_deploy
            ;;
        "sdk")
            do_sdk
            ;;
        "deploy-sdk")
            do_deploy_sdk
            ;;
    esac
done

