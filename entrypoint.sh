#!/bin/bash

# -------------------------------------------------------------------
# Anvil + JSONBin.io Persistence Entrypoint (INSTANT UPLOAD - FIXED)
# Uploads state to JSONBin after EVERY transaction
# -------------------------------------------------------------------

# Hardcoded configuration
JSONBIN_BIN_ID="6936f28bae596e708f8bafc0"
JSONBIN_API_KEY='$2a$10$aAW84k1Q4lfQR8ELHBneT.01Go2JevCCoay/TR4AATTeNpTd7ou9K'
FORK_URL="https://eth-mainnet.g.alchemy.com/v2/QFjExKnnaI2I4qTV7EFM7WwB0gl08X0n"
CHAIN_ID="1"
PORT="8545"
STATE_FILE="/tmp/state.json"

# -------------------------------------------------------------------
# Logging
LOG_FILE="/tmp/anvil-jsonbin.log"
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log "========================================="
log "🔷 ANVIL PERSISTENCE (INSTANT UPLOAD)"
log "========================================="

# Check dependencies
for cmd in curl jq anvil; do
    if ! command -v $cmd >/dev/null 2>&1; then
        log "❌ Missing: $cmd"
        exit 1
    fi
done
log "✅ Dependencies OK"

# -------------------------------------------------------------------
# Validate state file
validate_state() {
    [ -f "$1" ] && jq -e '.block' "$1" > /dev/null 2>&1
}

# -------------------------------------------------------------------
# PHASE 1: DOWNLOAD STATE
# -------------------------------------------------------------------
log "📥 Downloading previous state..."
RESPONSE=$(curl -s --max-time 30 \
    "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}/latest" \
    -H "X-Master-Key: ${JSONBIN_API_KEY}")

if echo "$RESPONSE" | jq -e '.record' > /dev/null 2>&1; then
    echo "$RESPONSE" | jq -r '.record' > "${STATE_FILE}"
    if validate_state "${STATE_FILE}"; then
        STATE_LOADED="yes"
        SIZE=$(wc -c < "${STATE_FILE}")
        BLOCK=$(jq -r '.block.number // .block' "${STATE_FILE}" 2>/dev/null || echo "?")
        WALLET_COUNT=$(jq '.accounts | keys | length' "${STATE_FILE}" 2>/dev/null || echo "0")
        log "✅ State loaded (Block: ${BLOCK}, Size: ${SIZE} bytes, ${WALLET_COUNT} wallets)"
    else
        rm -f "${STATE_FILE}"
        STATE_LOADED="no"
        log "⚠️ State invalid - starting fresh"
    fi
else
    STATE_LOADED="no"
    log "🆕 No previous state"
fi

# -------------------------------------------------------------------
# Upload to JSONBin
# -------------------------------------------------------------------
upload_state() {
    if [ ! -f "${STATE_FILE}" ] || ! validate_state "${STATE_FILE}"; then
        log "⚠️ No valid state file to upload"
        return 1
    fi
    
    STATE_CONTENT=$(cat "${STATE_FILE}")
    SIZE=$(wc -c < "${STATE_FILE}")
    ACCOUNTS=$(jq '.accounts | keys | length' "${STATE_FILE}" 2>/dev/null || echo "0")
    
    RESPONSE=$(curl -s --max-time 30 -X PUT \
        "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}" \
        -H "Content-Type: application/json" \
        -H "X-Master-Key: ${JSONBIN_API_KEY}" \
        -d "{\"record\": ${STATE_CONTENT}}")
    
    if echo "$RESPONSE" | jq -e '.record' > /dev/null 2>&1; then
        log "✅ Uploaded (${SIZE} bytes, ${ACCOUNTS} wallets)"
        return 0
    else
        log "❌ Upload failed"
        return 1
    fi
}

# -------------------------------------------------------------------
# Monitor transactions and upload after each one
# -------------------------------------------------------------------
monitor_and_save() {
    log "👁️  Monitoring transactions (checks every 2s)..."
    
    LAST_BLOCK="0x0"
    
    while true; do
        # Get current block from Anvil
        CURRENT_BLOCK=$(curl -s -X POST "http://localhost:${PORT}" \
            -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            | jq -r '.result // "0x0"')
        
        # If block changed, upload the state
        if [ "$CURRENT_BLOCK" != "$LAST_BLOCK" ] && [ "$CURRENT_BLOCK" != "0x0" ]; then
            log "🔔 New block: ${LAST_BLOCK} → ${CURRENT_BLOCK}"
            log "💾 Uploading state..."
            upload_state
            LAST_BLOCK="$CURRENT_BLOCK"
        fi
        
        sleep 2
    done
}

# -------------------------------------------------------------------
# Shutdown handler
# -------------------------------------------------------------------
graceful_shutdown() {
    log "⚠️ Shutdown..."
    log "💾 Final upload..."
    upload_state
    log "👋 Done"
    exit 0
}

# -------------------------------------------------------------------
# PHASE 2: LAUNCH ANVIL
# -------------------------------------------------------------------
log "========================================="
log "🚀 LAUNCHING ANVIL"
log "========================================="

# Build command with --state and --state-interval for frequent saves
CMD="anvil"
CMD="${CMD} --fork-url ${FORK_URL}"
CMD="${CMD} --chain-id ${CHAIN_ID}"
CMD="${CMD} --host 0.0.0.0"
CMD="${CMD} --port ${PORT}"
CMD="${CMD} --state ${STATE_FILE}"
CMD="${CMD} --state-interval 1"  # Write state to disk every 1 second!

if [ "${STATE_LOADED}" = "yes" ]; then
    log "📂 Launching with persisted state"
else
    log "🆕 Launching fresh"
fi

log "🔧 ${CMD}"
$CMD &
ANVIL_PID=$!
log "✅ Anvil PID: ${ANVIL_PID}"

# -------------------------------------------------------------------
# PHASE 3: WAIT & START MONITORING
# -------------------------------------------------------------------
log "⏳ Waiting for Anvil..."
sleep 3

for i in $(seq 1 20); do
    if curl -s -X POST "http://localhost:${PORT}" \
        -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        | jq -e '.result' > /dev/null 2>&1; then
        log "✅ Anvil ready"
        break
    fi
    sleep 2
done

# -------------------------------------------------------------------
# PHASE 4: START SERVICES
# -------------------------------------------------------------------
log "========================================="
log "🟢 STARTING MONITOR"
log "========================================="

trap graceful_shutdown SIGTERM SIGINT

# Initial upload
log "💾 Initial state upload..."
sleep 2  # Let Anvil write first state
upload_state

# Start monitoring
monitor_and_save &
MONITOR_PID=$!

log "========================================="
log "🎯 SYSTEM READY"
log "========================================="
log "📡 RPC: https://anvil-render-q5wl.onrender.com"
log "💾 State: Saved after every transaction"
log "🔒 All balances preserved"
log "========================================="

wait $ANVIL_PID
