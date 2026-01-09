#!/bin/sh
set -e

/bin/sh /etc/prometheus/generate-prometheus-config.sh

exec /bin/prometheus "$@"

