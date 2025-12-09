#!/bin/sh
set -e

API_KEYS="${ENVOY_API_KEYS:-placeholder_api_key}"

TEMP_KEYS=$(mktemp)
# Cleanup function to remove temp files on exit
cleanup() {
  rm -f "$TEMP_KEYS" "${TEMP_KEYS}.new" "${TEMP_KEYS}.tmp" 2>/dev/null || true
}
trap cleanup EXIT

IFS=','
for key in $API_KEYS; do
  key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  if [ -n "$key" ]; then
    echo "                            \"$key\"," >> "$TEMP_KEYS"
  fi
done
unset IFS

# Remove trailing comma from last line
# Use a more reliable approach that works in Alpine containers
if [ -f "$TEMP_KEYS" ] && [ -s "$TEMP_KEYS" ]; then
  sed '$ s/,$//' "$TEMP_KEYS" > "${TEMP_KEYS}.new"
  if [ -f "${TEMP_KEYS}.new" ] && [ -s "${TEMP_KEYS}.new" ]; then
    mv "${TEMP_KEYS}.new" "$TEMP_KEYS"
  fi
fi

# Replace placeholder in template
while IFS= read -r line; do
  case "$line" in
    *'${ENVOY_API_KEYS}'*)
      cat "$TEMP_KEYS"
      ;;
    *)
      echo "$line"
      ;;
  esac
done < /etc/envoy/envoy.template.yaml > /etc/envoy/envoy.yaml

echo "Envoy config generated successfully" >&2

