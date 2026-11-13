# https://geonetwork-opensource.org/manuals/3.10.x/en/install-guide/installing-from-source-code.html
ARG MAVEN_IMAGE_TAG=3.8-eclipse-temurin-8
ARG TOMCAT_IMAGE_TAG=8.5-jre8-temurin-jammy
# Global, so both stages share the default (the release stage uses it in the version label)
ARG GEONETWORK_VERSION=3.10.2

FROM docker.io/library/maven:${MAVEN_IMAGE_TAG} AS builder

ARG GEONETWORK_GIT_URL=https://github.com/geonetwork/core-geonetwork.git
ARG GEONETWORK_VERSION
ARG MAVEN_OPTS="-Xmx512M"

ENV MAVEN_OPTS=${MAVEN_OPTS}

WORKDIR /root

# Shallow clone of the release tag and its submodules
RUN git clone --depth 1 --branch ${GEONETWORK_VERSION} \
        --recurse-submodules --shallow-submodules \
        ${GEONETWORK_GIT_URL} geonetwork

WORKDIR /root/geonetwork

# Fail the build when any command in a pipeline fails (mvn | tee)
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Mods and builds
# Change obsolete PostgreSQL JDBC and old repos
# Force log4j to 2.17.1 
# - https://security.snyk.io/vuln/SNYK-JAVA-ORGAPACHELOGGINGLOG4J-2314720
# - https://snyk.io/blog/log4shell-remediation-cheat-sheet/
# Maven repository kept in a BuildKit cache mount, reused across builds
RUN --mount=type=cache,target=/root/.m2,sharing=locked \
    sed -i 's/<pg\.version>[^<]*</<pg.version>42.2.18</g' pom.xml && \
    sed -i 's/http:\/\/download.osgeo.org\/webdav\/geotools\//https:\/\/repo.osgeo.org\/repository\/release/g' pom.xml && \
    sed -i 's/https:\/\/packages.georchestra.org\/artifactory\/mapfish-print/https:\/\/artifactory.georchestra.org\/artifactory\/geonetwork-github-cache/g' pom.xml && \
    sed -i 's/<log4j2\.version>[^<]*</<log4j2\.version>2.17.1</g' pom.xml && \
    mvn clean install -DskipTests | tee install.log

SHELL ["/bin/sh", "-c"]


FROM docker.io/library/tomcat:${TOMCAT_IMAGE_TAG} AS release

ARG GEONETWORK_VERSION
ARG GEONETWORK_DATA_DIR=/srv/geonetwork/data

LABEL org.opencontainers.image.title="Geonetwork SGB/CPRM"
LABEL org.opencontainers.image.description="Geonetwork customizado pelo SGB/CPRM"
LABEL org.opencontainers.image.vendor="SGB/CPRM"
LABEL org.opencontainers.image.version=$GEONETWORK_VERSION
# Overrides the "ubuntu" value inherited from the base image (labels cannot be removed)
LABEL org.opencontainers.image.ref.name=$GEONETWORK_VERSION
LABEL org.opencontainers.image.source=https://github.com/nds-cprm/geonetwork-oci
LABEL org.opencontainers.image.authors="Carlos Eduardo Mota <carlos.mota@sgb.gov.br>"

# UMASK: read by catalina.sh (Tomcat default 0027). 0007 makes files created at runtime (H2 db,
# index, data dir) writable by group 0, so any UID in group 0 can reuse the same volume (OpenShift)
ENV JAVA_OPTS="-server -Djava.awt.headless=true -Xms2048m -Xmx2048m -XX:NewRatio=2 -XX:SurvivorRatio=10" \
    UMASK="0007" \
    GEONETWORK_DB_TYPE="h2" \
    GEONETWORK_DATA_DIR=${GEONETWORK_DATA_DIR}

# Copy built
COPY --from=builder /root/geonetwork/web/target/geonetwork/ ./webapps/geonetwork/

# Build log, kept outside the webapp so Tomcat does not serve it
COPY --from=builder /root/geonetwork/install.log /install.log

# Entrypoint
COPY docker-entrypoint.sh /

# Database configured only through environment variables, resolved by Spring at startup, so
# the webapp is never edited at runtime (read-only rootfs, restarts, any password characters):
# - srv.xml imports config-db/${GEONETWORK_DB_TYPE}.xml (postgis.xml aliases postgres-postgis.xml)
# - jdbc.properties reads GEONETWORK_DB_*; the default database is the h2 file in the data dir
# The build fails if the files do not have the expected layout
RUN W=./webapps/geonetwork/WEB-INF && \
    sed -i -E 's|^\s*<import resource="\.\./config-db/h2\.xml"/>|  <import resource="../config-db/${GEONETWORK_DB_TYPE:h2}.xml"/>|' $W/config-node/srv.xml && \
    grep -q 'config-db/${GEONETWORK_DB_TYPE:h2}.xml' $W/config-node/srv.xml && \
    printf '%s\n' \
        '<?xml version="1.0" encoding="UTF-8"?>' \
        '<beans xmlns="http://www.springframework.org/schema/beans"' \
        '       xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"' \
        '       xsi:schemaLocation="http://www.springframework.org/schema/beans http://www.springframework.org/schema/beans/spring-beans.xsd">' \
        '  <import resource="postgres-postgis.xml"/>' \
        '</beans>' > $W/config-db/postgis.xml && \
    sed -i -E \
        -e 's|^jdbc\.host=.*|jdbc.host=${GEONETWORK_DB_HOST:localhost}|' \
        -e 's|^jdbc\.port=.*|jdbc.port=${GEONETWORK_DB_PORT:5432}|' \
        -e "s|^jdbc\.database=.*|jdbc.database=\${GEONETWORK_DB_DATABASE:\${GEONETWORK_DATA_DIR:${GEONETWORK_DATA_DIR}}/h2/gn}|" \
        -e 's|^jdbc\.username=.*|jdbc.username=${GEONETWORK_DB_USERNAME:www-data}|' \
        -e 's|^jdbc\.password=.*|jdbc.password=${GEONETWORK_DB_PASSWORD:www-data}|' \
        $W/config-db/jdbc.properties && \
    [ "$(grep -c -E '^jdbc\.(host|port|database|username|password)=\$\{GEONETWORK_' $W/config-db/jdbc.properties)" -eq 5 ]

