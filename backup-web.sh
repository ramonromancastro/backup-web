#!/bin/bash

# backup-web is a bash function to simplify dump web applications.
# Copyright (C) 2017 Ramon Roman Castro <ramonromancastro@gmail.com>
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation; either version 2 of the License, or (at your
# option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

#
# CONSTANTES
#

APP_VERSION="0.7"
APP_HR="****************************************"

declare -A colors=( [disable]="\e[90m" [debug]="\e[95m" [info]="\e[97m" [ok]="\e[32m" [warning]="\e[93m" [error]="\e[91m" [normal]="\e[39m" [detail]="\e[36m")

#
# VARIABLES DEL PROGRAMA
#

APP_DATE=$(date +%Y%m%d)

APP_NAME=
APP_SOURCE_PATH=
APP_DESTINATION_PATH=/tmp
APP_CALCULATE=

APP_WEB_FILE="$APP_DATE.www.tar.gz"
APP_DB_DDL_FILE="$APP_DATE.mysql.ddl.sql"
APP_DB_DML_FILE="$APP_DATE.mysql.dml.sql"
APP_DB_DCL_FILE="$APP_DATE.mysql.dcl.sql"

APP_DBENGINE=
APP_DBNAME=
APP_DBUSER=
APP_DBPASSWORD=
APP_DBHOST=

#
# FUNCIONES INTERNAS
#

#msg() { msg_color=$1; msg_text=$2; printf "%b[ %-7s ] %s\e[0m\n" "${colors[$msg_color]}" "${msg_color^^}" "${msg_text}"; }
#msg() { msg_color=$1; msg_text=$2; printf "%b%s\e[0m\n" "${colors[$msg_color]}" "${msg_text}"; }
msg() { msg_color=$1; msg_text=$2; echo -en "${colors[$msg_color]}${msg_text}\e[0m\n"; }
cmd_exists() { cmd=$1; return `which ${cmd} >/dev/null 2>&1`; }
hr() { printf '=%.0s' {1..80}}; echo; }
version() { echo "$0 ver$APP_VERSION"; }
shortusage() {
	cat << EOF
Usage: $0 [OPTIONS]
$0 -h for more information.
EOF
}

usage(){
	cat << EOF

    $0 [OPTIONS] - Dump web application and its database information

    This script autodetect database configuration for:
      Drupal 6.x/7.x/8.x
      WordPress 3.x/4.x/5.x

   OPTIONS:
      -n NAME         Dump name. This dump name is appended to all dump files
      -s SOURCE       Web application source path
      -d DESTINATION  Destination path
      -h              This help text
      -v              Print version number
      -c              Calculate application and database size before dump

   OUTPUT:
      DESTINATION/NAME.DATE.www.tar.gz
      DESTINATION/NAME.DATE.mysql.dcl.sql
      DESTINATION/NAME.DATE.mysql.ddl.sql
      DESTINATION/NAME.DATE.mysql.dml.sql
   
   EXAMPLES:
      backup-web.sh -n wordpress -s /var/www/html/wordpress -d /tmp/dump
      backup-web.sh -h
      backup-web.sh -v

EOF
}

#
# FUNCIONES DEL PROGRAMA
#

app_checkReqs() {
	if [ ! -f /etc/init.d/functions ]; then
		msg "warning" "Archivo /etc/init.d/functions no encontrado"
		exit 1
	fi

	. /etc/init.d/functions
	cmds=(awk grep mysql mysqldump printf rsync sed tar)
	for cmd in ${cmds[@]}; do
		action "Comprobación de requisitos: $cmd" cmd_exists $cmd
	done
}

app_setVariables() {
	APP_WEB_FILE="$APP_DESTINATION_PATH/$APP_NAME.$APP_WEB_FILE"
	APP_DB_DDL_FILE="$APP_DESTINATION_PATH/$APP_NAME.$APP_DB_DDL_FILE"
	APP_DB_DML_FILE="$APP_DESTINATION_PATH/$APP_NAME.$APP_DB_DML_FILE"
	APP_DB_DCL_FILE="$APP_DESTINATION_PATH/$APP_NAME.$APP_DB_DCL_FILE"
}

