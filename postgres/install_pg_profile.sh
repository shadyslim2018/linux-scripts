#!/usr/bin/env bash

#
# Program: Download, build and install pg_profile extension for PostgreSQL <install_pg_profile.sh>
#
# Author: Mikhail Grigorev <sleuthhound at gmail dot com>
# 
# Current Version: 1.0.1
#
# License:
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
    DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
SCRIPT_NAME=$(basename $0)

# Settings
ENABLE_DEBUG=0
PG_STAT_KCACHE_GIT_VER=REL2_2_1
PG_PROFILE_GIT_VER=4.1
PG_CONGIG_PATH=""

_command_exists() {
	type "$1" &> /dev/null
}

_usage() {
	echo ""
	echo "Usage: $0 [ -v pgsql_version -d (0|1) ]"
	echo ""
	echo "  -v pgsql_vestion	: (Required) PostgreSQL version"
	echo ""
	echo "  -d 0|1		: (Optional) Enable verbose output"
	echo ""
	echo "  -h			: Print this screen"
	echo ""
	exit 1
}

[ $# -eq 0 ] && _usage

while getopts ":hd:v:" option; do
	case "${option}" in
		v)
			PG_VER=${OPTARG}
			;;
		d)
			ENABLE_DEBUG=${OPTARG}
			;;
		h | *)
			_usage
			;;
	esac
done

if [ -z "${PG_VER}" ]; then
     echo "No options -r <pgsql_vestion> found!"
     _usage
fi

RED='\e[1;31m'
GREEN='\e[1;32m'
BLUE='\e[1;34m'
CYAN='\e[1;36m'
NC='\e[0m'

if _command_exists git; then
	GIT_BIN=$(which git)
else
	echo -e "${RED}ERROR: Command 'git' not found.${NC}"
	exit 1
fi

if _command_exists make; then
	MAKE_BIN=$(which make)
else
	echo -e "${RED}ERROR: Command 'make' not found.${NC}"
	exit 1
fi

if _command_exists gcc; then
	GCC_BIN=$(which gcc)
else
	echo -e "${RED}ERROR: Command 'gcc' not found.${NC}"
	exit 1
fi

if [ -f "${SCRIPT_DIR}/${SCRIPT_NAME%.*}.conf" ]; then
	source "${SCRIPT_DIR}/${SCRIPT_NAME%.*}.conf"
fi

_unknown_os() {
	echo
	echo "Unfortunately, your operating system distribution and version are not supported by this script."
	echo
	echo "Please email sleuthhound@gmail.com and let us know if you run into any issues."
	exit 1
}

_unknown_distrib() {
	echo
	echo "Unfortunately, your Linux distribution or distribution version are not supported by this script."
	echo
	echo "Please email sleuthhound@gmail.com and let us know if you run into any issues."
	exit 1
}

_detect_linux_distrib() {
	local DIST=$1
	local REV=$2
	local PSUEDONAME=$3
	echo -en "${CYAN}Detecting your Linux distrib... ${NC}"
	case "${DIST}" in
		Ubuntu)
			OS_DISTRIB="Debian"
			echo -en "${GREEN}${DIST} ${REV}"
			case "${REV}" in
			14.04|16.04|18.04|20.04|22.04)
				echo -e " (${PSUEDONAME})${NC}"
				;;
			*)
				_unknown_distrib
				;;
			esac
			;;
		Debian)
			OS_DISTRIB="Debian"
			echo -en "${GREEN}${DIST} ${REV}"
			case "${REV}" in
			8|9|10|11)
				echo -e " (${PSUEDONAME})${NC}"
				;;
			*)
				_unknown_distrib
				;;
			esac
			;;
		"Red Hat"*|"RedHat"*)
			OS_DISTRIB="RedHat"
			echo -e "${GREEN}${DIST} ${REV} (${PSUEDONAME})${NC}"
			;;
		CentOS|"CentOS Linux"|"Rocky Linux")
			OS_DISTRIB="RedHat"
			echo -e "${GREEN}${DIST} ${REV} (${PSUEDONAME})${NC}"
			;;
		*)
			OS_DISTRIB=""
			echo -e "${RED}Unsupported (${DIST} | ${REV} | ${PSUEDONAME})${NC}"
			_unknown_distrib
			;;
	esac
}

