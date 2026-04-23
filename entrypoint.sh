#!/bin/bash
set -e

# -------------------------------------------------------------------
# Anvil + JSONBin.io Persistence Entrypoint (BALANCE-SAFE VERSION)
# -------------------------------------------------------------------
# This version preserves ALL balances from the state file.
# Only impersonation is restored (needed for signing transactions).
# No balances are ever modified on restart.
# -------------------------------------------------------------------

# Hardcoded configuration
JSONBIN_BIN_ID="6936f28bae596e708f8bafc0"
JSONBIN_API_KEY='$2a$10$aAW84k1Q4lfQR8ELHBneT.01Go2JevCCoay/TR4AATTeNpTd7ou9K'
FORK_URL="https://eth-mainnet.g.alchemy.com/v2/QFjExKnnaI2I4qTV7EFM7WwB0gl08X0n"
CHAIN_ID="1"
PORT="8545"
STATE_FILE="/tmp/state.json"

# Wallets to impersonate (access only, no balance changes)
MY_WALLET="0x4515C3834807993B080976da0F08790B70D5A247"
USDT_WHALE="0x28C6c06298d514Db089934071355E5743bf21d60"

# -------------------------------------------------------------------
# Logging helper
LOG_FILE="/tmp/anvil-jsonbin.log"
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log "========================================="
log "🔷 ANVIL + JSONBIN PERSISTENCE STARTING"
log "🔷 MODE: Preserve All Balances"
log "========================================="

# -------------------------------------------------------------------
# Check dependencies
log "🔍 Checking required dependencies..."
for cmd in curl jq; do
    if ! command -v $cmd >/dev/null 2>&1; then
        log "❌ Required command '$cmd' not found. Aborting."
        exit 1
    fi
done
log "✅ All dependencies present (curl, jq)"

# -------------------------------------------------------------------
# Validate state file
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
# PHASE 1: DOWNLOAD STATE FROM JSONBIN
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
        log "⚠️ Credentials not set. Starting fresh."
        rm -f "${STATE_FILE}"
        return 1
    fi

    RESPONSE=$(curl -s --max-time 30 -X GET "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}/latest" \
        -H "X-Master-Key: ${JSONBIN_API_KEY}" 2>&1) || {
        log "⚠️ curl download failed or timed out"
        rm -f "${STATE_FILE}"
        return 1
    }

    if echo "$RESPONSE" | jq -e '.record' > /dev/null 2>&1; then
        log "📦 Extracting state data..."
        echo "$RESPONSE" | jq -r '.record' > "${STATE_FILE}"
        
        if validate_state "${STATE_FILE}"; then
            local size=$(wc -c < "${STATE_FILE}")
            local block=$(jq -r '.block' "${STATE_FILE}" 2>/dev/null || echo "unknown")
            log "✅ State loaded successfully!"
            log "   - File size: ${size} bytes"
            log "   - Block number: ${block}"
            return 0
        else
            log "⚠️ Downloaded state is invalid"
            rm -f "${STATE_FILE}"
            return 1
        fi
    else
        log "⚠️ No valid state found in JSONBin"
        rm -f "${STATE_FILE}"
        return 1
    fi
}

if download_state; then
    STATE_LOADED="yes"
    log "🎯 State successfully loaded - all balances preserved"
else
    STATE_LOADED="no"
    log "🆕 Starting fresh (no previous state)"
fi

# -------------------------------------------------------------------
# Upload state to JSONBin
upload_state() {
    log "📤 Uploading state to JSONBin.io..."
    
    if [ -z "${JSONBIN_BIN_ID}" ] || [ -z "${JSONBIN_API_KEY}" ]; then
        log "⚠️ Credentials not set. Skipping upload."
        return 1
    fi

    if [ ! -f "${STATE_FILE}" ] || ! validate_state "${STATE_FILE}"; then
        log "⚠️ No valid state file to upload"
        return 1
    fi

    STATE_CONTENT=$(cat "${STATE_FILE}")
    local block=$(jq -r '.block' "${STATE_FILE}" 2>/dev/null || echo "unknown")
    local size=$(wc -c < "${STATE_FILE}")
    
    RESPONSE=$(curl -s --max-time 30 -X PUT "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}" \
        -H "Content-Type: application/json" \
        -H "X-Master-Key: ${JSONBIN_API_KEY}" \
        -d "{\"record\": ${STATE_CONTENT}}" 2>&1) || {
        log "⚠️ curl upload failed"
        return 1
    }

    if echo "$RESPONSE" | jq -e '.record' > /dev/null 2>&1; then
        log "✅ State uploaded successfully!"
        return 0
    else
        log "❌ Upload failed"
        return 1
    fi
}

