# GeoNetwork Container Image

Uma implementação personalizada do GeoNetwork, compilado diretamente do código fonte

Autor: Carlos Eduardo Mota

## Build Args
- TOMCAT_IMAGE_TAG=8.5-jre8-temurin-jammy
- MAVEN_IMAGE_TAG=3.8-eclipse-temurin-8
- MAVEN_OPTS="-Xmx512M"
- GEONETWORK_GIT_URL=https://github.com/geonetwork/core-geonetwork.git
- GEONETWORK_VERSION=3.10.2

## Environment Variables
- JAVA_OPTS="-server -Djava.awt.headless=true -Xms2048m -Xmx2048m -XX:NewRatio=2 -XX:SurvivorRatio=10"
- GEONETWORK_DATA_DIR
- GEONETWORK_LUCENE_DIR
- GEONETWORK_DB_TYPE=h2  ->  Opções: (h2, postgres, postgis)
- GEONETWORK_DB_HOST
- GEONETWORK_DB_PORT
- GEONETWORK_DB_DATABASE
- GEONETWORK_DB_USERNAME
- GEONETWORK_DB_PASSWORD

## References
- https://geonetwork-opensource.org/manuals/3.10.x/en/install-guide/installing-from-source-code.html