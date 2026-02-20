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

# Your Render URL (displayed in logs)
RENDER_URL="https://anvil-render.onrender.com"

# Function to validate that a file is a proper Anvil state JSON
validate_state() {
  local file=$1
  if [ ! -f "$file" ]; then
    return 1
  fi
  # Check if it's valid JSON and contains a "block" field (basic check)
  if ! jq -e '.block' "$file" > /dev/null 2>&1; then
    return 1
  fi
  return 0
}

download_state() {
  echo "📥 Downloading previous state from JSONBin.io..."
  RESPONSE=$(curl -s -X GET "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}/latest" \
    -H "X-Master-Key: ${JSONBIN_API_KEY}")
  
  if echo "$RESPONSE" | jq -e '.record' > /dev/null 2>&1; then
    # Extract the record and save to state file
    echo "$RESPONSE" | jq -r '.record' > "${STATE_FILE}"
    
    # Validate the downloaded state
    if validate_state "${STATE_FILE}"; then
      echo "✅ Valid state downloaded (${STATE_FILE})"
      STATE_SIZE=$(wc -c < "${STATE_FILE}")
      echo "   Size: $STATE_SIZE bytes"
    else
      echo "⚠️ Downloaded state is invalid (missing required fields). Starting fresh."
      rm -f "${STATE_FILE}"
    fi
  else
    echo "⚠️ No previous state found or download failed. Starting fresh."
    rm -f "${STATE_FILE}"
  fi
}

upload_state() {
  echo ""
  echo "📤 Uploading state to JSONBin.io..."
  if [ -f "${STATE_FILE}" ]; then
    # Only upload if file exists and is valid
    if validate_state "${STATE_FILE}"; then
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
    else
      echo "⚠️ Current state file is invalid, skipping upload."
    fi
  else
    echo "⚠️ No state file found, skipping upload."
  fi
}

# Trap signals to upload state on exit
trap 'upload_state; exit 0' SIGTERM SIGINT

# Download previous state (if any)
download_state

# Build the Anvil command
CMD="anvil --fork-url ${FORK_URL} --chain-id ${CHAIN_ID} --host 0.0.0.0 --port ${PORT}"

# Only add --state if the file exists and is valid
if [ -f "${STATE_FILE}" ] && validate_state "${STATE_FILE}"; then
  CMD="${CMD} --state ${STATE_FILE}"
  echo "✅ Resuming from saved state."
else
  echo "🆕 Starting with fresh state."
fi

echo ""
echo "🚀 Starting Anvil with command:"
echo "   $CMD"
echo ""
echo "📡 RPC endpoint: http://localhost:${PORT}"
echo "   Public URL: ${RENDER_URL}"
echo ""
echo "⏳ Waiting for connections... (Press Ctrl+C to stop and save state)"
echo "========================================="

# Start Anvil
$CMD &
ANVIL_PID=$!

# Wait for Anvil to finish
wait $ANVIL_PID
