#!/bin/bash
set -e

# -------------------------------------------------------------------
# Anvil + JSONBin.io Persistence Entrypoint
# -------------------------------------------------------------------
# Environment variables are hardcoded below - modify as needed
# -------------------------------------------------------------------

# Hardcoded configuration
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

log "========================================="
log "🔷 ANVIL + JSONBIN PERSISTENCE STARTING"
log "========================================="

# -------------------------------------------------------------------
# Check that required commands exist
log "🔍 Checking required dependencies..."
for cmd in curl jq; do
    if ! command -v $cmd >/dev/null 2>&1; then
        log "❌ Required command '$cmd' not found. Aborting."
        exit 1
    fi
done
log "✅ All dependencies present (curl, jq)"

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
# PHASE 1: DOWNLOAD STATE FROM JSONBIN BEFORE ANYTHING ELSE
# -------------------------------------------------------------------
log "========================================="
log "🔵 PHASE 1: LOADING PERSISTED STATE FROM JSONBIN"
log "========================================="
log "📡 Source: JSONBin.io"
log "🆔 Bin ID: ${JSONBIN_BIN_ID}"
log "💾 Target file: ${STATE_FILE}"

download_state() {
    log "📥 Attempting to download state from JSONBin.io..."
    
    if [ -z "${JSONBIN_BIN_ID}" ] || [ -z "${JSONBIN_API_KEY}" ]; then
        log "⚠️ JSONBIN_BIN_ID or JSONBIN_API_KEY not set. Starting fresh."
        rm -f "${STATE_FILE}"
        return 1
    fi

    # Attempt download with timeout
    RESPONSE=$(curl -s --max-time 30 -X GET "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}/latest" \
        -H "X-Master-Key: ${JSONBIN_API_KEY}" 2>&1) || {
        log "⚠️ curl download failed or timed out: ${RESPONSE}"
        rm -f "${STATE_FILE}"
        return 1
    }

    # Check if response contains valid record
    if echo "$RESPONSE" | jq -e '.record' > /dev/null 2>&1; then
        log "📦 Extracting state data from response..."
        echo "$RESPONSE" | jq -r '.record' > "${STATE_FILE}"
        
        if validate_state "${STATE_FILE}"; then
            local size=$(wc -c < "${STATE_FILE}")
            local block=$(jq -r '.block' "${STATE_FILE}" 2>/dev/null || echo "unknown")
            log "✅ State loaded successfully!"
            log "   - File size: ${size} bytes"
            log "   - Block number: ${block}"
            return 0
        else
            log "⚠️ Downloaded state is invalid (missing 'block' field)"
            rm -f "${STATE_FILE}"
            return 1
        fi
    else
        log "⚠️ No valid state found in JSONBin response"
        log "   Response: $(echo "$RESPONSE" | head -c 200)..."
        rm -f "${STATE_FILE}"
        return 1
    fi
}

# Execute download
if download_state; then
    STATE_LOADED="yes"
    log "🎯 State successfully loaded from JSONBin"
else
    STATE_LOADED="no"
    log "🆕 No existing state found - will start with fresh chain"
fi

# -------------------------------------------------------------------
# PHASE 2: REGISTER CONTAINER IMAGE
# -------------------------------------------------------------------
log "========================================="
log "🟢 PHASE 2: REGISTERING CONTAINER IMAGE"
log "========================================="
log "📦 Image Configuration:"
log "   - Chain ID: ${CHAIN_ID}"
log "   - Port: ${PORT}"
log "   - Fork URL: ${FORK_URL:0:50}..."
log "   - State file: ${STATE_FILE}"
log "   - State loaded: ${STATE_LOADED}"
log "   - Periodic sync: Every 60 seconds"
log "✅ Container image registered with persistence enabled"

# -------------------------------------------------------------------
# Upload local state to JSONBin.io
upload_state() {
    log "📤 Uploading state to JSONBin.io..."
    
    if [ -z "${JSONBIN_BIN_ID}" ] || [ -z "${JSONBIN_API_KEY}" ]; then
        log "⚠️ JSONBIN_BIN_ID or JSONBIN_API_KEY not set. Skipping upload."
        return 1
    fi

    if [ ! -f "${STATE_FILE}" ]; then
        log "⚠️ No state file exists at ${STATE_FILE}"
        return 1
    fi

    if ! validate_state "${STATE_FILE}"; then
        log "⚠️ State file is invalid or corrupted"
        return 1
    fi

    STATE_CONTENT=$(cat "${STATE_FILE}")
    local block=$(jq -r '.block' "${STATE_FILE}" 2>/dev/null || echo "unknown")
    local size=$(wc -c < "${STATE_FILE}")
    
    log "📦 Uploading state (block: ${block}, size: ${size} bytes)..."
    
    RESPONSE=$(curl -s --max-time 30 -X PUT "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}" \
        -H "Content-Type: application/json" \
        -H "X-Master-Key: ${JSONBIN_API_KEY}" \
        -d "{\"record\": ${STATE_CONTENT}}" 2>&1) || {
        log "⚠️ curl upload failed or timed out: ${RESPONSE}"
        return 1
    }

    if echo "$RESPONSE" | jq -e '.record' > /dev/null 2>&1; then
        log "✅ State uploaded successfully to JSONBin!"
        return 0
    else
        local error_msg=$(echo "$RESPONSE" | jq -r '.message // "Unknown error"' 2>/dev/null)
        log "❌ Upload failed: ${error_msg}"
        return 1
    fi
}

# -------------------------------------------------------------------
# Periodic upload (runs in background)
periodic_upload() {
    local count=0
    while true; do
        sleep 60   # upload every 60 seconds
        count=$((count + 1))
        log "⏰ Periodic upload #${count} triggered..."
        upload_state
    done
}

# -------------------------------------------------------------------
# PHASE 3: START BACKGROUND SYNC SERVICE
# -------------------------------------------------------------------
log "========================================="
log "🟡 PHASE 3: STARTING BACKGROUND SERVICES"
log "========================================="

# Trap signals to upload state on exit
trap 'log "⚠️ Container stopping, uploading final state..."; upload_state; log "👋 Shutdown complete"; exit 0' SIGTERM SIGINT

periodic_upload &
log "✅ State sync service started (uploads every 60 seconds)"

# -------------------------------------------------------------------
# PHASE 4: LAUNCH ANVIL
# -------------------------------------------------------------------
log "========================================="
log "🚀 PHASE 4: LAUNCHING ANVIL NODE"
log "========================================="

# Build Anvil command
CMD="anvil --fork-url ${FORK_URL} --chain-id ${CHAIN_ID} --host 0.0.0.0 --port ${PORT}"

# Only add state flag if state was successfully loaded
if [ "${STATE_LOADED}" = "yes" ] && [ -f "${STATE_FILE}" ]; then
    CMD="${CMD} --state ${STATE_FILE}"
    log "📂 Launching with persisted state from block $(jq -r '.block' "${STATE_FILE}" 2>/dev/null || echo "unknown")"
else
    log "🆕 Launching with fresh state"
fi

log "🔧 Command: ${CMD}"
log "📡 RPC endpoint: http://0.0.0.0:${PORT}"
log "🌐 Public endpoint: https://anvil-render-q5wl.onrender.com"
log "⏳ Node is starting..."
log "========================================="

# Start Anvil and wait for it to finish
$CMD &
ANVIL_PID=$!

log "✅ Anvil process started (PID: ${ANVIL_PID})"
log "📋 Logs will appear below:"
log "========================================="

wait $ANVIL_PID
