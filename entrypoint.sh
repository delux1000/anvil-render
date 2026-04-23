#!/bin/bash

# -------------------------------------------------------------------
# Anvil + JSONBin.io Persistence (BALANCE PERSISTENCE FIX)
# Saves wallet balances separately and restores them after restart
# -------------------------------------------------------------------

# Hardcoded configuration
JSONBIN_BIN_ID="6936f28bae596e708f8bafc0"
JSONBIN_API_KEY='$2a$10$aAW84k1Q4lfQR8ELHBneT.01Go2JevCCoay/TR4AATTeNpTd7ou9K'
FORK_URL="https://eth-mainnet.g.alchemy.com/v2/QFjExKnnaI2I4qTV7EFM7WwB0gl08X0n"
CHAIN_ID="1"
PORT="8545"
STATE_FILE="/tmp/state.json"
BALANCES_FILE="/tmp/balances.json"

# -------------------------------------------------------------------
# Logging
LOG_FILE="/tmp/anvil-jsonbin.log"
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# RPC helper
rpc() {
    curl -s -X POST "http://localhost:${PORT}" \
        -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"$1\",\"params\":$2,\"id\":1}"
}

log "========================================="
log "🔷 ANVIL PERSISTENCE (BALANCE FIX)"
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
# Download state + balances from JSONBin
# -------------------------------------------------------------------
log "📥 Downloading previous state..."

# Download state
STATE_RESPONSE=$(curl -s --max-time 30 \
    "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}/latest" \
    -H "X-Master-Key: ${JSONBIN_API_KEY}")

if echo "$STATE_RESPONSE" | jq -e '.record' > /dev/null 2>&1; then
    # Extract the full record
    echo "$STATE_RESPONSE" | jq -r '.record' > /tmp/full_record.json
    
    # Check if it contains both state and balances
    if jq -e '.state' /tmp/full_record.json > /dev/null 2>&1; then
        # New format: separate state and balances
        jq -r '.state' /tmp/full_record.json > "${STATE_FILE}"
        jq -r '.balances' /tmp/full_record.json > "${BALANCES_FILE}"
        STATE_LOADED="yes"
        log "✅ State + balances loaded"
        BALANCE_COUNT=$(jq 'length' "${BALANCES_FILE}" 2>/dev/null || echo "0")
        log "👛 Saved balances: ${BALANCE_COUNT} wallets"
    elif jq -e '.block' /tmp/full_record.json > /dev/null 2>&1; then
        # Old format: just state
        cp /tmp/full_record.json "${STATE_FILE}"
        echo '{}' > "${BALANCES_FILE}"
        STATE_LOADED="yes"
        log "✅ State loaded (old format, no saved balances)"
    else
        STATE_LOADED="no"
        echo '{}' > "${BALANCES_FILE}"
        log "⚠️ Unknown format"
    fi
else
    STATE_LOADED="no"
    echo '{}' > "${BALANCES_FILE}"
    log "🆕 Fresh start"
fi

# -------------------------------------------------------------------
# Upload state + balances to JSONBin
# -------------------------------------------------------------------
upload_all() {
    log "💾 Saving state + balances..."
    
    # Wait for Anvil
    sleep 1
    
    # Get current state file (written by Anvil's --state flag)
    if [ ! -f "${STATE_FILE}" ]; then
        log "⚠️ No state file"
        return 1
    fi
    
    STATE_CONTENT=$(cat "${STATE_FILE}")
    
    # Collect all wallet balances we care about
    echo '{' > "${BALANCES_FILE}"
    FIRST=true
    
    # Get all addresses from state file
    ADDRESSES=$(jq -r '.accounts | keys[]' "${STATE_FILE}" 2>/dev/null)
    
    for ADDR in $ADDRESSES; do
        # Get ETH balance
        ETH_BAL=$(rpc "eth_getBalance" "[\"${ADDR}\",\"latest\"]" | jq -r '.result // "0x0"')
        
        # Skip zero balances
        if [ "$ETH_BAL" != "0x0" ] && [ "$ETH_BAL" != "0x" ]; then
            if [ "$FIRST" = true ]; then
                FIRST=false
            else
                echo ',' >> "${BALANCES_FILE}"
            fi
            echo "\"${ADDR}\":{\"eth\":\"${ETH_BAL}\"}" >> "${BALANCES_FILE}"
        fi
    done
    echo '}' >> "${BALANCES_FILE}"
    
    BALANCE_COUNT=$(jq 'length' "${BALANCES_FILE}" 2>/dev/null || echo "0")
    log "   Collected ${BALANCE_COUNT} non-zero ETH balances"
    
    # Combine state and balances into one record
    COMBINED=$(jq -n --argfile state "${STATE_FILE}" --argfile balances "${BALANCES_FILE}" \
        '{state: $state, balances: $balances}')
    
    # Upload
    RESPONSE=$(curl -s --max-time 30 -X PUT \
        "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}" \
        -H "Content-Type: application/json" \
        -H "X-Master-Key: ${JSONBIN_API_KEY}" \
        -d "{\"record\": ${COMBINED}}")
    
    if echo "$RESPONSE" | jq -e '.record' > /dev/null 2>&1; then
        log "✅ Uploaded state + ${BALANCE_COUNT} balances"
        return 0
    else
        log "❌ Upload failed"
        return 1
    fi
}

