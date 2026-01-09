#!/bin/sh
set -e

AUTH_METHOD="${ENVOY_AUTH_METHOD:-api-key}"
CREDS="${ENVOY_BASIC_AUTH_CREDENTIALS:-}"
OUTPUT_FILE="/etc/prometheus/web.config.yml"

# generates web.config.yml based on auth method
if [ "$AUTH_METHOD" = "basic-auth" ] && [ -n "$CREDS" ]; then
  USER=$(echo "$CREDS" | cut -d: -f1)
  PASS=$(echo "$CREDS" | cut -d: -f2-)
  
  # generate bcrypt hash from password
  HASH=$(htpasswd -nbBC 10 "$USER" "$PASS" | cut -d: -f2)
  
  echo "Prometheus: Generated basic auth config for user '$USER'" >&2
  cat > "$OUTPUT_FILE" << EOF
basic_auth_users:
  ${USER}: ${HASH}
EOF
else
  echo "Prometheus: No basic auth (auth_method=$AUTH_METHOD)" >&2
  echo "{}" > "$OUTPUT_FILE"
fi

