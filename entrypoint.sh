#!/bin/bash

# -------------------------------------------------------------------
# Anvil Mainnet Fork + Balance Persistence
# USDT at 0xdAC17F958D2ee523a2206206994597C13D831ec7
# All balances survive restarts
# -------------------------------------------------------------------

JSONBIN_BIN_ID="6936f28bae596e708f8bafc0"
JSONBIN_API_KEY='$2a$10$aAW84k1Q4lfQR8ELHBneT.01Go2JevCCoay/TR4AATTeNpTd7ou9K'
FORK_URL="https://eth-mainnet.g.alchemy.com/v2/QFjExKnnaI2I4qTV7EFM7WwB0gl08X0n"
CHAIN_ID="1"
PORT="8545"
STATE_FILE="/tmp/state.json"
BALANCES_FILE="/tmp/balances.json"
USDT="0xdAC17F958D2ee523a2206206994597C13D831ec7"

LOG_FILE="/tmp/anvil-jsonbin.log"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"; }

rpc() {
    curl -s -X POST "http://localhost:${PORT}" \
        -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"$1\",\"params\":$2,\"id\":1}"
}

log "========================================="
log "🔷 ANVIL FORK + BALANCE PERSISTENCE"
log "========================================="

for cmd in curl jq anvil; do
    command -v $cmd >/dev/null 2>&1 || { log "❌ Missing: $cmd"; exit 1; }
done

# -------------------------------------------------------------------
# DOWNLOAD STATE + BALANCES
# -------------------------------------------------------------------
log "📥 Downloading saved data..."

RESPONSE=$(curl -s --max-time 30 \
    "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}/latest" \
    -H "X-Master-Key: ${JSONBIN_API_KEY}")

if echo "$RESPONSE" | jq -e '.record' > /dev/null 2>&1; then
    RECORD=$(echo "$RESPONSE" | jq -r '.record')
    
    # Check format
    if echo "$RECORD" | jq -e '.state' > /dev/null 2>&1; then
        # New format with separate state and balances
        echo "$RECORD" | jq -r '.state' > "${STATE_FILE}"
        echo "$RECORD" | jq -r '.balances' > "${BALANCES_FILE}"
        STATE_LOADED="yes"
        BAL_COUNT=$(jq 'length' "${BALANCES_FILE}" 2>/dev/null || echo "0")
        log "✅ State + ${BAL_COUNT} balances loaded"
    elif echo "$RECORD" | jq -e '.block' > /dev/null 2>&1; then
        # Old format - just state
        echo "$RECORD" > "${STATE_FILE}"
        echo '{}' > "${BALANCES_FILE}"
        STATE_LOADED="yes"
        log "✅ State loaded (no saved balances)"
    else
        rm -f "${STATE_FILE}"
        echo '{}' > "${BALANCES_FILE}"
        STATE_LOADED="no"
        log "⚠️ Unknown format"
    fi
else
    STATE_LOADED="no"
    echo '{}' > "${BALANCES_FILE}"
    log "🆕 Fresh start"
fi

# -------------------------------------------------------------------
# SAVE BALANCES FOR ALL MODIFIED WALLETS
# -------------------------------------------------------------------
save_balances() {
    log "💾 Collecting wallet balances..."
    
    # Start JSON
    echo '{' > "${BALANCES_FILE}.tmp"
    FIRST=true
    COUNT=0
    
    # Get all addresses with non-zero ETH balance (excluding Anvil defaults)
    # We check the state file for modified accounts
    if [ -f "${STATE_FILE}" ]; then
        ADDRESSES=$(jq -r '.accounts | keys[]' "${STATE_FILE}" 2>/dev/null)
        
        for ADDR in $ADDRESSES; do
            # Get ETH balance
            ETH_BAL=$(rpc "eth_getBalance" "[\"${ADDR}\",\"latest\"]" | jq -r '.result // "0x0"')
            
            # Get USDT balance
            USDT_DATA="0x70a08231000000000000000000000000${ADDR#0x}"
            USDT_BAL=$(rpc "eth_call" "[{\"to\":\"${USDT}\",\"data\":\"${USDT_DATA}\"},\"latest\"]" | jq -r '.result // "0x0"')
            
            # Skip if both are zero
            if [ "$ETH_BAL" != "0x0" ] && [ "$ETH_BAL" != "0x" ]; then
                if [ "$FIRST" = true ]; then FIRST=false; else echo ',' >> "${BALANCES_FILE}.tmp"; fi
                echo "\"${ADDR}\":{\"eth\":\"${ETH_BAL}\",\"usdt\":\"${USDT_BAL}\"}" >> "${BALANCES_FILE}.tmp"
                COUNT=$((COUNT + 1))
            fi
        done
    fi
    
    echo '}' >> "${BALANCES_FILE}.tmp"
    mv "${BALANCES_FILE}.tmp" "${BALANCES_FILE}"
    
    log "   Saved ${COUNT} wallet balances"
    return 0
}