OS=$(uname -s)
OS_ARCH=$(uname -m)
echo -en "${CYAN}Detecting your OS... ${NC}"
case "${OS}" in
	Linux*)
		echo -e "${GREEN}Linux (${OS_ARCH})${NC}"
		PLATFORM="linux"
		DISTROBASEDON="Unknown"
		DIST="Unknown"
		PSUEDONAME="Unknown"
		REV="Unknown"
		if [ -f "/etc/redhat-release" ]; then
			DISTROBASEDON="RedHat"
			DIST=$(cat /etc/redhat-release | sed s/\ release.*//)
			PSUEDONAME=$(cat /etc/redhat-release | sed s/.*\(// | sed s/\)//)
			REV=$(cat /etc/redhat-release | sed s/.*release\ // | sed s/\ .*//)
		elif [ -f "/etc/SuSE-release" ]; then
			DISTROBASEDON="SUSE"
			DIST="SuSE"
			PSUEDONAME=$(cat /etc/SuSE-release | tr "\n" ' '| sed s/VERSION.*//)
			REV=$(cat /etc/SuSE-release | tr "\n" ' ' | sed s/.*=\ //)
		elif [ -f "/etc/mandrake-release" ]; then
			DISTROBASEDON="Mandrake"
			DIST="Mandrake"
			PSUEDONAME=$(cat /etc/mandrake-release | sed s/.*\(// | sed s/\)//)
			REV=$(cat /etc/mandrake-release | sed s/.*release\ // | sed s/\ .*//)
		elif [ -f "/etc/debian_version" ]; then
			if [ -f "/etc/lsb-release" ]; then
				DISTROBASEDON="Debian"
				DIST=$(cat /etc/lsb-release | grep '^DISTRIB_ID' | awk -F=  '{ print $2 }')
				PSUEDONAME=$(cat /etc/lsb-release | grep '^DISTRIB_CODENAME' | awk -F=  '{ print $2 }')
				REV=$(cat /etc/lsb-release | grep '^DISTRIB_RELEASE' | awk -F=  '{ print $2 }')
			elif [ -f "/etc/os-release" ]; then
				DISTROBASEDON="Debian"
				DIST=$(cat /etc/os-release | grep '^NAME' | awk -F=  '{ print $2 }' | grep -oP '(?<=\")(\w+)(?=\ )')
				PSUEDONAME=$(cat /etc/os-release | grep '^VERSION=' | awk -F= '{ print $2 }' | grep -oP '(?<=\()(\w+)(?=\))')
				REV=$(sed 's/\..*//' /etc/debian_version)
			fi
		fi
		_detect_linux_distrib "${DIST}" "${REV}" "${PSUEDONAME}"
		;;
	*)
		echo -e "${RED}Unknown${NC}"
		_unknown_os
		;;
esac

echo -en "${CYAN}Checking your privileges... ${NC}"
CURRENT_USER=$(whoami)
if [[ "${CURRENT_USER}" = "root" ]]; then
	echo -e "${GREEN}OK${NC}"
else
	echo -e "${RED}ERROR: root access is required${NC}"
	exit 1
fi

if [[ "${OS_DISTRIB}" = "RedHat" ]]; then
	echo -en "${CYAN}Checking 'postgresql${PG_VER}-devel' packages... ${NC}"
	DEV_PKG_CNT=$(rpm -qa 2>/dev/null | grep -ic "postgresql${PG_VER}-devel")
	PG_BIN_PATH=/usr/pgsql-${PG_VER}/bin
else
	echo -en "${CYAN}Checking 'postgresql-server-dev-${PG_VER}' packages... ${NC}"
	DEV_PKG_CNT=$(dpkg -l 2>/dev/null | grep -c postgresql-server-dev-${PG_VER})
	PG_BIN_PATH=/usr/lib/postgresql/${PG_VER}/bin
fi
if [[ ${DEV_PKG_CNT} -ne 0 ]]; then
	echo -e "${GREEN}OK${NC}"
else
	echo -e "${RED}NOTFOUND${NC}"
	echo -e "${RED}Please, install developer packages for PostgreSQL v${PG_VER}${NC}"
	if [[ "${OS_DISTRIB}" = "RedHat" ]]; then
		echo -e "${GREEN}Note (run command): yum install -y postgresql${PG_VER}-devel${NC}"
	else
		echo -e "${GREEN}Note (run command): apt-get install -y postgresql-server-dev-${PG_VER}${NC}"
	fi
	exit 1
fi

if [ ! -f "${PG_BIN_PATH}/pg_config" ]; then
	echo -e "${RED}ERROR: File '${PG_BIN_PATH}/pg_config' not found.${NC}"
	exit 1
fi

_delete_git() {
	rm -rf "${SCRIPT_DIR}/pg_profile" >/dev/null 2>&1
	rm -rf "${SCRIPT_DIR}/pg_stat_kcache" >/dev/null 2>&1
}

_git_clone() {
	local REPO=$1
	_delete_git
	echo -en "${CYAN}Git clone '${REPO}'...${NC} "
	if [ "${ENABLE_DEBUG}" -eq 1 ]; then
		${GIT_BIN} clone "${REPO}"
	else
		${GIT_BIN} clone "${REPO}" >/dev/null 2>&1
	fi
	if [ $? -eq 0 ]; then
		echo -e "${GREEN}OK${NC}"
		return $?
	else
		echo -e "${RED}ERR${NC}"
		echo -e "${RED}ERROR: Cloning repo '${REPO}' not complete.${NC}"
		exit 1
	fi
}

cd "${SCRIPT_DIR}"
_git_clone "https://github.com/powa-team/pg_stat_kcache.git"
if [ -d "${SCRIPT_DIR}/pg_stat_kcache" ]; then
	cd "${SCRIPT_DIR}/pg_stat_kcache" >/dev/null 2>&1
	echo -en "${CYAN}Git checkout pg_stat_kcache module 'tags/${PG_STAT_KCACHE_GIT_VER}'...${NC} "
	${GIT_BIN} checkout tags/${PG_STAT_KCACHE_GIT_VER} >/dev/null 2>&1
fi
if [ $? -eq 0 ]; then
	if [ -d "${SCRIPT_DIR}/pg_stat_kcache" ]; then
		echo -e "${GREEN}OK${NC}"
		echo -en "${CYAN}Build pg_stat_kcache module...${NC} "
		cd "${SCRIPT_DIR}/pg_stat_kcache"
		if [ "${ENABLE_DEBUG}" -eq 1 ]; then
			${MAKE_BIN} USE_PGXS=1 PG_CONFIG=${PG_BIN_PATH}/pg_config install
		else
			${MAKE_BIN} USE_PGXS=1 PG_CONFIG=${PG_BIN_PATH}/pg_config install >/dev/null 2>&1
		fi
		if [ $? -eq 0 ]; then
			echo -e "${GREEN}OK${NC}"
		else
			echo -e "${RED}ERR${NC}"
			cd "${SCRIPT_DIR}"
			_delete_git
			exit 1
		fi
		cd "${SCRIPT_DIR}"
		_delete_git
	else
		echo -e "${RED}ERR${NC}"
		echo -e "${RED}ERROR: Directory '${SCRIPT_DIR}/pg_stat_kcache' not found.${NC}"
		exit 1
	fi
else
	echo -e "${RED}ERR${NC}"
	echo -e "${RED}ERROR: Checkout repo 'https://github.com/powa-team/pg_stat_kcache', tags 'tags/${PG_STAT_KCACHE_GIT_VER}' not complete.${NC}"
	exit 1
fi

cd "${SCRIPT_DIR}"
_git_clone "https://github.com/zubkov-andrei/pg_profile"
if [ -d "${SCRIPT_DIR}/pg_profile" ]; then
	cd "${SCRIPT_DIR}/pg_profile" >/dev/null 2>&1
	echo -en "${CYAN}Git checkout pg_profile module 'tags/${PG_PROFILE_GIT_VER}'...${NC} "
	${GIT_BIN} checkout tags/${PG_PROFILE_GIT_VER} >/dev/null 2>&1
fi
if [ $? -eq 0 ]; then
	if [ -d "${SCRIPT_DIR}/pg_profile" ]; then
		echo -e "${GREEN}OK${NC}"
		echo -en "${CYAN}Build pg_profile module...${NC} "
		cd "${SCRIPT_DIR}/pg_profile"
		if [ "${ENABLE_DEBUG}" -eq 1 ]; then
			${MAKE_BIN} USE_PGXS=1 PG_CONFIG=${PG_BIN_PATH}/pg_config install
		else
			${MAKE_BIN} USE_PGXS=1 PG_CONFIG=${PG_BIN_PATH}/pg_config install >/dev/null 2>&1
		fi
		if [ $? -eq 0 ]; then
			echo -e "${GREEN}OK${NC}"
			echo -e "${GREEN}Please, add module pg_stat_kcache in shared_preload_libraries in postgresql.conf file after pg_stat_statements and restart you PostgreSQL.${NC}"
			echo -e "${GREEN}After restart PostgreSQL execute command for enabling pg_profile module:${NC}"
			echo -e "${CYAN}psql -U postgres -d postgres -c 'ALTER SYSTEM SET track_activities = ON;'${NC}"
			echo -e "${CYAN}psql -U postgres -d postgres -c 'ALTER SYSTEM SET track_counts = ON;'${NC}"
			echo -e "${CYAN}psql -U postgres -d postgres -c 'ALTER SYSTEM SET track_io_timing = ON;'${NC}"
			echo -e "${CYAN}psql -U postgres -d postgres -c 'ALTER SYSTEM SET track_functions = \"all\";'${NC}"
			echo -e "${CYAN}psql -U postgres -d postgres -c 'SELECT pg_reload_conf();'${NC}"
			echo -e "${CYAN}psql -U postgres -d postgres -c 'CREATE DATABASE pg_profile;'${NC}"
			echo -e "${CYAN}psql -U postgres -d pg_profile -c 'CREATE SCHEMA profile;'${NC}"
			echo -e "${CYAN}psql -U postgres -d pg_profile -c 'CREATE EXTENSION dblink SCHEMA profile;'${NC}"
			echo -e "${CYAN}psql -U postgres -d pg_profile -c 'CREATE EXTENSION pg_stat_statements SCHEMA profile;'${NC}"
			echo -e "${CYAN}psql -U postgres -d pg_profile -c 'CREATE EXTENSION pg_stat_kcache SCHEMA profile;'${NC}"
			echo -e "${CYAN}psql -U postgres -d pg_profile -c 'CREATE EXTENSION pg_profile SCHEMA profile;'${NC}"
			echo -e "${GREEN}After enabling pg_profile module add in your crontab:${NC}"
			echo -e "${CYAN}*/30 * * * * ${PG_BIN_PATH}/psql -qAtX -U postgres -d pg_profile -c 'SELECT profile.take_sample()' > /dev/null 2>&1${NC}"
			echo -e "${GREEN}For view sample execute:${NC}"
			echo -e "${CYAN}${PG_BIN_PATH}/psql -qX -U postgres -d pg_profile -c 'SELECT profile.show_samples()'${NC}"
			echo -e "${GREEN}For create report execute:${NC}"
			echo -e "${CYAN}${PG_BIN_PATH}/psql -qAtX -U postgres -d pg_profile -c  'SELECT profile.get_report(1, 11)' > report_1_11.html${NC}"
			echo -e "${GREEN}Goodbye ;)${NC}"
		else
			echo -e "${RED}ERR${NC}"
			cd "${SCRIPT_DIR}"
			_delete_git
			exit 1
		fi
		cd "${SCRIPT_DIR}"
		_delete_git
	else
		echo -e "${RED}ERR${NC}"
		echo -e "${RED}ERROR: Directory '${SCRIPT_DIR}/pg_profile' not found.${NC}"
		exit 1
	fi
else
	echo -e "${RED}ERR${NC}"
	echo -e "${RED}ERROR: Checkout repo 'https://github.com/zubkov-andrei/pg_profile', 'tags/${PG_PROFILE_GIT_VER}' not complete.${NC}"
	exit 1
fi
