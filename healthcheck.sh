#!/bin/sh
# Container health check, used by the image HEALTHCHECK and by exec probes (OpenShift/Kubernetes).
#
# Healthy only when the GeoNetwork (Jeeves) application started and the database answers.
# The REST API (/srv/api) keeps answering 200 when the Jeeves startup fails, and the Jeeves
# services answer 200 with an HTML error page, so the body of a Jeeves service is checked.
# srv/eng/info?type=site is anonymous, light, reads the database and works on an empty catalog.

if curl -fsS -m 8 "http://localhost:8080/geonetwork/srv/eng/info?type=site" | grep -q "<info>"; then
    exit 0
fi

echo "GeoNetwork is not ready (srv/eng/info?type=site did not return <info>)" >&2
exit 1
