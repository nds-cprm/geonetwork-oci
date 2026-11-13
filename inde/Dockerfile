ARG GEONETWORK_IMAGE_REPOSITORY=docker.io/ndscprm/geonetwork
ARG GEONETWORK_IMAGE_TAG=3.10.2

# Stage the INDE overlay with its final layout and permissions, so the release stage
# needs a single COPY and no RUN as root
FROM ${GEONETWORK_IMAGE_REPOSITORY}:${GEONETWORK_IMAGE_TAG} AS overlay

USER root

# INDE Metadata profiles and patches
# https://inde.gov.br/Suporte/InstalacaoGN
COPY ["src/perfis/mgb/", "src/perfis/mgb2/", "/overlay/WEB-INF/data/config/schema_plugins/"]
COPY src/alteracoes/geonetwork/ /overlay/

# Enable MGB Profiles in geonetwork
# Permissions: read-only by default, group 0 gets the owner bits where the base image does
# (config-db, data), so arbitrary UIDs in group 0 can write there (OpenShift)
RUN mv /overlay/WEB-INF/data/config/schema_plugins/config-spring-mgb*.xml /overlay/WEB-INF/ && \
    sed -i '49i <import resource="config-spring-mgb.xml"/>\n<import resource="config-spring-mgb-2.xml"/>' \
        /overlay/WEB-INF/config-spring-geonetwork.xml && \
    chmod -R u=rwX,go=rX /overlay && \
    chmod -R g=u /overlay/WEB-INF/config-db /overlay/WEB-INF/data


FROM ${GEONETWORK_IMAGE_REPOSITORY}:${GEONETWORK_IMAGE_TAG} AS release

ARG GEONETWORK_IMAGE_TAG

LABEL org.opencontainers.image.title="Geonetwork INDE"
LABEL org.opencontainers.image.description="Geonetwork customizado pelo SGB/CPRM para uso na INDE"
LABEL org.opencontainers.image.version="$GEONETWORK_IMAGE_TAG-inde"
LABEL org.opencontainers.image.ref.name="$GEONETWORK_IMAGE_TAG-inde"
LABEL org.opencontainers.image.vendor="SGB/CPRM"

# COPY --from keeps the modes set in the overlay stage
COPY --from=overlay /overlay/ webapps/geonetwork/
