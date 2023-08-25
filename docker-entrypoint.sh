#!/bin/bash
set -ef -o pipefail

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

GEONETWORK_DB_TYPE=$(echo $GEONETWORK_DB_TYPE | tr [:upper:] [:lower:])

# Database
if [[ $GEONETWORK_DB_TYPE != "h2" ]]; then
    # disable H2
    sed -i -r 's/^\s*<import.*h2.*\/>$/<!--&-->/g' webapps/geonetwork/WEB-INF/config-node/srv.xml 
    
    if [[ $GEONETWORK_DB_TYPE == "postgis" ]]; then
        GEONETWORK_DB_TYPE="postgres-${GEONETWORK_DB_TYPE}"
    fi

    if [[ -r "./webapps/geonetwork/WEB-INF/config-db/${GEONETWORK_DB_TYPE}.xml" ]]; then
        sed -i -r "s/<\/beans>$/  <import resource=\"..\/config-db\/${GEONETWORK_DB_TYPE}.xml\" \/>\n<\/beans>/g" webapps/geonetwork/WEB-INF/config-node/srv.xml

        if [[ -n $GEONETWORK_DB_HOST ]]; then
            sed -i -r "s/jdbc.host=.*$/jdbc.host=${GEONETWORK_DB_HOST}/g" webapps/geonetwork/WEB-INF/config-db/jdbc.properties
        fi

        if [[ -n $GEONETWORK_DB_PORT ]]; then
            sed -i -r "s/jdbc.port=.*$/jdbc.port=${GEONETWORK_DB_PORT}/g" webapps/geonetwork/WEB-INF/config-db/jdbc.properties
        fi

        if [[ -n $GEONETWORK_DB_DATABASE ]]; then
            sed -i -r "s/jdbc.database=.*$/jdbc.database=${GEONETWORK_DB_DATABASE}/g" webapps/geonetwork/WEB-INF/config-db/jdbc.properties
        fi

        if [[ -n $GEONETWORK_DB_USERNAME ]]; then
            sed -i -r "s/jdbc.username=.*$/jdbc.username=${GEONETWORK_DB_USERNAME}/g" webapps/geonetwork/WEB-INF/config-db/jdbc.properties
        fi

        if [[ -n $GEONETWORK_DB_PASSWORD ]]; then
            sed -i -r "s/jdbc.password=.*$/jdbc.password=${GEONETWORK_DB_PASSWORD}/g" webapps/geonetwork/WEB-INF/config-db/jdbc.properties
        fi 
    else
        echo "GEONETWORK_DB_TYPE incorrect: ${GEONETWORK_DB_TYPE}"
        echo "Possible values: h2, postgres, postgis"
        exit 1
    fi   
fi

export CATALINA_OPTS

exec $@
