#! /usr/bin/env bash

rootdir=$(dirname "$(realpath "$0")")/..

function usage {
cat << EOF
    $(basename "$0") [OPTIONS] CMD
        --help, -h
            This help message
        --verbose, -v
            Show some verbose logs
        --configuration
            Yocto configuration (master, nxp)
        --image
            Image name to build
        --branch
            manifest branch to build
        --distro
            Distribution to build
        --manifest
            manifest to build
        --builddir
            build directory name, default to build-\$image
        --force
            Force local.conf customization
        --image
        --sdkdir
            Yocto SDK directory
        --installdir
            NFS directory
        --workdir
            Working directory
        --update
            Update the git repositories
        --urlmanifest
            URL of manifest repository
        --downloaddir
            Yocto Download directory
        --downloadmirror
            Yocto Download mirror
        --sstatedir
            Yocto dstatedir directory
        --sstatemirror
            Yocto dstatedir directory
        --extra_ca_cert
            Extra CA certificate file

    Possible commands:
        setup
        list
        build
        sdk
        deploy
        deploy-sdk
EOF
}

opts_short=vh
opts_long=verbose,help,update,force,image:,builddir:,sdkdir:,installdir:,workdir:,sstatedir:,downloaddir:,sstatemirror:,hashserver:,prserver:,downloadmirror:,configuration:,branch:,manifest:,urlmanifest:,machine:,distro:,buildenv:,extra_ca_cert:

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
        --image)
            shift
            image=$1
            ;;
        --branch)
            shift
            branch=$1
            ;;
        --configuration)
            shift
            configuration=$1
            ;;
        --builddir)
            shift
            builddir=$1
            ;;
        --buildenv)
            shift
            # shellcheck disable=SC2034
            buildenv=default-$1
            ;;
        --downloaddir)
            shift
            downloaddir=$1
            ;;
        --downloadmirror)
            shift
            downloadmirror=$1
            ;;
        --force)
            force=true
            ;;
        --hashserver)
            shift
            hashserver=$1
            ;;
        --machine)
            shift
            machine=$1
            ;;
        --distro)
            shift
            distro=$1
            ;;
        --prserver)
            shift
            prserver=$1
            ;;
        --sdkdir)
            shift
            sdkdir=$1
            ;;
        --sstatedir)
            shift
            sstatedir=$1
            ;;
        --sstatemirror)
            shift
            sstatemirror=$1
            ;;
        --installdir)
            shift
            installdir=$1
            ;;
        --workdir)
            shift
            workdir=$(realpath "$1")
            ;;
        --update)
            update=true
            ;;
        --url)
            shift
            urlmanifest=$1
            ;;
        --extra_ca_cert)
            shift
            extra_ca_cert=$1
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

# shellcheck disable=SC1091
. "${rootdir}"/common/utils.sh

image_default=${image_default:-core-image-base}
image=${image:-${image_default}}

machine_default=${machine_default:-generic-arm64}
machine=${machine:-${machine_default}}

distro_default=${distro_default:-poky}
distro=${distro:-${distro_default}}

configuration_default=${configuration_default:-master}
configuration=${configuration:-${configuration_default}}

builddir=${builddir:-build-"${image}"}


branch_default=${branch_default:-}
branch=${branch:-${branch_default}}

manifest_default=${manifest_default:-default}
manifest=${manifest:-${manifest_default}}

verbose=${verbose:-false}
force=${force:-false}
update=${update:-false}

urlmanifest_default=${urlmanifest_default:-}
urlmanifest=${urlmanifest:-${urlmanifest_default}}

installdir=${installdir:-${installdir_default}}
sdkdir=${sdkdir:-${sdkdir_default}}
workdir=${workdir:-$(pwd)}
#dependency on workdir
sstatedir_default=${sstatedir_default:-${workdir}/sstate-cache}
sstatedir=${sstatedir:-${sstatedir_default}}

