ARG GEONETWORK_IMAGE_REPOSITORY=docker.io/ndscprm/geonetwork
ARG GEONETWORK_IMAGE_TAG=3.10.2

FROM ${GEONETWORK_IMAGE_REPOSITORY}:${GEONETWORK_IMAGE_TAG}

USER root

LABEL org.opencontainers.image.title "Geonetwork INDE"
LABEL org.opencontainers.image.description "Geonetwork customizado pelo SGB/CPRM para uso na INDE"
LABEL org.opencontainers.image.vendor "SGB/CPRM"

# INDE Metadata profiles and patches
# https://inde.gov.br/Suporte/InstalacaoGN
COPY ["src/perfis/mgb/", "src/perfis/mgb2/", "webapps/geonetwork/WEB-INF/data/config/schema_plugins/"]
COPY src/alteracoes/ webapps/geonetwork/

# Enable MGB Profiles in geonetwork
RUN mv ./webapps/geonetwork/WEB-INF/data/config/schema_plugins/config-spring-mgb*.xml ./webapps/geonetwork/WEB-INF && \
    sed -i '49i <import resource="config-spring-mgb.xml"/>\n<import resource="config-spring-mgb-2.xml"/>' \
        ./webapps/geonetwork/WEB-INF/config-spring-geonetwork.xml && \
    chmod 644 ./webapps/geonetwork/WEB-INF/config-spring-mgb*.xml

USER geonetwork