# -------------------------------------------------------------------
# Periodic upload
periodic_upload() {
    local count=0
    while true; do
        sleep 60
        count=$((count + 1))
        log "⏰ Periodic upload #${count} triggered..."
        upload_state
    done
}

# -------------------------------------------------------------------
# PHASE 2: REGISTER CONTAINER
# -------------------------------------------------------------------
log "========================================="
log "🟢 PHASE 2: REGISTERING CONTAINER IMAGE"
log "========================================="
log "📦 Configuration:"
log "   - Chain ID: ${CHAIN_ID}"
log "   - Port: ${PORT}"
log "   - State loaded: ${STATE_LOADED}"
log "   - Mode: PRESERVE ALL BALANCES"
log "✅ Container registered"

# -------------------------------------------------------------------
# PHASE 3: LAUNCH ANVIL
# -------------------------------------------------------------------
log "========================================="
log "🚀 PHASE 3: LAUNCHING ANVIL NODE"
log "========================================="

CMD="anvil --fork-url ${FORK_URL} --chain-id ${CHAIN_ID} --host 0.0.0.0 --port ${PORT}"

if [ "${STATE_LOADED}" = "yes" ] && [ -f "${STATE_FILE}" ]; then
    CMD="${CMD} --state ${STATE_FILE}"
    log "📂 Launching with persisted state"
else
    log "🆕 Launching with fresh state"
fi

log "🔧 Command: ${CMD}"
$CMD &
ANVIL_PID=$!
log "✅ Anvil started (PID: ${ANVIL_PID})"

# -------------------------------------------------------------------
# PHASE 4: RESTORE IMPERSONATION ONLY (NO BALANCE CHANGES!)
# -------------------------------------------------------------------
log "========================================="
log "🟣 PHASE 4: RESTORING WALLET ACCESS ONLY"
log "========================================="
log "⏳ Waiting for Anvil to be ready..."
log "⚠️  IMPORTANT: Only restoring impersonation, NOT changing balances!"

sleep 5

# Check if Anvil is ready
RETRY=0
MAX_RETRIES=12
while [ $RETRY -lt $MAX_RETRIES ]; do
    if curl -s -X POST "http://localhost:${PORT}" \
        -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        | jq -e '.result' > /dev/null 2>&1; then
        log "✅ Anvil RPC is ready"
        break
    fi
    RETRY=$((RETRY + 1))
    log "⏳ Waiting... (${RETRY}/${MAX_RETRIES})"
    sleep 5
done

if [ $RETRY -ge $MAX_RETRIES ]; then
    log "❌ Anvil failed to start properly"
    exit 1
fi

# RPC helper
rpc_call() {
    local method=$1
    local params=$2
    curl -s -X POST "http://localhost:${PORT}" \
        -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"${method}\",\"params\":${params},\"id\":1}"
}

# Restore impersonation ONLY
log "👤 Restoring wallet impersonation..."
rpc_call "anvil_impersonateAccount" "[\"${MY_WALLET}\"]" > /dev/null 2>&1 && \
    log "✅ Wallet access restored: ${MY_WALLET}" || \
    log "⚠️ Failed to impersonate wallet"

log "🐋 Restoring whale impersonation..."
rpc_call "anvil_impersonateAccount" "[\"${USDT_WHALE}\"]" > /dev/null 2>&1 && \
    log "✅ Whale access restored: ${USDT_WHALE}" || \
    log "⚠️ Failed to impersonate whale"

log "🔒 NO BALANCES WERE MODIFIED - All state preserved exactly as saved"

# -------------------------------------------------------------------
# PHASE 5: START SYNC SERVICE
# -------------------------------------------------------------------
log "========================================="
log "🟡 PHASE 5: STARTING BACKGROUND SYNC"
log "========================================="

trap 'log "⚠️ Container stopping, uploading final state..."; upload_state; log "👋 Shutdown complete"; exit 0' SIGTERM SIGINT

periodic_upload &
log "✅ State sync active (every 60s)"

# -------------------------------------------------------------------
# DONE
# -------------------------------------------------------------------
log "========================================="
log "🎯 SETUP COMPLETE"
log "========================================="
log "📡 RPC: https://anvil-render-q5wl.onrender.com"
log "👛 Wallet: ${MY_WALLET}"
log "🔒 All balances preserved from state"
log "========================================="

wait $ANVIL_PID