sstatemirror_default=${sstatemirror_default:-}
sstatemirror=${sstatemirror:-${sstatemirror_default}}

hashserver_default=${hashserver_default:-}
hashserver=${hashserver:-${hashserver_default}}

prserver_default=${prserver_default:-}
prserver=${prserver:-${prserver_default}}

downloaddir_default=${downloaddir_default:-${workdir}/downloads}
downloaddir=${downloaddir:-${downloaddir_default}}

downloadmirror_default=${downloadmirror_default:-}
downloadmirror=${downloadmirror:-${downloadmirror_default}}

srcdir=${workdir}

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

function do_common_setup {
    cat <<EOF >> conf/local.conf
# Customization

BB_NICE_LEVEL = "10"
MACHINE = "${machine}"
DISTRO = "${distro}"

INHERIT += "rm_work"

EOF

    if [ -n "${downloaddir}" ];then
        cat <<EOF >> conf/local.conf
DL_DIR = "${downloaddir}"
EOF
    fi

    if [ -n "${sstatedir}" ];then
        cat <<EOF >> conf/local.conf
SSTATE_DIR = "${sstatedir}"
EOF
    fi

    if [ -n "${sstatemirror}" ];then
        cat <<EOF >> conf/local.conf
SSTATE_MIRRORS = "file://.* file://${sstatemirror}/PATH"
EOF
    fi
    if [ -n "${downloadmirror}" ];then
        cat <<EOF >> conf/local.conf
PREMIRRORS:prepend = "\\
    git://.*/.* file://${downloadmirror}/ \\
    ftp://.*/.* file://${downloadmirror}/ \\
    http://.*/.* file://${downloadmirror}/ \\
    https://.*/.* file://${downloadmirror}/"

EOF
    fi
    if [ -n "${hashserver}" ];then
        cat <<EOF >> conf/local.conf
BB_HASHSERVE= "${hashserver}"
EOF
    fi
    if [ -n "${prserver}" ];then
        cat <<EOF >> conf/local.conf
PRSERV_HOST= "${prserver}"
EOF
    fi
}


function install_buildtools {
    cd ${srcdir}

    if [ -n "${force}" ] && $force; then
        rm -rf poky/buildtools
    fi

    if [ ! -d poky/buildtools ]; then
        poky/scripts/install-buildtools
        if [[ -n "$extra_ca_cert" ]] && [ -f ${extra_ca_cert} ]; then
            echo "Appending ${extra_ca_cert} to GIT_SSL_CAINFO file"
            cat ${extra_ca_cert} >> poky/buildtools/sysroots/x86_64-pokysdk-linux/etc/ssl/certs/ca-certificates.crt
        fi
    fi
    cd -
}

function source_buildtools {
    _gcc=$(realpath "$(which gcc)")
    if [ ! "${_gcc##*/}" == x86_64-pokysdk-linux-gcc ];then
        # shellcheck disable=SC1091
        . ${srcdir}/poky/buildtools/environment-setup-x86_64-pokysdk-linux
    fi
}

#
# MASTER
#

function do_enter_env_master {
    install_buildtools
    source_buildtools
    if [ -z "$OEROOT" ];
    then
        # shellcheck disable=SC1091
        . poky/oe-init-build-env "${builddir}"
    fi
}