# -------------------------------------------------------------------
# Restore balances after restart
# -------------------------------------------------------------------
restore_balances() {
    if [ ! -f "${BALANCES_FILE}" ] || [ ! -s "${BALANCES_FILE}" ]; then
        log "   No saved balances to restore"
        return
    fi
    
    log "🔄 Restoring saved balances..."
    
    WALLETS=$(jq -r 'keys[]' "${BALANCES_FILE}" 2>/dev/null)
    RESTORED=0
    
    for ADDR in $WALLETS; do
        ETH_BAL=$(jq -r ".\"${ADDR}\".eth" "${BALANCES_FILE}" 2>/dev/null)
        
        if [ -n "$ETH_BAL" ] && [ "$ETH_BAL" != "null" ] && [ "$ETH_BAL" != "0x0" ]; then
            # Set the balance using anvil_setBalance
            RESULT=$(rpc "anvil_setBalance" "[\"${ADDR}\",\"${ETH_BAL}\"]")
            
            if echo "$RESULT" | jq -e '.result == null' > /dev/null 2>&1; then
                RESTORED=$((RESTORED + 1))
                log "   ✅ Restored ${ADDR:0:10}...${ADDR: -6}: ${ETH_BAL}"
            fi
        fi
    done
    
    log "🎯 Restored ${RESTORED} wallet balances"
}

# -------------------------------------------------------------------
# Monitor and upload after each transaction
# -------------------------------------------------------------------
monitor_and_save() {
    log "👁️  Monitoring transactions..."
    
    LAST_BLOCK="0x0"
    
    while true; do
        CURRENT_BLOCK=$(rpc "eth_blockNumber" "[]" | jq -r '.result // "0x0"')
        
        if [ "$CURRENT_BLOCK" != "$LAST_BLOCK" ] && [ "$CURRENT_BLOCK" != "0x0" ]; then
            log "🔔 New block: ${LAST_BLOCK} → ${CURRENT_BLOCK}"
            upload_all
            LAST_BLOCK="$CURRENT_BLOCK"
        fi
        
        sleep 2
    done
}

# -------------------------------------------------------------------
# Shutdown
# -------------------------------------------------------------------
graceful_shutdown() {
    log "⚠️ Shutdown..."
    upload_all
    log "👋 Done"
    exit 0
}

# -------------------------------------------------------------------
# PHASE 2: LAUNCH ANVIL
# -------------------------------------------------------------------
log "========================================="
log "🚀 LAUNCHING ANVIL"
log "========================================="

CMD="anvil --fork-url ${FORK_URL} --chain-id ${CHAIN_ID} --host 0.0.0.0 --port ${PORT} --state ${STATE_FILE} --state-interval 1"

if [ "${STATE_LOADED}" = "yes" ]; then
    log "📂 Using persisted state"
else
    log "🆕 Fresh start"
fi

$CMD &
ANVIL_PID=$!
log "✅ Anvil PID: ${ANVIL_PID}"

# -------------------------------------------------------------------
# PHASE 3: WAIT + RESTORE BALANCES
# -------------------------------------------------------------------
log "⏳ Waiting for Anvil..."
sleep 5

for i in $(seq 1 20); do
    if rpc "eth_blockNumber" "[]" | jq -e '.result' > /dev/null 2>&1; then
        log "✅ Anvil ready"
        break
    fi
    sleep 2
done

# 🔥 RESTORE SAVED BALANCES 🔥
restore_balances

# -------------------------------------------------------------------
# PHASE 4: START MONITORING
# -------------------------------------------------------------------
log "========================================="
log "🟢 STARTING MONITOR"
log "========================================="

trap graceful_shutdown SIGTERM SIGINT

sleep 2
upload_all

monitor_and_save &
MONITOR_PID=$!

log "========================================="
log "🎯 SYSTEM READY"
log "========================================="
log "📡 RPC: https://anvil-render-q5wl.onrender.com"
log "💾 Balances saved + restored every restart"
log "🔒 All wallets protected"
log "========================================="

wait $ANVIL_PID