app_checkMysqlAccess() {
	mysql -h$APP_DBHOST -u$APP_DBUSER -p''$APP_DBPASSWORD'' --silent --skip-column-names --execute "select * from mysql.user" > /dev/null 2>&1
	return $?
}

app_detectEngineAndDbParameters() {
	msg "info" "Recopilando información de la aplicación"
	APP_WEBENGINE=""
	# WordPress
	if $(grep -q "^\s*\$wp_version\s*=\s*'[34]" "${APP_SOURCE_PATH}/wp-includes/version.php" > /dev/null 2>&1); then
		APP_WEBENGINE="WordPress 3.x/4.x"
		if [ -f "${APP_SOURCE_PATH}/wp-config.php" ]; then
			APP_DBNAME=$(grep "^[\t ]*define.*'DB_NAME'" ${APP_SOURCE_PATH}/wp-config.php         | head -1 | awk -F ',' '{ value=gensub(/[^\047]*\047([^\047]+).*/,"\\1","g",$2); print value }')
			APP_DBUSER=$(grep "^[\t ]*define.*'DB_USER'" ${APP_SOURCE_PATH}/wp-config.php         | head -1 | awk -F ',' '{ value=gensub(/[^\047]*\047([^\047]+).*/,"\\1","g",$2); print value }')
			APP_DBPASSWORD=$(grep "^[\t ]*define.*'DB_PASSWORD'" ${APP_SOURCE_PATH}/wp-config.php | head -1 | awk -F ',' '{ value=gensub(/[^\047]*\047([^\047]+).*/,"\\1","g",$2); print value }')
			APP_DBHOST=$(grep "^[\t ]*define.*'DB_HOST'" ${APP_SOURCE_PATH}/wp-config.php         | head -1 | awk -F ',' '{ value=gensub(/[^\047]*\047([^\047]+).*/,"\\1","g",$2); print value }')
		fi
	fi

	# Drupal 6.x
	if [ -z "$APP_WEBENGINE" ]; then
		if $(grep -q "^\s*define('VERSION',\s*'6" "${APP_SOURCE_PATH}/modules/system/system.module" > /dev/null 2>&1); then
			APP_WEBENGINE="Drupal 6.x"
			if [ -f "${APP_SOURCE_PATH}/sites/default/settings.php" ]; then
				APP_DBENGINE=$(grep "^\s*\$db_url\s*=\s*'.*'" ${APP_SOURCE_PATH}/sites/default/settings.php   | head -1 | sed 's/\s*$db_url\s*=\s*'"'"'\([^:]*\):.*'"'"'.*/\1/g')
				if [[ ! $APP_DBENGINE =~ mysql ]]; then
					msg "warning" "Este script sólo soporta base de datos MySQL y la aplicación utiliza $APP_DBENGINE"
					exit 1
				fi
				APP_DBUSER=$(grep "^\s*\$db_url\s*=\s*'.*'" ${APP_SOURCE_PATH}/sites/default/settings.php     | head -1 | sed 's/\s*$db_url\s*=\s*'"'"'[^:]*:\/\/\([^:]*\):.*'"'"'.*/\1/g')
				APP_DBPASSWORD=$(grep "^\s*\$db_url\s*=\s*'.*'" ${APP_SOURCE_PATH}/sites/default/settings.php | head -1 | sed 's/\s*$db_url\s*=\s*'"'"'[^:]*:\/\/[^:]*:\([^@]*\)@.*'"'"'.*/\1/g')
				APP_DBHOST=$(grep "^\s*\$db_url\s*=\s*'.*'" ${APP_SOURCE_PATH}/sites/default/settings.php     | head -1 | sed 's/\s*$db_url\s*=\s*'"'"'[^:]*:\/\/[^:]*:[^@]*@\([^\/]*\)\/.*'"'"'.*/\1/g')
				APP_DBNAME=$(grep "^\s*\$db_url\s*=\s*'.*'" ${APP_SOURCE_PATH}/sites/default/settings.php     | head -1 | sed 's/\s*$db_url\s*=\s*'"'"'[^:]*:\/\/[^:]*:[^@]*@[^\/]*\/\(.*\)'"'"'.*/\1/g')
			fi
		fi
	fi
	
	# Drupal 7.x
	if [ -z "$APP_WEBENGINE" ]; then
		if $(grep -q "^\s*define('VERSION',\s*'7" "${APP_SOURCE_PATH}/includes/bootstrap.inc" > /dev/null 2>&1); then
			APP_WEBENGINE="Drupal 7.x"
			if [ -f "${APP_SOURCE_PATH}/sites/default/settings.php" ]; then
				APP_DBENGINE=$(grep "^\s*'driver'\s*=>\s*'.*'" ${APP_SOURCE_PATH}/sites/default/settings.php     | head -1 | awk -F '>' '{ value=gensub(/[^\047]*\047([^\047]+).*/,"\\1","g",$2); print value }')
				if [[ ! $APP_DBENGINE =~ mysql ]]; then
					msg "warning" "Este script sólo soporta base de datos MySQL y la aplicación utiliza $APP_DBENGINE"
					exit 1
				fi
				APP_DBNAME=$(grep "^\s*'database'\s*=>\s*'.*'" ${APP_SOURCE_PATH}/sites/default/settings.php     | head -1 | awk -F '>' '{ value=gensub(/[^\047]*\047([^\047]+).*/,"\\1","g",$2); print value }')
				APP_DBUSER=$(grep "^\s*'username'\s*=>\s*'.*'" ${APP_SOURCE_PATH}/sites/default/settings.php     | head -1 | awk -F '>' '{ value=gensub(/[^\047]*\047([^\047]+).*/,"\\1","g",$2); print value }')
				APP_DBPASSWORD=$(grep "^\s*'password'\s*=>\s*'.*'" ${APP_SOURCE_PATH}/sites/default/settings.php | head -1 | awk -F '>' '{ value=gensub(/[^\047]*\047([^\047]+).*/,"\\1","g",$2); print value }')
				APP_DBHOST=$(grep "^\s*'host'\s*=>\s*'.*'" ${APP_SOURCE_PATH}/sites/default/settings.php         | head -1 | awk -F '>' '{ value=gensub(/[^\047]*\047([^\047]+).*/,"\\1","g",$2); print value }')
			fi
		fi
	fi
	
	if [ -z "$APP_WEBENGINE" ]; then
		# Drupal 8.x
		if $(grep -q "^\s*const\s*VERSION\s*=\s*'8" "${APP_SOURCE_PATH}/core/lib/Drupal.php" > /dev/null 2>&1); then
			APP_WEBENGINE="Drupal 8.x"
			if [ -f "${APP_SOURCE_PATH}/sites/default/settings.php" ]; then
				APP_DBENGINE=$(grep "^\s*'driver'\s*=>\s*'.*'" ${APP_SOURCE_PATH}/sites/default/settings.php     | head -1 | awk -F '>' '{ value=gensub(/[^\047]*\047([^\047]+).*/,"\\1","g",$2); print value }')
				if [[ ! $APP_DBENGINE =~ mysql ]]; then
					msg "warning" "Este script sólo soporta base de datos MySQL y la aplicación utiliza $APP_DBENGINE"
					exit 1
				fi
				APP_DBNAME=$(grep "^\s*'database'\s*=>\s*'.*'" ${APP_SOURCE_PATH}/sites/default/settings.php     | head -1 | awk -F '>' '{ value=gensub(/[^\047]*\047([^\047]+).*/,"\\1","g",$2); print value }')
				APP_DBUSER=$(grep "^\s*'username'\s*=>\s*'.*'" ${APP_SOURCE_PATH}/sites/default/settings.php     | head -1 | awk -F '>' '{ value=gensub(/[^\047]*\047([^\047]+).*/,"\\1","g",$2); print value }')
				APP_DBPASSWORD=$(grep "^\s*'password'\s*=>\s*'.*'" ${APP_SOURCE_PATH}/sites/default/settings.php | head -1 | awk -F '>' '{ value=gensub(/[^\047]*\047([^\047]+).*/,"\\1","g",$2); print value }')
				APP_DBHOST=$(grep "^\s*'host'\s*=>\s*'.*'" ${APP_SOURCE_PATH}/sites/default/settings.php         | head -1 | awk -F '>' '{ value=gensub(/[^\047]*\047([^\047]+).*/,"\\1","g",$2); print value }')
			fi
		fi
	fi

	msg "detail" "App Engine  : ${APP_WEBENGINE:-<Unknown>}"
	msg "detail" "DB Engine   : ${APP_DBENGINE:-<Unknown>}"
	msg "detail" "DB Server   : ${APP_DBHOST:-<Unknown>}"
	msg "detail" "DB Name     : ${APP_DBNAME:-<Unknown>}"
	msg "detail" "DB User     : ${APP_DBUSER:-<Unknown>}"
	msg "detail" "DB Password : ${APP_DBPASSWORD:-<Unknown>}"
	
	if [ ! -z "$APP_DBNAME" ] && [ ! -z "$APP_DBUSER" ] && [ ! -z "$APP_DBPASSWORD" ] && [ ! -z "$APP_DBHOST" ]; then
		msg "warning" "*** El usuario detectado no tiene los privilegios necesarios para extraer la información de DCL"
		msg "warning" "    Es necesario utilizar un usuario con el privilegio SELECT sobre la tabla mysql.user"
	fi
	msg "warning" "*** Es necesario que el usuario tenga los siguientes privilegios\n    SELECT, SHOW VIEW, TRIGGER, LOCK TABLES"
	
	read -p "DB Server [$APP_DBHOST]: " input
	APP_DBHOST=${input:-$APP_DBHOST}
	read -p "DB Name [$APP_DBNAME]: " input
	APP_DBNAME=${input:-$APP_DBNAME}
	read -p "DB User [$APP_DBUSER]: " input
	APP_DBUSER=${input:-$APP_DBUSER}
	read -s -p "DB Password [$APP_DBPASSWORD]: " input
	APP_DBPASSWORD=${input:-$APP_DBPASSWORD}
	echo
}

