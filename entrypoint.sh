#!/bin/bash
set -e

echo "========================================="
echo "🔧 Anvil with JSONBin.io Persistence"
echo "========================================="

# Hardcoded JSONBin.io credentials
JSONBIN_BIN_ID="6994c9b743b1c97be986b84b"
JSONBIN_API_KEY="$2a$10$UFKAyDvpR8RhJ8QzH2Q3zuDyayu0LAVb9OVIhHZyhmxTaZInpfrTu"

STATE_FILE=${STATE_FILE:-/tmp/state.json}
PORT=${PORT:-8545}
CHAIN_ID=${CHAIN_ID:-1}
FORK_URL=${FORK_URL:-https://eth-mainnet.g.alchemy.com/v2/QFjExKnnaI2I4qTV7EFM7WwB0gl08X0n}
RENDER_URL="https://anvil-render.onrender.com"

LOG_FILE="/tmp/upload.log"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

validate_state() {
  local file=$1
  if [ ! -f "$file" ]; then
    log "❌ State file $file does not exist."
    return 1
  fi
  if ! jq -e '.block' "$file" > /dev/null 2>&1; then
    log "❌ State file $file is missing 'block' field."
    return 1
  fi
  log "✅ State file $file is valid."
  return 0
}

download_state() {
  log "📥 Downloading previous state from JSONBin.io..."
  RESPONSE=$(curl -s -X GET "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}/latest" \
    -H "X-Master-Key: ${JSONBIN_API_KEY}")
  
  if echo "$RESPONSE" | jq -e '.record' > /dev/null 2>&1; then
    echo "$RESPONSE" | jq -r '.record' > "${STATE_FILE}"
    if validate_state "${STATE_FILE}"; then
      STATE_SIZE=$(wc -c < "${STATE_FILE}")
      log "✅ Valid state downloaded (size: $STATE_SIZE bytes)"
    else
      log "⚠️ Downloaded state is invalid. Starting fresh."
      rm -f "${STATE_FILE}"
    fi
  else
    log "⚠️ No previous state found or download failed. Starting fresh."
    rm -f "${STATE_FILE}"
  fi
}

upload_state() {
  log "📤 Uploading state to JSONBin.io..."
  if [ -f "${STATE_FILE}" ] && validate_state "${STATE_FILE}"; then
    STATE_CONTENT=$(cat "${STATE_FILE}")
    RESPONSE=$(curl -s -X PUT "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}" \
      -H "Content-Type: application/json" \
      -H "X-Master-Key: ${JSONBIN_API_KEY}" \
      -d "{\"record\": ${STATE_CONTENT}}")
    
    if echo "$RESPONSE" | jq -e '.record' > /dev/null 2>&1; then
      log "✅ State uploaded successfully!"
    else
      log "❌ Upload failed: $RESPONSE"
    fi
  else
    log "⚠️ No valid state file to upload."
  fi
}

# Periodic upload every 30 seconds (in background)
periodic_upload() {
  while true; do
    sleep 30
    log "⏰ Periodic upload triggered (30s)..."
    upload_state
  done
}

# Trap signals to upload state on exit
trap 'log "⚠️ Container stopping, uploading state..."; upload_state; exit 0' SIGTERM SIGINT

# Download previous state (if any)
download_state

# Start periodic upload in background
periodic_upload &

# Build the Anvil command
CMD="anvil --fork-url ${FORK_URL} --chain-id ${CHAIN_ID} --host 0.0.0.0 --port ${PORT}"

if [ -f "${STATE_FILE}" ] && validate_state "${STATE_FILE}"; then
  CMD="${CMD} --state ${STATE_FILE}"
  log "✅ Resuming from saved state."
else
  log "🆕 Starting with fresh state."
fi

log "🚀 Starting Anvil with command: $CMD"
log "📡 Public URL: ${RENDER_URL}"

# Start Anvil
$CMD &
ANVIL_PID=$!

# Wait for Anvil to finish
wait $ANVIL_PID
