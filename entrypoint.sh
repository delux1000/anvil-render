#!/bin/bash
set -e

echo "========================================="
echo "🔧 Anvil with JSONBin.io Persistence"
echo "========================================="

download_state() {
  echo "📥 Downloading previous state from JSONBin.io..."
  RESPONSE=$(curl -s -X GET "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}/latest" \
    -H "X-Master-Key: ${JSONBIN_API_KEY}")
  
  if echo "$RESPONSE" | jq -e '.record' > /dev/null 2>&1; then
    echo "$RESPONSE" | jq -r '.record' > "${STATE_FILE}"
    echo "✅ State downloaded"
  else
    echo "⚠️ No previous state found. Starting fresh."
    rm -f "${STATE_FILE}"
  fi
}

upload_state() {
  echo ""
  echo "📤 Uploading state to JSONBin.io..."
  if [ -f "${STATE_FILE}" ]; then
    STATE_CONTENT=$(cat "${STATE_FILE}")
    RESPONSE=$(curl -s -X PUT "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}" \
      -H "Content-Type: application/json" \
      -H "X-Master-Key: ${JSONBIN_API_KEY}" \
      -d "{\"record\": ${STATE_CONTENT}}")
    
    if echo "$RESPONSE" | jq -e '.record' > /dev/null 2>&1; then
      echo "✅ State uploaded successfully!"
    else
      echo "❌ Upload failed"
    fi
  fi
}

trap 'upload_state; exit 0' SIGTERM SIGINT

download_state

CMD="anvil --fork-url ${FORK_URL} --chain-id ${CHAIN_ID} --host 0.0.0.0 --port ${PORT}"
[ -f "${STATE_FILE}" ] && CMD="${CMD} --state ${STATE_FILE}"

echo "🚀 Starting Anvil..."
$CMD &
ANVIL_PID=$!

wait $ANVIL_PID
