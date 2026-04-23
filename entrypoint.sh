#!/bin/bash

# -------------------------------------------------------------------
# Anvil STANDALONE Chain + JSONBin Persistence
# NO FORK - Pure standalone chain
# ALL balances are native and WILL survive restarts
# -------------------------------------------------------------------

JSONBIN_BIN_ID="6936f28bae596e708f8bafc0"
JSONBIN_API_KEY='$2a$10$aAW84k1Q4lfQR8ELHBneT.01Go2JevCCoay/TR4AATTeNpTd7ou9K'
CHAIN_ID="1"
PORT="8545"
STATE_FILE="/tmp/state.json"

LOG_FILE="/tmp/anvil-jsonbin.log"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"; }

log "========================================="
log "🔷 STANDALONE CHAIN (NO FORK)"
log "========================================="

for cmd in curl jq anvil; do
    command -v $cmd >/dev/null 2>&1 || { log "❌ Missing: $cmd"; exit 1; }
done

# -------------------------------------------------------------------
# DOWNLOAD STATE
# -------------------------------------------------------------------
log "📥 Downloading state..."

RESPONSE=$(curl -s --max-time 30 \
    "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}/latest" \
    -H "X-Master-Key: ${JSONBIN_API_KEY}")

if echo "$RESPONSE" | jq -e '.record' > /dev/null 2>&1; then
    RECORD=$(echo "$RESPONSE" | jq -r '.record')
    
    # Handle nested record
    if echo "$RECORD" | jq -e '.block' > /dev/null 2>&1; then
        echo "$RECORD" > "${STATE_FILE}"
    elif echo "$RECORD" | jq -e '.record.block' > /dev/null 2>&1; then
        echo "$RECORD" | jq -r '.record' > "${STATE_FILE}"
    fi
    
    if [ -f "${STATE_FILE}" ] && jq -e '.block' "${STATE_FILE}" > /dev/null 2>&1; then
        STATE_LOADED="yes"
        BLOCK=$(jq -r '.block.number // .block' "${STATE_FILE}")
        ACCOUNTS=$(jq '.accounts | keys | length' "${STATE_FILE}")
        log "✅ State loaded - Block: ${BLOCK}, Accounts: ${ACCOUNTS}"
    else
        rm -f "${STATE_FILE}"
        STATE_LOADED="no"
    fi
else
    STATE_LOADED="no"
fi

# -------------------------------------------------------------------
# UPLOAD STATE
# -------------------------------------------------------------------
upload_state() {
    if [ ! -f "${STATE_FILE}" ]; then
        log "⚠️ No state file"
        return 1
    fi
    
    STATE_CONTENT=$(cat "${STATE_FILE}")
    
    curl -s --max-time 30 -X PUT \
        "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}" \
        -H "Content-Type: application/json" \
        -H "X-Master-Key: ${JSONBIN_API_KEY}" \
        -d "{\"record\": ${STATE_CONTENT}}" > /dev/null
    
    BLOCK=$(jq -r '.block.number // .block' "${STATE_FILE}" 2>/dev/null || echo "?")
    ACCOUNTS=$(jq '.accounts | keys | length' "${STATE_FILE}" 2>/dev/null || echo "0")
    log "✅ Uploaded - Block: ${BLOCK}, Accounts: ${ACCOUNTS}"
}

# -------------------------------------------------------------------
# MONITOR & AUTO-SAVE
# -------------------------------------------------------------------
LAST_BLOCK="0x0"
monitor() {
    while true; do
        CURRENT=$(curl -s -X POST "http://localhost:${PORT}" \
            -H 'Content-Type: application/json' \
            --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            | jq -r '.result // "0x0"')
        
        if [ "$CURRENT" != "$LAST_BLOCK" ] && [ "$CURRENT" != "0x0" ]; then
            log "🔔 Block: ${LAST_BLOCK} → ${CURRENT}"
            upload_state
            LAST_BLOCK="$CURRENT"
        fi
        sleep 2
    done
}

shutdown() {
    log "💾 Final save..."
    upload_state
    log "👋 Done"
    exit 0
}

# -------------------------------------------------------------------
# LAUNCH ANVIL - NO FORK!
# -------------------------------------------------------------------
log "🚀 Launching standalone chain..."

CMD="anvil --chain-id ${CHAIN_ID} --host 0.0.0.0 --port ${PORT} --state ${STATE_FILE}"

if [ "${STATE_LOADED}" = "yes" ] && [ -f "${STATE_FILE}" ]; then
    log "📂 Resuming from saved state"
else
    log "🆕 Fresh chain"
fi

$CMD &
ANVIL_PID=$!
log "✅ PID: ${ANVIL_PID}"

# Wait for ready
sleep 3
for i in $(seq 1 15); do
    curl -s -X POST "http://localhost:${PORT}" \
        -H 'Content-Type: application/json' \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        | jq -e '.result' > /dev/null 2>&1 && break
    sleep 2
done

# -------------------------------------------------------------------
# SHOW ACCOUNTS
# -------------------------------------------------------------------
log "========================================="
log "🎁 DEFAULT ACCOUNTS (10,000 ETH each):"
log ""

ACCOUNTS=$(curl -s -X POST "http://localhost:${PORT}" \
    -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","method":"eth_accounts","params":[],"id":1}' | jq -r '.result[]')

for ADDR in $ACCOUNTS; do
    BAL=$(curl -s -X POST "http://localhost:${PORT}" \
        -H 'Content-Type: application/json' \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"${ADDR}\",\"latest\"],\"id\":1}" | jq -r '.result')
    log "   ${ADDR}: ${BAL}"
done

# -------------------------------------------------------------------
# START SYNC
# -------------------------------------------------------------------
trap shutdown SIGTERM SIGINT
sleep 2
upload_state
monitor &

log "========================================="
log "🎯 READY"
log "========================================="
log "📡 RPC: https://anvil-render-q5wl.onrender.com"
log "⛓️  Chain ID: ${CHAIN_ID}"
log "🆓 No fork - pure standalone"
log "🔒 ALL balances SURVIVE restarts"
log "========================================="

wait $ANVIL_PID