app_detectSizes() {
	if [ ! -z "$APP_CALCULATE" ]; then
		msg "info" "Calculando el tamaño de la aplicación"
		APPSIZE=$(du --max-depth=0 -h ${APP_SOURCE_PATH}/ 2> /dev/null | awk '{ print $1 }')
		msg "detail" "App Size : ${APPSIZE:-<Unknown>}"
		DBSIZE=$(mysql -h$APP_DBHOST -u$APP_DBUSER -p''$APP_DBPASSWORD'' --silent --skip-column-names --execute "SELECT  sum(round(((data_length + index_length) / 1024 / 1024), 2)) FROM information_schema.TABLES WHERE table_schema = '$APP_DBNAME'" 2> /dev/null)
		msg "detail" "DB Size  : ${DBSIZE:-<Unknown>}M"
	fi
}

app_confirmDump() {
	read -r -p "¿Desea continuar? [S/N] " response
	case "$response" in
		[nN])
			exit 1
			;;
	esac
}

app_dumpWebApp() {
	tar -cvzh -f "$APP_WEB_FILE" "$APP_SOURCE_PATH" > /dev/null 2>&1
}

app_dumpDbDdl() {
	mysqldump --max_allowed_packet=1G --default-character-set=utf8 --add-drop-database --add-drop-table --create-options --routines --triggers --no-data --hex-blob --single-transaction -h$APP_DBHOST -u$APP_DBUSER -p''$APP_DBPASSWORD'' $APP_DBNAME > $APP_DB_DDL_FILE
}

