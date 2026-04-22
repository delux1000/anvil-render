#!/bin/bash
set -e

# -------------------------------------------------------------------
# Anvil + JSONBin.io Persistence Entrypoint
# -------------------------------------------------------------------
# Environment variables are hardcoded below - modify as needed
# -------------------------------------------------------------------

# Hardcoded configuration - EDIT THESE VALUES
JSONBIN_BIN_ID="6936f28bae596e708f8bafc0"
JSONBIN_API_KEY='$2a$10$aAW84k1Q4lfQR8ELHBneT.01Go2JevCCoay/TR4AATTeNpTd7ou9K'
FORK_URL="https://eth-mainnet.g.alchemy.com/v2/QFjExKnnaI2I4qTV7EFM7WwB0gl08X0n"
CHAIN_ID="1"
PORT="8545"
STATE_FILE="/tmp/state.json"

# -------------------------------------------------------------------
# Logging helper (writes to stdout and a log file)
LOG_FILE="/tmp/anvil-jsonbin.log"
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# -------------------------------------------------------------------
# Check that required commands exist
for cmd in curl jq; do
    if ! command -v $cmd >/dev/null 2>&1; then
        log "❌ Required command '$cmd' not found. Aborting."
        exit 1
    fi
done

# -------------------------------------------------------------------
# Validate that a file is a proper Anvil state (has a "block" field)
validate_state() {
    local file=$1
    if [ ! -f "$file" ]; then
        return 1
    fi
    if ! jq -e '.block' "$file" > /dev/null 2>&1; then
        return 1
    fi
    return 0
}

# -------------------------------------------------------------------
# Download state from JSONBin.io
download_state() {
    log "📥 Downloading previous state from JSONBin.io..."
    if [ -z "${JSONBIN_BIN_ID}" ] || [ -z "${JSONBIN_API_KEY}" ]; then
        log "⚠️ JSONBIN_BIN_ID or JSONBIN_API_KEY not set. Starting fresh."
        rm -f "${STATE_FILE}"
        return 0
    fi

    RESPONSE=$(curl -s -X GET "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}/latest" \
        -H "X-Master-Key: ${JSONBIN_API_KEY}") || {
        log "⚠️ curl failed. Starting fresh."
        rm -f "${STATE_FILE}"
        return 0
    }

    if echo "$RESPONSE" | jq -e '.record' > /dev/null 2>&1; then
        echo "$RESPONSE" | jq -r '.record' > "${STATE_FILE}"
        if validate_state "${STATE_FILE}"; then
            log "✅ Valid state downloaded (size: $(wc -c < "${STATE_FILE}") bytes)"
        else
            log "⚠️ Downloaded state is invalid (missing required fields). Starting fresh."
            rm -f "${STATE_FILE}"
        fi
    else
        log "⚠️ No previous state found or download failed. Starting fresh."
        rm -f "${STATE_FILE}"
    fi
}

# -------------------------------------------------------------------
# Upload local state to JSONBin.io
upload_state() {
    log "📤 Uploading state to JSONBin.io..."
    if [ -z "${JSONBIN_BIN_ID}" ] || [ -z "${JSONBIN_API_KEY}" ]; then
        log "⚠️ JSONBIN_BIN_ID or JSONBIN_API_KEY not set. Skipping upload."
        return 0
    fi

    if [ -f "${STATE_FILE}" ] && validate_state "${STATE_FILE}"; then
        STATE_CONTENT=$(cat "${STATE_FILE}")
        RESPONSE=$(curl -s -X PUT "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}" \
            -H "Content-Type: application/json" \
            -H "X-Master-Key: ${JSONBIN_API_KEY}" \
            -d "{\"record\": ${STATE_CONTENT}}") || {
            log "⚠️ curl upload failed."
            return 0
        }

        if echo "$RESPONSE" | jq -e '.record' > /dev/null 2>&1; then
            log "✅ State uploaded successfully!"
        else
            log "❌ Upload failed: $(echo "$RESPONSE" | jq -r '.message // "Unknown error"')"
        fi
    else
        log "⚠️ No valid state file to upload."
    fi
}

# -------------------------------------------------------------------
# Periodic upload (runs in background)
periodic_upload() {
    while true; do
        sleep 60   # upload every 60 seconds
        log "⏰ Periodic upload triggered..."
        upload_state
    done
}

# -------------------------------------------------------------------
# Trap signals to upload state on exit
trap 'log "⚠️ Container stopping, uploading final state..."; upload_state; exit 0' SIGTERM SIGINT

# -------------------------------------------------------------------
# Download previous state (if any)
download_state

# -------------------------------------------------------------------
# Start periodic upload in background
periodic_upload &

# -------------------------------------------------------------------
# Build Anvil command
CMD="anvil --fork-url ${FORK_URL} --chain-id ${CHAIN_ID} --host 0.0.0.0 --port ${PORT} --state ${STATE_FILE}"

# -------------------------------------------------------------------
# Launch Anvil
log "🚀 Starting Anvil with command: $CMD"
log "📡 RPC endpoint: http://localhost:${PORT} (public via Render)"
log "⏳ Waiting for connections... (Press Ctrl+C to stop and save state)"
log "========================================="

# Start Anvil and wait for it to finish
$CMD &
ANVIL_PID=$!
wait $ANVIL_PID
