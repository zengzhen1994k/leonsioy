#!/bin/bash
#
# Leonid Kogan <leon@leonsio.com>
# Yet Another Homematic Management 
#
# Globale Funktionen
#

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root!" 1>&2
   exit 1
fi

#echo ${0##*/}
#exit;

#Default Settings
LXCNAME=yahm
CCU2Version="2.17.16"
YAHM_DIR=/opt/YAHM
YAHM_TOOLS=/opt/YAHM/share/tools
YAHM_TMP=/tmp/YAHM
YAHM_LIB=/var/lib/yahm
OPTIND=1
IS_FORCE=0
IS_VERBOSE=0
QUIET="--quiet"
VERBOSE=""
DRY_RUN=0
ARCH=""

# Check if we can use colours in our output
use_colour=0
[ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null && use_colour=1

# Some useful functions
progress() {
    [ $use_colour -eq 1 ] && echo -ne "\033[01;32m"
    echo -e "$@" >&2
    [ $use_colour -eq 1 ] && echo -ne "\033[00m"
}

info() {
    [ $use_colour -eq 1 ] && echo -ne "\033[01;34m"
    echo -e "$@" >&2
    [ $use_colour -eq 1 ] && echo -ne "\033[00m"
}

die () {
    [ $use_colour -eq 1 ] && echo -ne "\033[01;31m"
    echo -e "$@" >&2
    [ $use_colour -eq 1 ] && echo -ne "\033[00m"
    exit 1
}

# Load system information
if [ -f ${YAHM_LIB}/systeminfo ]
then
    source ${YAHM_LIB}/systeminfo
else
    source ${YAHM_TOOLS}/arm-board-detect/armhwinfo.sh
    echo "BOARD_TYPE='$BOARD_TYPE'" >> ${YAHM_LIB}/systeminfo
    echo "ARCH='$ARCH'" >> ${YAHM_LIB}/systeminfo
    echo "BOARD_VERSION='$BOARD_VERSION'" >> ${YAHM_LIB}/systeminfo
fi

# check architecture 
#case `dpkg --print-architecture` in
case $ARCH in
    armhf|armv7l|arm64|aarch64)
        ARCH="ARM"
        ;;
    i386|amd64|x86_64)
        ARCH="X86"
        ;;
    *)
        die "Unsupported CPU architecture, we support only ARM and x86"
        ;;
esac

while getopts "${PARAMETER}" OPTION
do
    case $OPTION in
        f)
            IS_FORCE=1
            set +e
            ;;
        b)
            BRIDGE=$OPTARG
            ;;
        i)
            INTERFACE=$OPTARG
            ;;
        w)
            WRITE=1
            ;;
        d)
            DRY_RUN=1
            DATA_FILE=$OPTARG
            ;;
        m)
            MODULE=$OPTARG
            # Pruefen ob Modul existiert
            if [ ! -f "${YAHM_DIR}/share/modules/${MODULE}" ]
            then
                die "Specified module can not be found"
            fi

            # Modul laden
            source ${YAHM_DIR}/share/modules/${MODULE}
            ;;
        v)
            IS_VERBOSE=1
            QUIET=""
            VERBOSE="-v"
            ;;
        n)
            LXCNAME=$OPTARG
            ;;
        h|\?)
            show_help
            ;;
    esac
done

shift $((OPTIND-1))

[ "$1" = "--" ] && shift

LXC_ROOT=/var/lib/lxc/$LXCNAME
LXC_ROOT_FS=/var/lib/lxc/$LXCNAME/root
LXC_ROOT_MODULES=/var/lib/lxc/$LXCNAME/.modules

get_yahm_name()
{
        if [ `check_yahm_installed` -eq 1 ] 
        then
                local installed_name=`cat ${YAHM_LIB}/container_name`
        else
                echo 0
        fi

}

check_yahm_name()
{
	if [ `check_yahm_installed` -eq 1 ] ; then
		local container_name=$1
		local installed_name=`cat ${YAHM_LIB}/container_name`

		if [ "$container_name" = "$installed_name" ] ; then
			echo 1
			return 1
		fi
	fi
	echo 0
	return 1 
}

check_yahm_installed()
{
	file="${YAHM_LIB}/is_installed"
	if [ -f "$file" ]
	then
		echo 1 
	else
		echo 0
	fi
}

get_yahm_version()
{
    local container_name=$1
    local yahm_version=`cat /var/lib/lxc/${container_name}/root/boot/VERSION  | cut -d'=' -f2` 
    echo $yahm_version
}

yahm_compatibility()
{
    local ccufw_version=$1
    if [ ! -f "${YAHM_DIR}/share/patches/${ccufw_version}.patch" ] ; then
        echo 1 
        return 1 
    fi

    if [ ! -f "${YAHM_DIR}/share/scripts/${ccufw_version}.sh" ] ; then
        echo 1 
        return 1
    fi 

    echo 0
}

ver() 
{ 
   printf "%03d%03d%03d%03d" $(echo "$1" | tr '.' ' ') 
}

countdown()
{
    secs=$((5))
    while [ $secs -gt 0 ]; do
        echo -ne "$secs\033[0K\r"
        sleep 1
        : $((secs--))
    done
}

check_install_deb()
{
    progress "Installing dependencies"
    packages=$1
    for P in $packages
    do
        dpkg -s "$P" >/dev/null 2>&1 && {
        info $P is installed
        } || {
            install_package "$P"
        }
    done
}

install_package() {
    package=$1
    info "install ${package}"
    apt-get -qq -y install $package 2>&1 > /dev/null
    return $?
}

