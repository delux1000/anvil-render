#!/bin/bash

# -------------------------------------------------------------------
# SIMPLE STANDALONE ANVIL - NO FORK - WILL WORK
# -------------------------------------------------------------------

JSONBIN_BIN_ID="6936f28bae596e708f8bafc0"
JSONBIN_API_KEY='$2a$10$aAW84k1Q4lfQR8ELHBneT.01Go2JevCCoay/TR4AATTeNpTd7ou9K'
CHAIN_ID="1"
PORT="8545"
STATE_FILE="/tmp/state.json"

LOG_FILE="/tmp/anvil-jsonbin.log"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"; }

log "========================================="
log "🔷 SIMPLE STANDALONE CHAIN"
log "========================================="

# Check deps
command -v anvil >/dev/null 2>&1 || { log "❌ Missing anvil"; exit 1; }
command -v curl >/dev/null 2>&1 || { log "❌ Missing curl"; exit 1; }
command -v jq >/dev/null 2>&1 || { log "❌ Missing jq"; exit 1; }

# -------------------------------------------------------------------
# Download state
# -------------------------------------------------------------------
log "📥 Checking for saved state..."

RESPONSE=$(curl -s --max-time 30 \
    "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}/latest" \
    -H "X-Master-Key: ${JSONBIN_API_KEY}")

STATE_LOADED="no"

if echo "$RESPONSE" | jq -e '.record.record.block' > /dev/null 2>&1; then
    echo "$RESPONSE" | jq -r '.record.record' > "${STATE_FILE}"
    if jq -e '.block' "${STATE_FILE}" > /dev/null 2>&1; then
        STATE_LOADED="yes"
        log "✅ State found"
    fi
elif echo "$RESPONSE" | jq -e '.record.block' > /dev/null 2>&1; then
    echo "$RESPONSE" | jq -r '.record' > "${STATE_FILE}"
    if jq -e '.block' "${STATE_FILE}" > /dev/null 2>&1; then
        STATE_LOADED="yes"
        log "✅ State found"
    fi
fi

if [ "$STATE_LOADED" = "no" ]; then
    rm -f "${STATE_FILE}"
    log "🆕 Fresh chain"
fi

# -------------------------------------------------------------------
# Upload state
# -------------------------------------------------------------------
upload_state() {
    if [ -f "${STATE_FILE}" ] && jq -e '.block' "${STATE_FILE}" > /dev/null 2>&1; then
        STATE_CONTENT=$(cat "${STATE_FILE}")
        curl -s --max-time 30 -X PUT \
            "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}" \
            -H "Content-Type: application/json" \
            -H "X-Master-Key: ${JSONBIN_API_KEY}" \
            -d "{\"record\": ${STATE_CONTENT}}" > /dev/null
        log "✅ State saved"
    fi
}

# -------------------------------------------------------------------
# Launch Anvil
# -------------------------------------------------------------------
log "🚀 Starting Anvil..."

CMD="anvil --chain-id ${CHAIN_ID} --host 0.0.0.0 --port ${PORT}"

if [ "$STATE_LOADED" = "yes" ] && [ -f "${STATE_FILE}" ]; then
    CMD="${CMD} --state ${STATE_FILE}"
    log "📂 With saved state"
else
    log "🆕 New chain"
fi

$CMD &
ANVIL_PID=$!

# Wait
sleep 5
for i in $(seq 1 15); do
    curl -s -X POST "http://localhost:${PORT}" \
        -H 'Content-Type: application/json' \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        | jq -e '.result' > /dev/null 2>&1 && break
    sleep 2
done

# -------------------------------------------------------------------
# Show accounts
# -------------------------------------------------------------------
log "========================================="
log "📋 AVAILABLE ACCOUNTS:"
log ""

ACCOUNTS_JSON=$(curl -s -X POST "http://localhost:${PORT}" \
    -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","method":"eth_accounts","params":[],"id":1}')

echo "$ACCOUNTS_JSON" | jq -r '.result[]' | while read ADDR; do
    BAL=$(curl -s -X POST "http://localhost:${PORT}" \
        -H 'Content-Type: application/json' \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"${ADDR}\",\"latest\"],\"id\":1}" \
        | jq -r '.result')
    log "   ${ADDR}"
    log "   Balance: ${BAL}"
    log ""
done

log "🔑 Private Key for Account #0:"
log "   0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
log ""

# -------------------------------------------------------------------
# Auto-save loop
# -------------------------------------------------------------------
LAST_BLOCK="0x0"

trap 'log "💾 Saving..."; upload_state; log "👋 Done"; exit 0' SIGTERM SIGINT

# Initial save
sleep 3
upload_state

log "========================================="
log "🎯 CHAIN IS LIVE"
log "========================================="
log "📡 RPC: https://anvil-render-q5wl.onrender.com"
log "⛓️  Chain ID: ${CHAIN_ID}"
log "========================================="

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
done &

wait $ANVIL_PID
