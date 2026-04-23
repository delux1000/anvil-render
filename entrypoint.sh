#!/bin/bash

# -------------------------------------------------------------------
# Anvil + JSONBin.io Persistence Entrypoint (INSTANT UPLOAD)
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
# Dump Anvil state to file using RPC
# -------------------------------------------------------------------
dump_state() {
    RESULT=$(curl -s -X POST "http://localhost:${PORT}" \
        -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"anvil_dumpState","params":["'${STATE_FILE}'"],"id":1}')
    
    if echo "$RESULT" | jq -e '.result == true' > /dev/null 2>&1; then
        if [ -f "${STATE_FILE}" ] && validate_state "${STATE_FILE}"; then
            return 0
        fi
    fi
    return 1
}

# -------------------------------------------------------------------
# Upload to JSONBin
# -------------------------------------------------------------------
upload_state() {
    if [ ! -f "${STATE_FILE}" ] || ! validate_state "${STATE_FILE}"; then
        log "⚠️ No valid state file to upload"
        return 1
    fi
    
    STATE_CONTENT=$(cat "${STATE_FILE}")
    
    RESPONSE=$(curl -s --max-time 30 -X PUT \
        "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}" \
        -H "Content-Type: application/json" \
        -H "X-Master-Key: ${JSONBIN_API_KEY}" \
        -d "{\"record\": ${STATE_CONTENT}}")
    
    if echo "$RESPONSE" | jq -e '.record' > /dev/null 2>&1; then
        local accounts=$(jq '.accounts | keys | length' "${STATE_FILE}" 2>/dev/null || echo "0")
        log "✅ State uploaded to JSONBin (${accounts} wallets)"
        return 0
    else
        log "❌ Upload failed"
        return 1
    fi
}

# -------------------------------------------------------------------
# Save state: dump + upload
# -------------------------------------------------------------------
save_state() {
    if dump_state; then
        upload_state
    else
        log "⚠️ State dump failed, skipping upload"
    fi
}

# -------------------------------------------------------------------
# Monitor transactions and save after each one
# -------------------------------------------------------------------
monitor_and_save() {
    log "👁️  Starting transaction monitor..."
    log "   State will be saved after EVERY transaction"
    
    LAST_BLOCK="0x0"
    
    while true; do
        # Get current block
        CURRENT_BLOCK=$(curl -s -X POST "http://localhost:${PORT}" \
            -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            | jq -r '.result // "0x0"')
        
        # Check if block changed
        if [ "$CURRENT_BLOCK" != "$LAST_BLOCK" ] && [ "$CURRENT_BLOCK" != "0x0" ]; then
            log "🔔 New block detected: ${CURRENT_BLOCK} (was ${LAST_BLOCK})"
            log "💾 Saving state to JSONBin..."
            save_state
            LAST_BLOCK="$CURRENT_BLOCK"
        fi
        
        sleep 2  # Check every 2 seconds
    done
}

# -------------------------------------------------------------------
# Also save on shutdown
# -------------------------------------------------------------------
graceful_shutdown() {
    log "⚠️ Shutdown signal received..."
    log "💾 Performing final state save..."
    save_state
    log "👋 Shutdown complete"
    exit 0
}

# -------------------------------------------------------------------
# PHASE 2: LAUNCH ANVIL
# -------------------------------------------------------------------
log "========================================="
log "🚀 LAUNCHING ANVIL"
log "========================================="

CMD="anvil --fork-url ${FORK_URL} --chain-id ${CHAIN_ID} --host 0.0.0.0 --port ${PORT}"

if [ "${STATE_LOADED}" = "yes" ] && [ -f "${STATE_FILE}" ]; then
    CMD="${CMD} --state ${STATE_FILE}"
    log "📂 Using persisted state"
else
    log "🆕 Fresh start"
fi

$CMD &
ANVIL_PID=$!
log "✅ Anvil PID: ${ANVIL_PID}"

# -------------------------------------------------------------------
# PHASE 3: WAIT FOR ANVIL
# -------------------------------------------------------------------
log "⏳ Waiting for Anvil to be ready..."
sleep 3

for i in $(seq 1 20); do
    if curl -s -X POST "http://localhost:${PORT}" \
        -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        | jq -e '.result' > /dev/null 2>&1; then
        log "✅ Anvil is ready"
        break
    fi
    sleep 2
done

# -------------------------------------------------------------------
# PHASE 4: START MONITORING & TRAP
# -------------------------------------------------------------------
log "========================================="
log "🟢 STARTING TRANSACTION MONITOR"
log "========================================="

trap graceful_shutdown SIGTERM SIGINT

# Initial save
log "💾 Performing initial state save..."
save_state

# Start monitoring for new transactions
monitor_and_save &
MONITOR_PID=$!

log "========================================="
log "🎯 SYSTEM READY"
log "========================================="
log "📡 RPC: https://anvil-render-q5wl.onrender.com"
log "💾 State: Saved after every transaction"
log "🔒 All wallet balances preserved"
log "========================================="

wait $ANVIL_PID
