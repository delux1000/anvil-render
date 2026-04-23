#!/bin/bash

# -------------------------------------------------------------------
# Anvil + JSONBin.io Persistence Entrypoint (ALL WALLETS VERSION)
# Preserves balances for EVERY address after restart
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
log "🔷 ANVIL PERSISTENCE (ALL WALLETS)"
log "========================================="

# Check dependencies (no bc needed!)
for cmd in curl jq anvil; do
    if ! command -v $cmd >/dev/null 2>&1; then
        log "❌ Missing: $cmd"
        exit 1
    fi
done
log "✅ Dependencies OK (curl, jq, anvil)"

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
        log "✅ State loaded (Block: ${BLOCK}, Size: ${SIZE} bytes)"
        
        WALLET_COUNT=$(jq '.accounts | keys | length' "${STATE_FILE}" 2>/dev/null || echo "0")
        log "👛 Wallets in state: ${WALLET_COUNT}"
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
# Upload with verification
upload_state() {
    if [ ! -f "${STATE_FILE}" ] || ! validate_state "${STATE_FILE}"; then
        log "⚠️ Upload skipped - no valid state"
        return 1
    fi
    
    STATE_CONTENT=$(cat "${STATE_FILE}")
    
    RESPONSE=$(curl -s --max-time 30 -X PUT \
        "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}" \
        -H "Content-Type: application/json" \
        -H "X-Master-Key: ${JSONBIN_API_KEY}" \
        -d "{\"record\": ${STATE_CONTENT}}")
    
    if echo "$RESPONSE" | jq -e '.record' > /dev/null 2>&1; then
        log "✅ State uploaded"
        return 0
    else
        log "❌ Upload failed"
        return 1
    fi
}

# -------------------------------------------------------------------
# Touch all wallets to force into state
# -------------------------------------------------------------------
touch_all_wallets() {
    log "========================================="
    log "🟣 FORCING ALL WALLETS INTO STATE"
    log "========================================="
    
    # Wait for Anvil to be ready
    for i in $(seq 1 15); do
        curl -s -X POST "http://localhost:${PORT}" \
            -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            | jq -e '.result' > /dev/null 2>&1 && break
        sleep 2
    done
    
    # RPC helper
    rpc() {
        curl -s -X POST "http://localhost:${PORT}" \
            -H "Content-Type: application/json" \
            --data "{\"jsonrpc\":\"2.0\",\"method\":\"$1\",\"params\":$2,\"id\":1}"
    }
    
    if [ -f "${STATE_FILE}" ] && [ "${STATE_LOADED}" = "yes" ]; then
        log "📋 Reading wallets from state file..."
        
        ADDRESSES=$(jq -r '.accounts | keys[]' "${STATE_FILE}" 2>/dev/null)
        
        if [ -z "$ADDRESSES" ]; then
            log "⚠️ No addresses in state file to touch"
            return
        fi
        
        TOUCHED=0
        for ADDR in $ADDRESSES; do
            # Impersonate each wallet
            rpc "anvil_impersonateAccount" "[\"${ADDR}\"]" > /dev/null 2>&1
            
            # Send 0 ETH to self (forces into Anvil's active state)
            TX_RESULT=$(rpc "eth_sendTransaction" "[{\"from\":\"${ADDR}\",\"to\":\"${ADDR}\",\"value\":\"0x0\"}]")
            
            if echo "$TX_RESULT" | jq -e '.result' > /dev/null 2>&1; then
                TOUCHED=$((TOUCHED + 1))
                log "   ✅ Touched: ${ADDR:0:10}...${ADDR: -6}"
            else
                log "   ⚠️ Failed: ${ADDR:0:10}...${ADDR: -6}"
            fi
        done
        
        log "🎯 Touched ${TOUCHED} wallets - will persist after restart"
    else
        log "🆕 No previous wallets"
    fi
}

# -------------------------------------------------------------------
# Periodic sync
# -------------------------------------------------------------------
SYNC_COUNT=0
touch_before_sync() {
    SYNC_COUNT=$((SYNC_COUNT + 1))
    log "⏰ Sync #${SYNC_COUNT}..."
    
    if [ -f "${STATE_FILE}" ]; then
        ADDRESSES=$(jq -r '.accounts | keys[]' "${STATE_FILE}" 2>/dev/null)
        for ADDR in $ADDRESSES; do
            curl -s -X POST "http://localhost:${PORT}" \
                -H "Content-Type: application/json" \
                --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_sendTransaction\",\"params\":[{\"from\":\"${ADDR}\",\"to\":\"${ADDR}\",\"value\":\"0x0\"}],\"id\":1}" > /dev/null 2>&1
        done
    fi
    
    upload_state
}

periodic_sync() {
    while true; do
        sleep 60
        touch_before_sync
    done
}

# -------------------------------------------------------------------
# PHASE 2: LAUNCH ANVIL
# -------------------------------------------------------------------
log "========================================="
log "🚀 LAUNCHING ANVIL"
log "========================================="

CMD="anvil --fork-url ${FORK_URL} --chain-id ${CHAIN_ID} --host 0.0.0.0 --port ${PORT}"
[ "${STATE_LOADED}" = "yes" ] && [ -f "${STATE_FILE}" ] && \
    CMD="${CMD} --state ${STATE_FILE}" && \
    log "📂 Using persisted state"

$CMD &
ANVIL_PID=$!
log "✅ Anvil PID: ${ANVIL_PID}"

# -------------------------------------------------------------------
# PHASE 3: TOUCH ALL WALLETS
# -------------------------------------------------------------------
touch_all_wallets

# -------------------------------------------------------------------
# PHASE 4: START SYNC
# -------------------------------------------------------------------
log "========================================="
log "🟡 STARTING AUTO-SYNC"
log "========================================="

trap 'log "⚠️ Shutdown..."; touch_before_sync; log "👋 Done"; exit 0' SIGTERM SIGINT

periodic_sync &
log "✅ Syncing every 60 seconds"

# -------------------------------------------------------------------
# DONE
# -------------------------------------------------------------------
log "========================================="
log "🎯 ALL WALLETS PROTECTED"
log "========================================="
log "📡 RPC: https://anvil-render-q5wl.onrender.com"
log "🔒 All wallet balances survive restarts"
log "========================================="

wait $ANVIL_PID