app_dumpDbDml() {
	mysqldump --max_allowed_packet=1G --default-character-set=utf8 --complete-insert --no-create-info --no-create-db --skip-triggers --hex-blob --single-transaction -h$APP_DBHOST -u$APP_DBUSER -p''$APP_DBPASSWORD'' $APP_DBNAME > $APP_DB_DML_FILE
}

app_dumpDbDcl() {
	MYSQL_VERSION=$(mysql -h$APP_DBHOST -u$APP_DBUSER -p''$APP_DBPASSWORD'' --silent --skip-column-names --execute "select @@version")
	if [ "5.7" == "`echo -e "5.7\n$MYSQL_VERSION" | sort -V | head -n1`" ]; then
		mysql -h$APP_DBHOST -u$APP_DBUSER -p''$APP_DBPASSWORD'' --silent --skip-column-names --execute "select concat('\'',User,'\'@\'',Host,'\'') as User from mysql.user" 2> /dev/null | sort | while read u;  do mysql -h$APP_DBHOST -u$APP_DBUSER -p''$APP_DBPASSWORD'' --silent --skip-column-names --execute "show grants for $u" 2> /dev/null | sed 's/$/;/'; done | grep "ON \`$APP_DBNAME\`" | sed -e "s/^.*\sTO\s\('[^']*'@'[^']*'\).*/\1/g" | sort -u | while read v;  do mysql -h$APP_DBHOST -u$APP_DBUSER -p''$APP_DBPASSWORD'' --silent --skip-column-names --execute "SHOW CREATE USER $v"; done  > $APP_DB_DCL_FILE
		mysql -h$APP_DBHOST -u$APP_DBUSER -p''$APP_DBPASSWORD'' --silent --skip-column-names --execute "select concat('\'',User,'\'@\'',Host,'\'') as User from mysql.user" 2> /dev/null | sort | while read u;  do mysql -h$APP_DBHOST -u$APP_DBUSER -p''$APP_DBPASSWORD'' --silent --skip-column-names --execute "show grants for $u" 2> /dev/null | sed 's/$/;/'; done | grep "ON \`$APP_DBNAME\`" >> $APP_DB_DCL_FILE
	else
		mysql -h$APP_DBHOST -u$APP_DBUSER -p''$APP_DBPASSWORD'' --silent --skip-column-names --execute "select concat('\'',User,'\'@\'',Host,'\'') as User from mysql.user" 2> /dev/null | sort | while read u;  do mysql -h$APP_DBHOST -u$APP_DBUSER -p''$APP_DBPASSWORD'' --silent --skip-column-names --execute "show grants for $u" 2> /dev/null | sed 's/$/;/'; done | grep "ON \`$APP_DBNAME\`" > $APP_DB_DCL_FILE
	fi
}