# -------------------------------------------------------------------
# UPLOAD STATE + BALANCES
# -------------------------------------------------------------------
upload_all() {
    save_balances
    
    if [ ! -f "${STATE_FILE}" ]; then
        log "⚠️ No state file"
        return 1
    fi
    
    COMBINED=$(jq -n --argfile state "${STATE_FILE}" --argfile balances "${BALANCES_FILE}" \
        '{state: $state, balances: $balances}')
    
    RESPONSE=$(curl -s --max-time 30 -X PUT \
        "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}" \
        -H "Content-Type: application/json" \
        -H "X-Master-Key: ${JSONBIN_API_KEY}" \
        -d "{\"record\": ${COMBINED}}")
    
    if echo "$RESPONSE" | jq -e '.record' > /dev/null 2>&1; then
        log "✅ Uploaded to JSONBin"
        return 0
    else
        log "❌ Upload failed"
        return 1
    fi
}

# -------------------------------------------------------------------
# RESTORE BALANCES AFTER RESTART
# -------------------------------------------------------------------
restore_balances() {
    if [ ! -f "${BALANCES_FILE}" ] || [ ! -s "${BALANCES_FILE}" ]; then
        log "   No balances to restore"
        return
    fi
    
    log "🔄 Restoring wallet balances..."
    
    WALLETS=$(jq -r 'keys[]' "${BALANCES_FILE}" 2>/dev/null)
    RESTORED=0
    
    for ADDR in $WALLETS; do
        ETH_BAL=$(jq -r ".\"${ADDR}\".eth" "${BALANCES_FILE}" 2>/dev/null)
        USDT_BAL=$(jq -r ".\"${ADDR}\".usdt" "${BALANCES_FILE}" 2>/dev/null)
        
        # Restore ETH
        if [ "$ETH_BAL" != "null" ] && [ "$ETH_BAL" != "0x0" ] && [ -n "$ETH_BAL" ]; then
            rpc "anvil_setBalance" "[\"${ADDR}\",\"${ETH_BAL}\"]" > /dev/null 2>&1
        fi
        
        # Restore USDT via storage manipulation
        if [ "$USDT_BAL" != "null" ] && [ "$USDT_BAL" != "0x0" ] && [ -n "$USDT_BAL" ]; then
            # USDT balanceOf storage slot for this address
            # keccak256(address + uint256(2))
            ADDR_NO0X=$(echo "${ADDR}" | sed 's/0x//' | tr '[:upper:]' '[:lower:]')
            SLOT_PREIMAGE="000000000000000000000000${ADDR_NO0X}0000000000000000000000000000000000000000000000000000000000000002"
            SLOT_HASH=$(echo -n "${SLOT_PREIMAGE}" | xxd -r -p | sha256sum | head -c 64)
            
            # Format balance to 32 bytes
            BAL_HEX=$(echo "${USDT_BAL}" | sed 's/0x//')
            BAL_PADDED=$(printf "%064s" "$BAL_HEX" | tr ' ' '0')
            
            rpc "anvil_setStorageAt" "[\"${USDT}\",\"0x${SLOT_HASH}\",\"0x${BAL_PADDED}\"]" > /dev/null 2>&1
        fi
        
        RESTORED=$((RESTORED + 1))
        log "   ✅ ${ADDR:0:10}...${ADDR: -6}"
    done
    
    log "🎯 Restored ${RESTORED} wallets"
}

# -------------------------------------------------------------------
# MONITOR & SAVE
# -------------------------------------------------------------------
monitor_and_save() {
    LAST_BLOCK="0x0"
    while true; do
        CURRENT_BLOCK=$(rpc "eth_blockNumber" "[]" | jq -r '.result // "0x0"')
        if [ "$CURRENT_BLOCK" != "$LAST_BLOCK" ] && [ "$CURRENT_BLOCK" != "0x0" ]; then
            log "🔔 Block: ${LAST_BLOCK} → ${CURRENT_BLOCK}"
            upload_all
            LAST_BLOCK="$CURRENT_BLOCK"
        fi
        sleep 2
    done
}

graceful_shutdown() {
    log "⚠️ Shutdown... saving..."
    upload_all
    log "👋 Done"
    exit 0
}

# -------------------------------------------------------------------
# LAUNCH ANVIL
# -------------------------------------------------------------------
log "========================================="
log "🚀 LAUNCHING FORK"
log "========================================="

CMD="anvil --fork-url ${FORK_URL} --chain-id ${CHAIN_ID} --host 0.0.0.0 --port ${PORT} --state ${STATE_FILE}"

[ "${STATE_LOADED}" = "yes" ] && log "📂 Resuming from saved state" || log "🆕 Fresh fork"

$CMD &
ANVIL_PID=$!
log "✅ Anvil PID: ${ANVIL_PID}"

# Wait for ready
sleep 5
for i in $(seq 1 20); do
    rpc "eth_blockNumber" "[]" | jq -e '.result' > /dev/null 2>&1 && break
    sleep 2
done

# -------------------------------------------------------------------
# RESTORE BALANCES
# -------------------------------------------------------------------
restore_balances

# -------------------------------------------------------------------
# START SYNC
# -------------------------------------------------------------------
trap graceful_shutdown SIGTERM SIGINT
sleep 2
upload_all
monitor_and_save &
MONITOR_PID=$!

log "========================================="
log "🎯 READY"
log "========================================="
log "📡 RPC: https://anvil-render-q5wl.onrender.com"
log "💵 USDT: ${USDT}"
log "🔒 Balances survive restarts"
log "========================================="

wait $ANVIL_PID