# Enable Rootless: directories written at runtime are writable by group 0 (OpenShift)
# schemaplugin-uri-catalog.xml and images/harvesting are copied into the data dir at startup
# and the copies keep the source mode, so they need g=u too (volume reused by another UID)
# TODO: add lucene mount point
RUN mkdir -p ${GEONETWORK_DATA_DIR} ./conf/Catalina/localhost && \
    chmod -R g=u \
        ./conf/Catalina/ \
        ./webapps/geonetwork/WEB-INF/data/ \
        ./webapps/geonetwork/WEB-INF/schemaplugin-uri-catalog.xml \
        ./webapps/geonetwork/images/harvesting/ \
        ${GEONETWORK_DATA_DIR} && \
    chmod +x /docker-entrypoint.sh

# Send all logs to stdout instead of files under logs/
# - Tomcat JULI: console handler only
# - Access log: written to the process stdout
# - Geonetwork log4j: every logger also gets consoleAppender; fileAppender is kept (the admin
#   console reads it) but writes a small rolling file under /tmp
RUN sed -i -r \
        -e 's/^handlers = .*/handlers = java.util.logging.ConsoleHandler/' \
        -e 's/^\.handlers = .*/.handlers = java.util.logging.ConsoleHandler/' \
        -e 's/^(org\.apache\.catalina\.core\.ContainerBase\..*\.handlers) = .*/\1 = java.util.logging.ConsoleHandler/' \
        ./conf/logging.properties && \
    sed -i -r \
        -e 's/(AccessLogValve" )directory="logs"/\1directory="\/proc\/self\/fd"/' \
        -e 's/prefix="localhost_access_log" suffix=".txt"/prefix="1" suffix="" rotatable="false" buffered="false"/' \
        ./conf/server.xml && \
    for f in ./webapps/geonetwork/WEB-INF/classes/log4j*.xml; do \
        sed 's|<param name="File" value="${log_dir}logs/geonetwork.log"/>|<param name="File" value="/tmp/geonetwork.log"/>\n    <param name="MaxFileSize" value="10MB"/>\n    <param name="MaxBackupIndex" value="1"/>|' "$f" | \
            awk '/<appender-ref ref="fileAppender"\/>/ && prev !~ /<appender-ref ref="consoleAppender"\/>/ { l = $0; sub(/fileAppender/, "consoleAppender", l); print l } { prev = $0; print }' > "$f.tmp" && \
        mv "$f.tmp" "$f"; \
    done

# Restrict the built-in health checks to the Monitor role. Spring Security applies the first
# matching rule, and the generic "/[a-zA-Z0-9_\-]+" permitAll rule shadowed "/\w*healthcheck",
# so the rule is moved above it. The build fails if the file layout changes
RUN f=./webapps/geonetwork/WEB-INF/config-security/config-security-mapping.xml && \
    sed -i -E \
        -e '/<sec:intercept-url pattern="\/\\w\*healthcheck"/,/\/>/d' \
        -e "0,/<sec:intercept-url pattern=\"\/\[a-zA-Z0-9_\\\\-\]\+\" access=\"permitAll\"\/>/s//<sec:intercept-url pattern=\"\/\\\\w*healthcheck\" access=\"hasRole('Monitor')\"\/>\n        &/" \
        "$f" && \
    grep -n -m1 -E 'healthcheck|pattern="/\[a-zA-Z0-9_\\-\]\+"' "$f" | grep -q healthcheck && \
    [ "$(grep -c healthcheck "$f")" -eq 1 ]

# nss_wrapper: passwd/group entries for UIDs absent from /etc/passwd (OpenShift arbitrary UID)
RUN apt-get update && \
    apt-get install -y --no-install-recommends libnss-wrapper && \
    rm -rf /var/lib/apt/lists/*

USER 1000:0

# Anonymous API call backed by the database settings. The built-in /criticalhealthcheck
# is not used: its Lucene check fails while the catalog is empty
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD curl -fsS -o /dev/null -H "Accept: application/json" http://localhost:8080/geonetwork/srv/api/0.1/site || exit 1

ENTRYPOINT ["/docker-entrypoint.sh"]

CMD ["catalina.sh", "run"]
