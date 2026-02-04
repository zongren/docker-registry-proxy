#!/bin/bash

set -e
export DRP_PROXY="docker.nandgates.com:3128" # Format IP:port, change this 
export CA_CERT_URL="https://${PROXY_HOST}/ca.crt"
wget -O - "http://${DRP_PROXY}/" # Make sure you can reach the proxy
# Inject the CA certificate
docker run -it --privileged --pid=host justincormack/nsenter1 \
  /bin/bash -c "curl -o /containers/services/docker/lower/etc/ssl/certs/ca-certificates.crt $CA_CERT_URL"

# Preserve original config.
docker run -it --privileged --pid=host justincormack/nsenter1 /bin/bash -c "cp /containers/services/docker/config.json /containers/services/docker/config.json.orig"

# Inject the HTTPS_PROXY enviroment variable. I dare you find a better way.
docker run -it --privileged --pid=host justincormack/nsenter1 /bin/bash -c "sed -ibeforedockerproxy -e  's/\"PATH=/\"HTTPS_PROXY=http:\/\/$DRP_PROXY\/\",\"PATH=/' /containers/services/docker/config.json"