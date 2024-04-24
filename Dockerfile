# https://geonetwork-opensource.org/manuals/3.10.x/en/install-guide/installing-from-source-code.html
ARG MAVEN_IMAGE_TAG=3.8-eclipse-temurin-8
ARG TOMCAT_IMAGE_TAG=8.5-jre8-temurin-jammy

FROM docker.io/library/maven:${MAVEN_IMAGE_TAG} AS BUILDER

ARG GEONETWORK_GIT_URL=https://github.com/geonetwork/core-geonetwork.git
ARG GEONETWORK_VERSION=3.10.2
ARG MAVEN_OPTS="-Xmx512M"

ENV MAVEN_OPTS ${MAVEN_OPTS}

WORKDIR /root

RUN git clone ${GEONETWORK_GIT_URL} geonetwork

WORKDIR /root/geonetwork

RUN set -xe && \
    git checkout tags/${GEONETWORK_VERSION} -b docker-builder && \
    git submodule init && \
    git submodule update

VOLUME ["/root/.m2"]

# Mods and builds
# Change obsolete PostgreSQL JDBC and old repos
# Force log4j to 2.17.1 
# - https://security.snyk.io/vuln/SNYK-JAVA-ORGAPACHELOGGINGLOG4J-2314720
# - https://snyk.io/blog/log4shell-remediation-cheat-sheet/
RUN sed -i 's/<pg\.version>[^<]*</<pg.version>42.2.18</g' pom.xml && \
    sed -i 's/http:\/\/download.osgeo.org\/webdav\/geotools\//https:\/\/repo.osgeo.org\/repository\/release/g' pom.xml && \
    sed -i 's/https:\/\/packages.georchestra.org\/artifactory\/mapfish-print/https:\/\/artifactory.georchestra.org\/artifactory\/geonetwork-github-cache/g' pom.xml && \
    sed -i 's/<log4j2\.version>[^<]*</<log4j2\.version>2.17.1</g' pom.xml && \
    mvn clean install -DskipTests | tee install.log && \
    mv install.log ./web/target/geonetwork/install.log


FROM docker.io/library/tomcat:${TOMCAT_IMAGE_TAG} AS RELEASE

ARG GEONETWORK_VERSION
ARG GEONETWORK_DATA_DIR=/srv/geonetwork/data
ARG GEONETWORK_UID=15000
ARG GEONETWORK_GID=15000

LABEL org.opencontainers.image.title "Geonetwork SGB/CPRM"
LABEL org.opencontainers.image.description "Geonetwork customizado pelo SGB/CPRM"
LABEL org.opencontainers.image.vendor "SGB/CPRM"
LABEL org.opencontainers.image.version $GEONETWORK_VERSION
LABEL org.opencontainers.image.source https://github.com/nds-cprm/geonetwork-oci
LABEL org.opencontainers.image.authors "Carlos Eduardo Mota <carlos.mota@sgb.gov.br>"

ENV JAVA_OPTS="-server -Djava.awt.headless=true -Xms2048m -Xmx2048m -XX:NewRatio=2 -XX:SurvivorRatio=10" \
    GEONETWORK_DB_TYPE="h2" \
    GEONETWORK_DATA_DIR=${GEONETWORK_DATA_DIR}

# Copy built
COPY --from=BUILDER /root/geonetwork/web/target/geonetwork/ ./webapps/geonetwork/

# Entrypoint
COPY docker-entrypoint.sh /

# Enable Rootless & move the default h2 db to /tmp (avoid change tomcat dir permissions)
RUN groupadd -g ${GEONETWORK_GID} geoserver && \
    useradd -M -s /sbin/nologin -c "Geonetwork" \
        -u ${GEONETWORK_UID} -g ${GEONETWORK_GID} -N geonetwork && \    
    sed -i -r "s/jdbc.database=.*$/jdbc.database=\/tmp\/gn/g" ./webapps/geonetwork/WEB-INF/config-db/jdbc.properties && \
    mkdir -p ${GEONETWORK_DATA_DIR} && \
    chgrp -R ${GEONETWORK_GID} \
        ./webapps/geonetwork/WEB-INF/config-db/ \
        ./webapps/geonetwork/WEB-INF/config-node/ \
        ./webapps/geonetwork/WEB-INF/data/ \
        ${GEONETWORK_DATA_DIR} && \
    chmod -R g=u \
        ./webapps/geonetwork/WEB-INF/config-db/ \
        ./webapps/geonetwork/WEB-INF/config-node/ \
        ./webapps/geonetwork/WEB-INF/data/ \
        ${GEONETWORK_DATA_DIR} && \
    chmod +x /docker-entrypoint.sh

USER geonetwork

ENTRYPOINT ["/docker-entrypoint.sh"]

CMD ["catalina.sh", "run"]
