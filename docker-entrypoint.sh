#!/bin/sh
set -eu

HMDM_DIR=/opt/hmdm
TEMPLATE_DIR=$HMDM_DIR/templates
TOMCAT_DIR=/usr/local/tomcat
BASE_DIR=$TOMCAT_DIR/work

mkdir -p "$BASE_DIR/cache" "$BASE_DIR/files" "$BASE_DIR/plugins" "$BASE_DIR/logs" "$BASE_DIR/emails" "$TOMCAT_DIR/conf/Catalina/localhost" "$TOMCAT_DIR/ssl"

BASE_HOST=$BASE_DOMAIN
if [ -n "${BASE_PORT:-}" ]; then
    BASE_HOST="$BASE_DOMAIN:$BASE_PORT"
fi
BASE_PATH_VALUE=$BASE_PATH
if [ -n "$BASE_PATH_VALUE" ] && [ "${BASE_PATH_VALUE#\/}" = "$BASE_PATH_VALUE" ]; then
    BASE_PATH_VALUE="/$BASE_PATH_VALUE"
fi
PUBLIC_BASE_URL="$PROTOCOL://$BASE_HOST$BASE_PATH_VALUE"
DOWNLOAD_BASE_URL=https://h-mdm.com/files

HMDM_WAR=$(basename "$HMDM_URL")
if [ ! -f "$BASE_DIR/cache/$HMDM_WAR" ]; then
    if ! wget $DOWNLOAD_CREDENTIALS "$HMDM_URL" -O "$BASE_DIR/cache/$HMDM_WAR"; then
        echo "Failed to retrieve $HMDM_URL"
        exit 1
    fi
fi
cp "$BASE_DIR/cache/$HMDM_WAR" "$TOMCAT_DIR/webapps/ROOT.war"

if [ ! -f "$BASE_DIR/log4j-hmdm.xml" ] || [ "$FORCE_RECONFIGURE" = "true" ]; then
    sed "s|_BASE_DIRECTORY_|$BASE_DIR|g" "$TEMPLATE_DIR/conf/log4j_template.xml" > "$BASE_DIR/log4j-hmdm.xml"
fi

if [ ! -d "$BASE_DIR/emails/en" ] || [ "$FORCE_RECONFIGURE" = "true" ]; then
    cp -r "$TEMPLATE_DIR/emails/." "$BASE_DIR/emails/"
fi

if [ ! -f "$TOMCAT_DIR/conf/Catalina/localhost/ROOT.xml" ] || [ "$FORCE_RECONFIGURE" = "true" ]; then
    BASE_HOST=$BASE_DOMAIN
    if [ -n "${BASE_PORT:-}" ]; then
        BASE_HOST="$BASE_DOMAIN:$BASE_PORT"
    fi
    BASE_PATH_VALUE=$BASE_PATH
    if [ -n "$BASE_PATH_VALUE" ] && [ "${BASE_PATH_VALUE#\/}" = "$BASE_PATH_VALUE" ]; then
        BASE_PATH_VALUE="/$BASE_PATH_VALUE"
    fi
    sed \
        -e "s|_SQL_HOST_|$SQL_HOST|g" \
        -e "s|_SQL_PORT_|$SQL_PORT|g" \
        -e "s|_SQL_BASE_|$SQL_BASE|g" \
        -e "s|_SQL_USER_|$SQL_USER|g" \
        -e "s|_SQL_PASS_|$SQL_PASS|g" \
        -e "s|_BASE_DIRECTORY_|$BASE_DIR|g" \
        -e "s|_PROTOCOL_|$PROTOCOL|g" \
        -e "s|_BASE_HOST_|$BASE_HOST|g" \
        -e "s|_BASE_DOMAIN_|$BASE_DOMAIN|g" \
        -e "s|_BASE_PATH_|$BASE_PATH_VALUE|g" \
        -e "s|_SHARED_SECRET_|$SHARED_SECRET|g" \
        -e "s|_INSTALL_FLAG_|$BASE_DIR/hmdm_install_flag|g" \
        -e "s|_SMTP_HOST_|${SMTP_HOST:-}|g" \
        -e "s|_SMTP_PORT_|${SMTP_PORT:-}|g" \
        -e "s|_SMTP_SSL_|${SMTP_SSL:-0}|g" \
        -e "s|_SMTP_STARTTLS_|${SMTP_STARTTLS:-0}|g" \
        -e "s|_SMTP_USERNAME_|${SMTP_USERNAME:-}|g" \
        -e "s|_SMTP_PASSWORD_|${SMTP_PASSWORD:-}|g" \
        -e "s|_SMTP_FROM_|${SMTP_FROM:-}|g" \
        -e "s|_LANGUAGE_|$INSTALL_LANGUAGE|g" \
        "$TEMPLATE_DIR/conf/context_template.xml" > "$TOMCAT_DIR/conf/Catalina/localhost/ROOT.xml"
fi

CLIENT_VARIANT=${CLIENT_VARIANT:-$HMDM_VARIANT}
HMDM_APK="hmdm-$CLIENT_VERSION-$CLIENT_VARIANT.apk"

