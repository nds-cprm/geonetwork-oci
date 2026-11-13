#!/bin/bash
set -ef -o pipefail

# User: register the running UID through nss_wrapper when it has no passwd entry
if ! getent passwd "$(id -u)" > /dev/null; then
    export HOME=/tmp
    NSS_WRAPPER_DIR=$(mktemp -d)
    export NSS_WRAPPER_PASSWD="${NSS_WRAPPER_DIR}/passwd"
    export NSS_WRAPPER_GROUP="${NSS_WRAPPER_DIR}/group"

    cp /etc/passwd "${NSS_WRAPPER_PASSWD}"
    cp /etc/group "${NSS_WRAPPER_GROUP}"
    echo "geonetwork:x:$(id -u):$(id -g):Geonetwork:${HOME}:/sbin/nologin" >> "${NSS_WRAPPER_PASSWD}"

    if ! getent group "$(id -g)" > /dev/null; then
        echo "geonetwork:x:$(id -g):" >> "${NSS_WRAPPER_GROUP}"
    fi

    export LD_PRELOAD=libnss_wrapper.so
fi

# Filesystem
if [[ -d ${GEONETWORK_DATA_DIR} ]]; then
    if [[ ! -r ${GEONETWORK_DATA_DIR} || ! -w ${GEONETWORK_DATA_DIR} ]]; then
        echo "Data Directory not acessible by Geonetwork: ${GEONETWORK_DATA_DIR}"
        exit 1
    fi

    CATALINA_OPTS="${CATALINA_OPTS} -Dgeonetwork.dir=${GEONETWORK_DATA_DIR}"
fi

if [[ -d ${GEONETWORK_LUCENE_DIR} ]]; then
    if [[ ! -r ${GEONETWORK_LUCENE_DIR} || ! -w ${GEONETWORK_LUCENE_DIR} ]]; then
        echo "Lucene Directory not acessible by Geonetwork: ${GEONETWORK_LUCENE_DIR}"
        exit 1
    fi

    CATALINA_OPTS="${CATALINA_OPTS} -Dgeonetwork.lucene.dir=${GEONETWORK_LUCENE_DIR}"
fi

# Database: nothing is written here. srv.xml and jdbc.properties read GEONETWORK_DB_* through
# Spring placeholders (see the Dockerfile); this block only validates and normalizes them
GEONETWORK_DB_TYPE="${GEONETWORK_DB_TYPE:-h2}"
GEONETWORK_DB_TYPE="${GEONETWORK_DB_TYPE,,}"

case "${GEONETWORK_DB_TYPE}" in
    h2)
        # The h2 file and its credentials come from jdbc.properties defaults
        unset GEONETWORK_DB_HOST GEONETWORK_DB_PORT GEONETWORK_DB_DATABASE \
              GEONETWORK_DB_USERNAME GEONETWORK_DB_PASSWORD GEONETWORK_DB_PASSWORD_FILE
        ;;
    postgres|postgis)
        # Password from a mounted secret file, if given
        if [[ -n ${GEONETWORK_DB_PASSWORD_FILE} ]]; then
            if [[ ! -r ${GEONETWORK_DB_PASSWORD_FILE} ]]; then
                echo "GEONETWORK_DB_PASSWORD_FILE not readable: ${GEONETWORK_DB_PASSWORD_FILE}"
                exit 1
            fi
            GEONETWORK_DB_PASSWORD="$(< "${GEONETWORK_DB_PASSWORD_FILE}")"
            export GEONETWORK_DB_PASSWORD
            unset GEONETWORK_DB_PASSWORD_FILE
        fi

        if [[ -z ${GEONETWORK_DB_DATABASE} ]]; then
            echo "GEONETWORK_DB_DATABASE is required when GEONETWORK_DB_TYPE=${GEONETWORK_DB_TYPE}"
            exit 1
        fi
        ;;
    *)
        echo "GEONETWORK_DB_TYPE incorrect: ${GEONETWORK_DB_TYPE}"
        echo "Possible values: h2, postgres, postgis"
        exit 1
        ;;
esac

export GEONETWORK_DB_TYPE CATALINA_OPTS

exec "$@"