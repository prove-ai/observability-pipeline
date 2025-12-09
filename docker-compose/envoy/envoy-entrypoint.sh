#!/bin/sh
set -e

# Generate Envoy config from template
/bin/sh /etc/envoy/generate-envoy-config.sh

# Start Envoy with the generated config
exec /usr/local/bin/envoy -c /etc/envoy/envoy.yaml "$@"