#
# CUERPO PRINCIPAL
#

if [[ $# -eq 0  ]]; then
	shortusage
	exit 1
fi

while getopts "n:s:d:hvc" opt; do
	case "$opt" in
		n)
			APP_NAME=${OPTARG}
			;;
		s)
			APP_SOURCE_PATH=${OPTARG%/}
			;;
		d)
			APP_DESTINATION_PATH=${OPTARG%/}
			;;
		c)
			APP_CALCULATE=1
			;;
		h)
			usage
			exit 1
			;;
		v)
			version
			exit 1
			;;
	esac
done

if [ -z "$APP_NAME" ] || [ -z "$APP_SOURCE_PATH" ] || [ -z "$APP_DESTINATION_PATH" ]; then
	msg "warning" "No se han espefificado los parámetros -n, -s, -d"
	shortusage
	exit 1
fi

if [ ! -d "$APP_SOURCE_PATH" ]; then
	msg "warning" "Directorio origen $APP_SOURCE_PATH no encontrado"
	exit 1
fi

if [ ! -d "$APP_DESTINATION_PATH" ]; then
	msg "warning" "Directorio destino $APP_DESTINATION_PATH no encontrado"
	exit 1
fi

app_checkReqs
app_setVariables
app_detectEngineAndDbParameters
app_detectSizes
app_confirmDump

action "Volcado de la aplicación Web" app_dumpWebApp
action "Volcado de la base de datos (Data Definition Language)" app_dumpDbDdl
action "Volcado de la base de datos (Data Manipulation Language)" app_dumpDbDml
action "Volcado de la base de datos (Data Control Language)" app_dumpDbDcl