if [ ! -f "$BASE_DIR/init.sql" ] || [ "$FORCE_RECONFIGURE" = "true" ]; then
    sed \
        -e "s|_ADMIN_EMAIL_|${ADMIN_EMAIL:-}|g" \
        -e "s|_HMDM_VERSION_|$CLIENT_VERSION|g" \
        -e "s|_HMDM_APK_|$HMDM_APK|g" \
        "$TEMPLATE_DIR/sql/hmdm_init.$INSTALL_LANGUAGE.sql" > "$BASE_DIR/init.sql"
fi

sed -i "s|https://h-mdm.com/files/|$PUBLIC_BASE_URL/files/|g" "$BASE_DIR/init.sql"

FILES_TO_DOWNLOAD=$(grep -oE 'https?://[^/[:space:]'"'"'(),;]+/files/[A-Za-z0-9._-]+\.(apk|war)' "$BASE_DIR/init.sql" | sort -u)
FILES_TO_DOWNLOAD="$FILES_TO_DOWNLOAD
$PUBLIC_BASE_URL/files/$HMDM_APK"
cd "$BASE_DIR/files"
for FILE in $FILES_TO_DOWNLOAD; do
    FILENAME=$(basename "$FILE")
    if [ ! -f "$FILENAME" ]; then
        wget "$DOWNLOAD_BASE_URL/$FILENAME"
    fi
done

if [ "$PROTOCOL" = "https" ]; then
    HTTPS_CERT_PATH=${HTTPS_CERT_PATH:-/etc/letsencrypt/live/$BASE_DOMAIN}
    if [ "$HTTPS_LETSENCRYPT" = "true" ]; then
        until [ -f "$HTTPS_CERT_PATH/$HTTPS_PRIVKEY" ]; do
            echo "Waiting for TLS certificate at $HTTPS_CERT_PATH..."
            sleep 5
        done
    fi
    openssl pkcs12 -export -out "$TOMCAT_DIR/ssl/hmdm.p12" -inkey "$HTTPS_CERT_PATH/$HTTPS_PRIVKEY" -in "$HTTPS_CERT_PATH/$HTTPS_CERT" -certfile "$HTTPS_CERT_PATH/$HTTPS_FULLCHAIN" -password pass:123456
    keytool -importkeystore -destkeystore "$TOMCAT_DIR/ssl/hmdm.jks" -srckeystore "$TOMCAT_DIR/ssl/hmdm.p12" -srcstoretype PKCS12 -srcstorepass 123456 -deststorepass 123456 -noprompt
fi

until PGPASSWORD="$SQL_PASS" psql -h "$SQL_HOST" -p "$SQL_PORT" -U "$SQL_USER" -d "$SQL_BASE" -c '\q'; do
    echo "Waiting for PostgreSQL at $SQL_HOST:$SQL_PORT..."
    sleep 5
done

APPLICATIONS_TABLE_EXISTS=$(PGPASSWORD="$SQL_PASS" psql -h "$SQL_HOST" -p "$SQL_PORT" -U "$SQL_USER" -d "$SQL_BASE" -tAc "SELECT to_regclass('public.applications') IS NOT NULL" | tr -d '[:space:]')
if [ "$APPLICATIONS_TABLE_EXISTS" = "t" ]; then
    APPLICATION_COUNT=$(PGPASSWORD="$SQL_PASS" psql -h "$SQL_HOST" -p "$SQL_PORT" -U "$SQL_USER" -d "$SQL_BASE" -tAc 'SELECT count(*) FROM applications' | tr -d '[:space:]')
    if [ "$APPLICATION_COUNT" = "0" ]; then
        PGPASSWORD="$SQL_PASS" psql -v ON_ERROR_STOP=1 -h "$SQL_HOST" -p "$SQL_PORT" -U "$SQL_USER" -d "$SQL_BASE" -f "$BASE_DIR/init.sql"
    fi
fi

APPLICATION_VERSIONS_TABLE_EXISTS=$(PGPASSWORD="$SQL_PASS" psql -h "$SQL_HOST" -p "$SQL_PORT" -U "$SQL_USER" -d "$SQL_BASE" -tAc "SELECT to_regclass('public.applicationversions') IS NOT NULL" | tr -d '[:space:]')
if [ "$APPLICATION_VERSIONS_TABLE_EXISTS" = "t" ]; then
    PGPASSWORD="$SQL_PASS" psql -v ON_ERROR_STOP=1 -h "$SQL_HOST" -p "$SQL_PORT" -U "$SQL_USER" -d "$SQL_BASE" <<SQL
SET client_min_messages TO WARNING;
UPDATE applicationversions
SET url = replace(url, 'https://h-mdm.com/files/', '$PUBLIC_BASE_URL/files/')
WHERE url LIKE 'https://h-mdm.com/files/%';
UPDATE applicationversions
SET version = '$CLIENT_VERSION', url = '$PUBLIC_BASE_URL/files/$HMDM_APK'
WHERE applicationid = (SELECT id FROM applications WHERE pkg = 'com.hmdm.launcher' LIMIT 1);
SQL
fi

exec catalina.sh run
