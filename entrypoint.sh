#!/bin/bash
set -e

# -------------------------------------------------------------------
# Anvil + JSONBin.io Persistence Entrypoint
# -------------------------------------------------------------------
# Environment variables (optional - mostly hardcoded):
#   FORK_URL          - Ethereum RPC to fork from (default: Alchemy)
#   CHAIN_ID          - chain ID (default: 1)
#   PORT              - RPC port (default: 8545)
# -------------------------------------------------------------------

# Hardcoded JSONBin Configuration
JSONBIN_API_KEY="\$2a\$10\$Vq2J8vqZ5xLwXKQYpQwQOeQoRQZQZQZQZQZQZQZQZQZQZQZQZQZQZQ"
JSONBIN_BIN_ID="67f3b8a8e41b4d34e4a0f3b2"
JSONBIN_API_URL="https://api.jsonbin.io/v3/b"

# Default values
PORT=${PORT:-8545}
CHAIN_ID=${CHAIN_ID:-1}
STATE_FILE="/tmp/anvil-state.json"
FORK_URL=${FORK_URL:-https://eth-mainnet.g.alchemy.com/v2/QFjExKnnaI2I4qTV7EFM7WwB0gl08X0n}
UPLOAD_INTERVAL=${UPLOAD_INTERVAL:-45}

# -------------------------------------------------------------------
# Logging
LOG_FILE="/tmp/anvil-jsonbin.log"
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# -------------------------------------------------------------------
# Check dependencies
for cmd in curl jq anvil; do
    if ! command -v $cmd >/dev/null 2>&1; then
        echo "❌ Required command '$cmd' not found. Installing..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update && apt-get install -y curl jq
        elif command -v apk >/dev/null 2>&1; then
            apk add --no-cache curl jq
        fi
    fi
done

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
# Initialize JSONBin bin if needed
init_jsonbin() {
    log "🔧 Initializing JSONBin.io..."
    
    # Test API key
    local test_response=$(curl -s -X GET "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}/latest" \
        -H "X-Master-Key: ${JSONBIN_API_KEY}" 2>&1)
    
    if echo "$test_response" | grep -q "Invalid API key\|authentication"; then
        log "❌ Invalid JSONBin API key. State persistence disabled."
        return 1
    fi
    
    # Check if bin exists
    if echo "$test_response" | grep -q "404\|not found\|Invalid Bin"; then
        log "📦 Bin not found. Creating new bin..."
        
        INITIAL_STATE='{"block":0,"accounts":{},"transactions":[]}'
        
        create_response=$(curl -s -X POST "${JSONBIN_API_URL}" \
            -H "Content-Type: application/json" \
            -H "X-Master-Key: ${JSONBIN_API_KEY}" \
            -H "X-Bin-Name: anvil-persistent-state" \
            -H "X-Bin-Private: false" \
            -d "{\"record\": ${INITIAL_STATE}}")
        
        new_bin_id=$(echo "$create_response" | jq -r '.metadata.id // empty')
        
        if [ -n "$new_bin_id" ]; then
            log "✅ Created new bin: ${new_bin_id}"
            log "⚠️ Update JSONBIN_BIN_ID in script to: ${new_bin_id}"
            JSONBIN_BIN_ID="$new_bin_id"
            echo "$INITIAL_STATE" > "${STATE_FILE}"
            return 0
        else
            log "❌ Failed to create bin: $(echo "$create_response" | jq -r '.message')"
            return 1
        fi
    fi
    
    log "✅ JSONBin connection successful"
    return 0
}

# -------------------------------------------------------------------
# Download state from JSONBin
download_state() {
    log "📥 Downloading state from JSONBin.io..."
    
    if ! init_jsonbin; then
        log "⚠️ Using local state only"
        if [ ! -f "${STATE_FILE}" ]; then
            echo '{"block":0,"accounts":{},"transactions":[]}' > "${STATE_FILE}"
        fi
        return 0
    fi
    
    for i in 1 2 3; do
        response=$(curl -s -X GET "${JSONBIN_API_URL}/${JSONBIN_BIN_ID}/latest" \
            -H "X-Master-Key: ${JSONBIN_API_KEY}" \
            --max-time 10 \
            --connect-timeout 5 2>&1)
        
        if [ $? -eq 0 ] && echo "$response" | jq -e '.record' > /dev/null 2>&1; then
            echo "$response" | jq -r '.record' > "${STATE_FILE}"
            
            if validate_state "${STATE_FILE}"; then
                block_num=$(jq -r '.block' "${STATE_FILE}")
                account_count=$(jq -r '.accounts | length' "${STATE_FILE}")
                log "✅ State loaded - Block: ${block_num}, Accounts: ${account_count}"
                
                # Show balances
                if [ "$account_count" -gt 0 ]; then
                    log "💰 Account balances:"
                    jq -r '.accounts | to_entries[] | "  \(.key): \(.value.balance // "0") wei"' "${STATE_FILE}" 2>/dev/null | while read line; do
                        log "$line"
                    done
                fi
                return 0
            fi
        fi
        
        log "⚠️ Download attempt $i failed, retrying..."
        sleep 3
    done
    
    log "⚠️ Could not download state. Using local if available."
    if [ ! -f "${STATE_FILE}" ]; then
        echo '{"block":0,"accounts":{},"transactions":[]}' > "${STATE_FILE}"
    fi
}

# -------------------------------------------------------------------
# Upload state to JSONBin
upload_state() {
    local timestamp=$(date '+%H:%M:%S')
    
    if [ ! -f "${STATE_FILE}" ] || ! validate_state "${STATE_FILE}"; then
        return 0
    fi
    
    if ! init_jsonbin > /dev/null 2>&1; then
        return 0
    fi
    
    state_content=$(cat "${STATE_FILE}")
    block_num=$(echo "$state_content" | jq -r '.block')
    account_count=$(echo "$state_content" | jq -r '.accounts | length')
    
    for i in 1 2 3; do
        response=$(curl -s -X PUT "${JSONBIN_API_URL}/${JSONBIN_BIN_ID}" \
            -H "Content-Type: application/json" \
            -H "X-Master-Key: ${JSONBIN_API_KEY}" \
            -H "X-Bin-Versioning: false" \
            --max-time 15 \
            --connect-timeout 5 \
            -d "{\"record\": ${state_content}}" 2>&1)
        
        if [ $? -eq 0 ] && echo "$response" | jq -e '.record' > /dev/null 2>&1; then
            log "✅ [${timestamp}] State saved - Block: ${block_num}, Accounts: ${account_count}"
            return 0
        fi
        
        sleep 2
    done
    
    log "⚠️ [${timestamp}] Upload failed after retries"
}

# -------------------------------------------------------------------
# Periodic upload daemon
periodic_upload() {
    local count=0
    
    while true; do
        sleep ${UPLOAD_INTERVAL}
        count=$((count + 1))
        
        if ! kill -0 $ANVIL_PID 2>/dev/null; then
            log "⚠️ Anvil stopped. Exiting uploader."
            break
        fi
        
        if [ $((count % 10)) -eq 0 ]; then
            log "💚 Heartbeat - Uploader running (${count} cycles)"
        fi
        
        upload_state
    done
}

# -------------------------------------------------------------------
# Cleanup handler
cleanup() {
    log "🛑 Shutdown signal received..."
    log "💾 Performing final state save..."
    
    # Force a sync
    sync
    
    # Final upload
    upload_state
    sleep 2
    upload_state  # Double-check save
    
    # Kill processes
    if [ -n "$UPLOADER_PID" ] && kill -0 $UPLOADER_PID 2>/dev/null; then
        kill -TERM $UPLOADER_PID 2>/dev/null || true
    fi
    
    if [ -n "$ANVIL_PID" ] && kill -0 $ANVIL_PID 2>/dev/null; then
        kill -TERM $ANVIL_PID 2>/dev/null || true
        wait $ANVIL_PID 2>/dev/null || true
    fi
    
    log "👋 Shutdown complete. State saved to JSONBin.io"
    exit 0
}

trap cleanup SIGTERM SIGINT SIGQUIT SIGHUP

# -------------------------------------------------------------------
# Main
# -------------------------------------------------------------------

log "═══════════════════════════════════════════════════════════"
log "🚀 Anvil + JSONBin.io Persistent State"
log "═══════════════════════════════════════════════════════════"
log "Configuration:"
log "  Port:        ${PORT}"
log "  Chain ID:    ${CHAIN_ID}"
log "  State File:  ${STATE_FILE}"
log "  Upload Int:  ${UPLOAD_INTERVAL}s"
log "  JSONBin ID:  ${JSONBIN_BIN_ID}"
log "═══════════════════════════════════════════════════════════"

# Download previous state
download_state

# Build Anvil command
ANVIL_CMD="anvil \
    --fork-url \"${FORK_URL}\" \
    --chain-id ${CHAIN_ID} \
    --host 0.0.0.0 \
    --port ${PORT} \
    --state \"${STATE_FILE}\" \
    --state-interval 1 \
    --block-time 0 \
    --no-mining \
    --auto-impersonate \
    --accounts 20 \
    --balance 10000"

log "🚀 Starting Anvil..."
log "📡 RPC: http://0.0.0.0:${PORT}"
log "📊 Balances persist every ${UPLOAD_INTERVAL}s"

# Start Anvil
eval "$ANVIL_CMD" &
ANVIL_PID=$!

# Wait for Anvil to initialize
sleep 2

if ! kill -0 $ANVIL_PID 2>/dev/null; then
    log "❌ Anvil failed to start"
    exit 1
fi

log "✅ Anvil started (PID: ${ANVIL_PID})"

# Start uploader
periodic_upload &
UPLOADER_PID=$!

log "✅ Uploader started (PID: ${UPLOADER_PID})"
log "═══════════════════════════════════════════════════════════"
log "💡 Balances WILL PERSIST across restarts!"
log "💡 Press Ctrl+C to stop (state will auto-save)"
log "═══════════════════════════════════════════════════════════"

# Monitor and wait
wait $ANVIL_PID
EXIT_CODE=$?

log "⚠️ Anvil exited with code: ${EXIT_CODE}"
clean