function do_setup_master {
    add_repo git://git.yoctoproject.org/poky master
    add_repo git://git.yoctoproject.org/meta-arm master
    add_repo git://git.openembedded.org/meta-openembedded master
    add_repo https://github.com/xroumegue/meta-staging main

    do_enter_env

    echo "${workdir}"/meta-arm/meta-arm-toolchain
    add_layer "${workdir}"/meta-arm/meta-arm-toolchain
    add_layer "${workdir}"/meta-arm/meta-arm
    add_layer "${workdir}"/meta-openembedded/meta-oe
    add_layer "${workdir}"/meta-openembedded/meta-python
    add_layer "${workdir}"/meta-openembedded/meta-multimedia
    add_layer "${workdir}"/meta-staging

    if [ -n "${force}" ] && $force;
    then
        sed -i -e '/# Customization/,$d' conf/local.conf
    fi

    if [ "$(grep -c -E "# Customization" conf/local.conf)" -eq 0 ]
    then
        do_common_setup
        do_custom_conf
    fi
}

function do_custom_conf_master {
    cat <<EOF >> conf/local.conf

EXTRA_IMAGE_FEATURES += "\\
  debug-tweaks \\
  nfs-client \\
  ssh-server-openssh \\
  tools-debug \\
  tools-sdk \\
  package-management \\
"

PACKAGE_CLASSES = "package_rpm"

PACKAGECONFIG:append:pn-libcamera = " gst python"
PACKAGECONFIG:append:pn-gstreamer1.0-plugins-bad = " kms"
PACKAGECONFIG:remove:pn-perf = " scripting"

IMAGE_INSTALL:append = "\\
     cmake \\
     gstreamer1.0-plugins-good \\
     gstreamer1.0-plugins-bad \\
     gstreamer1.0-plugins-base \\
     libcamera \\
     libcamera-gst \\
     libdrm \\
     libdrm-drivers \\
     libdrm-tests \\
     perf \\
     python3-pip \\
     python3-setuptools \\
     python3-venv \\
     v4l-utils \\
     yavta \\
     opencv \\
     opencv-dev \\
     opencv-staticdev \\
     libgpiod-tools \\
     i2c-tools \\
     i2c-tools-misc \\
"

TOOLCHAIN_HOST_TASK:append = " \\
    nativesdk-python3-pyyaml \\
    nativesdk-python3-jinja2 \\
    nativesdk-python3-ply \\
    nativesdk-python3-sphinx \\
"

DISTRO_FEATURES += " systemd usrmerge"
VIRTUAL-RUNTIME_init_manager = "systemd"
DISTRO_FEATURES_BACKFILL_CONSIDERED += "sysvinit"
IMAGE_FSTYPES = "tar.bz2"

DISTRO_FEATURES:append = " opengl wayland pam"
CORE_IMAGE_EXTRA_INSTALL += " wayland weston"

PREFERRED_PROVIDER_virtual/kernel = "linux-imx"
TOOLCHAIN_TARGET_TASK:append = " kernel-headers"

SERIAL_CONSOLES = "115200;ttymxc1"

# Use by mount-dev to get the nfs server ip address
IMAGE_INSTALL:append = " mount-dev "
#CONF_CUSTOM_NFS_IP_ADDRESS = "xxx.xxx.xxx.xxx"

# No TRNG, accelerate boot time
PACKAGECONFIG:remove:pn-openssh = "rng-tools"
MACHINE_EXTRA_RRECOMMENDS += "ssh-pregen-hostkeys"

PREFERRED_PROVIDER_base-utils = "packagegroup-core-base-utils"
VIRTUAL-RUNTIME_base-utils = "packagegroup-core-base-utils"
VIRTUAL-RUNTIME_base-utils-hwclock = "util-linux-hwclock"

EOF
}

#
# NXP BSP
#
#

function do_setup_nxp {
    repo init -u "${urlmanifest}" -b "${branch}" -m "${manifest}".xml

    if "${update}" || ! [ -d sources ] ;
    then
        repo sync "-j$(nproc)"
    fi
    if [ ! -d "${builddir}" ] || "$force" ;
    then
        # shellcheck disable=SC1091
        # machine variable is overriden in fsl-setup-internal-build
        # with garbage content
        _machine=$machine
        EULA=1 MACHINE=$machine DISTRO=$distro \
            . fsl-setup-internal-build.sh -b "${builddir}"
        machine=$_machine
    else
        do_enter_env
    fi

    if [ -n "${force}" ] && $force;
    then
        sed -i -e '/# Customization/,$d' conf/local.conf
    fi

    if [ "$(grep -c -E "# Customization" conf/local.conf)" -eq 0 ]
    then
        do_common_setup
    fi
}

function do_build_nxp {
    true
}

function do_enter_env_nxp {
    if [ -z "$OEROOT" ];
    then
        # shellcheck disable=SC1091
        . setup-environment "${builddir}"
    fi
}

function do_custom_conf_nxp {
    true
}

#
# Petalinux
#

function do_setup_petalinux {
    srcdir=${workdir}/sources

    repo init -u "${urlmanifest}" -b "${branch}" -m "${manifest}".xml
    add_repo https://github.com/xroumegue/meta-staging petalinux

    if "${update}" || ! [ -d sources ] ;
    then
        repo sync "-j$(nproc)"
    fi

    do_enter_env

    # Add layer(s)
    add_layer "${workdir}"/meta-staging

    if [ -n "${force}" ] && $force;
    then
        sed -i -e '/# Customization/,$d' conf/local.conf
    fi

    if [ "$(grep -c -E "# Customization" conf/local.conf)" -eq 0 ]
    then
        do_common_setup
    fi
}

function do_enter_env_petalinux {
    srcdir=${workdir}/sources
    install_buildtools
    source_buildtools
    if [ -z "$OEROOT" ];
    then
        # shellcheck disable=SC1091
        . setupsdk "${builddir}"
    fi
}

declare -A setup_funcs=(
    [master]=do_setup_master
    [nxp]=do_setup_nxp
    [petalinux]=do_setup_petalinux
)

declare -A enter_env_funcs=(
    [master]=do_enter_env_master
    [nxp]=do_enter_env_nxp
    [petalinux]=do_enter_env_petalinux
)

declare -A custom_conf_funcs=(
    [master]=do_custom_conf_master
)

declare -A build_funcs=(
)

function do_enter_env {
    "${enter_env_funcs[${configuration}]}"
}

function do_custom_conf {
    "${custom_conf_funcs[${configuration}]}"
}

function do_list {
    log "List configurations"
    list_configurations
}

function do_setup {
    log "Setup environment"
    "${setup_funcs[${configuration}]}"

}

function do_build {
    log "Building image ${image}"
    do_enter_env
    if [[ -v build_funcs[${configuration}] ]];
    then
        log "Calling customized build function"
        ${build_funcs[${configuration}]}
    else
        bitbake "${image}"
    fi
}

function do_deploy {
    log "Deploying ${image}"
    rootfsimage=$(find "${builddir}/tmp/deploy/images" -regextype posix-extended -regex ".*/${image}-${machine}\.rootfs\.tar\.(bz2|zst)")
    [ -e "${rootfsimage}" ] || fatal "root fs image not found"
    fstype=${rootfsimage##*.}
    log "Deploying rootfsimage $rootfsimage (${fstype}) to ${installdir}"
    sudo --preserve-env bash -c "rm -Rf ${installdir}; mkdir -p ${installdir}; tar -C ${installdir}  --auto-compress -xf ${rootfsimage};"
}

function do_sdk {
    log "Building SDK"
    do_enter_env
    bitbake "${image}" -c populate_sdk
}

function do_deploy_sdk {
    log "Deploying SDK"

    sdkimage=$(find "${builddir}/tmp/deploy/sdk" -regextype posix-extended -regex ".*/.*-glibc-x86_64-${image}-armv8a-${machine}-toolchain-(.*)\.sh")
    [ -e "${sdkimage}" ] || fatal "sdk image not found"
    echo "Find sdimage $sdkimage"

    [[ "$sdkimage" =~ .*-glibc-x86_64-${image}-armv8a-${machine}-toolchain-(.*)\.sh ]]
    [ ${#BASH_REMATCH[@]} -eq 2 ] || fatal "Invalid sdkimage!"
    sdkversion=${BASH_REMATCH[1]}

    log "Sdk ${sdkversion} image found: $sdkimage"

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
        "list")
            do_list
            ;;
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

