#!/bin/sh
set -e

API_KEYS="${ENVOY_API_KEYS:-placeholder_api_key}"
BASIC_AUTH_CREDS="${ENVOY_BASIC_AUTH_CREDENTIALS:-}"
AUTH_METHOD="${ENVOY_AUTH_METHOD:-api-key}"

TEMP_KEYS=$(mktemp)
TEMP_BASIC=$(mktemp)
# Cleanup function to remove temp files on exit
cleanup() {
  rm -f "$TEMP_KEYS" "${TEMP_KEYS}.new" "${TEMP_KEYS}.tmp" "$TEMP_BASIC" "${TEMP_BASIC}.new" "${TEMP_BASIC}.tmp" 2>/dev/null || true
}
trap cleanup EXIT

# Process API keys
IFS=','
for key in $API_KEYS; do
  key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  if [ -n "$key" ]; then
    echo "                            \"$key\"," >> "$TEMP_KEYS"
  fi
done
unset IFS

# Remove trailing comma from API keys
if [ -f "$TEMP_KEYS" ] && [ -s "$TEMP_KEYS" ]; then
  sed '$ s/,$//' "$TEMP_KEYS" > "${TEMP_KEYS}.new"
  if [ -f "${TEMP_KEYS}.new" ] && [ -s "${TEMP_KEYS}.new" ]; then
    mv "${TEMP_KEYS}.new" "$TEMP_KEYS"
  fi
fi

# Process Basic Auth credentials (format: username:password)
if [ -n "$BASIC_AUTH_CREDS" ]; then
  IFS=','
  for cred in $BASIC_AUTH_CREDS; do
    cred=$(echo "$cred" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -n "$cred" ]; then
      echo "                            \"$cred\"," >> "$TEMP_BASIC"
    fi
  done
  unset IFS
  
  # Remove trailing comma from basic auth credentials
  if [ -f "$TEMP_BASIC" ] && [ -s "$TEMP_BASIC" ]; then
    sed '$ s/,$//' "$TEMP_BASIC" > "${TEMP_BASIC}.new"
    if [ -f "${TEMP_BASIC}.new" ] && [ -s "${TEMP_BASIC}.new" ]; then
      mv "${TEMP_BASIC}.new" "$TEMP_BASIC"
    fi
  fi
fi

# Replace placeholders in template
TEMP_OUTPUT=$(mktemp)
cleanup() {
  rm -f "$TEMP_KEYS" "${TEMP_KEYS}.new" "${TEMP_KEYS}.tmp" "$TEMP_BASIC" "${TEMP_BASIC}.new" "${TEMP_BASIC}.tmp" "$TEMP_OUTPUT" 2>/dev/null || true
}
trap cleanup EXIT

while IFS= read -r line; do
  case "$line" in
    *'${ENVOY_API_KEYS}'*)
      if [ -f "$TEMP_KEYS" ] && [ -s "$TEMP_KEYS" ]; then
        cat "$TEMP_KEYS"
      else
        echo "                            \"placeholder_api_key\""
      fi
      ;;
    *'${ENVOY_BASIC_AUTH_CREDENTIALS}'*)
      if [ -f "$TEMP_BASIC" ] && [ -s "$TEMP_BASIC" ]; then
        cat "$TEMP_BASIC"
      else
        echo "                            \"\""
      fi
      ;;
    *)
      echo "$line"
      ;;
  esac
done < /etc/envoy/envoy.template.yaml > "$TEMP_OUTPUT"

# Post-process to replace ENVOY_AUTH_METHOD placeholder
sed "s|__ENVOY_AUTH_METHOD__|${AUTH_METHOD}|g" "$TEMP_OUTPUT" > /etc/envoy/envoy.yaml

echo "Envoy config generated successfully" >&2

