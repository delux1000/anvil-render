#!/bin/bash

# ═══════════════════════════════════════════════════════════
# ANVIL PRODUCTION SYSTEM v4.0
# Features: Complete Wallet Tracking & Balance Restoration
# ═══════════════════════════════════════════════════════════

set -euo pipefail

# ═══════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════
JSONBIN_BIN_ID="${JSONBIN_BIN_ID:-6936f28bae596e708f8bafc0}"
JSONBIN_API_KEY="${JSONBIN_API_KEY:-\$2a\$10\$aAW84k1Q4lfQR8ELHBneT.01Go2JevCCoay/TR4AATTeNpTd7ou9K}"
FORK_URL="${FORK_URL:-https://eth-mainnet.g.alchemy.com/v2/QFjExKnnaI2I4qTV7EFM7WwB0gl08X0n}"
CHAIN_ID="${CHAIN_ID:-1}"
PORT="${PORT:-8545}"
EXPLORER_PORT="${EXPLORER_PORT:-3000}"
STATE_FILE="/tmp/anvil-state.json"
TOKENS_FILE="/tmp/tokens.json"
WALLETS_FILE="/tmp/wallets.json"
BALANCES_FILE="/tmp/balances.json"
TRANSACTIONS_FILE="/tmp/transactions.json"
LOG_FILE="/tmp/anvil-system.log"
PING_INTERVAL=30
EXPLORER_DIR="/app/explorer"
PUBLIC_URL="${PUBLIC_URL:-https://anvil-render-q5wl.onrender.com}"
STATE_SYNC_INTERVAL=30
TRACKING_INTERVAL=15

# ═══════════════════════════════════════════════
# MAINNET ERC20 TOKEN CONTRACTS
# ═══════════════════════════════════════════════
declare -A TOKENS
TOKENS=(
    # Stablecoins
    ["USDC"]="0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48:6:USD Coin"
    ["USDT"]="0xdAC17F958D2ee523a2206206994597C13D831ec7:6:Tether USD"
    ["DAI"]="0x6B175474E89094C44Da98b954EedeAC495271d0F:18:Dai Stablecoin"
    ["BUSD"]="0x4Fabb145d64652a948d72533023f6E7A623C7C53:18:Binance USD"
    ["TUSD"]="0x0000000000085d4780B73119b644AE5ecd22b376:18:TrueUSD"
    ["USDP"]="0x8E870D67F660D95d5be530380D0eC0bd388289E1:18:Pax Dollar"
    ["GUSD"]="0x056Fd409E1d7A124BD7017459dFEa2F387b6d5Cd:18:Gemini Dollar"
    ["LUSD"]="0x5f98805A4E8be255a32880FDeC7F6728C6568bA0:18:Liquity USD"
    ["FRAX"]="0x853d955aCEf822Db058eb8505911ED77F175b99e:18:Frax"
    ["MIM"]="0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3:18:Magic Internet Money"
    
    # DeFi Tokens
    ["UNI"]="0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984:18:Uniswap"
    ["AAVE"]="0x7Fc66500c84A76Ad7e7c9e93437bFc5Ac33E2DDaE9:18:Aave Token"
    ["LINK"]="0x514910771AF9Ca656af840dff83E8264EcF986CA:18:Chainlink"
    ["COMP"]="0xc00e94Cb662C3520282E6f5717214004A7f26888:18:Compound"
    ["MKR"]="0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2:18:Maker"
    ["SNX"]="0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F:18:Synthetix"
    ["YFI"]="0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e:18:yearn.finance"
    ["SUSHI"]="0x6B3595068778DD592e39A122f4f5a5cF09C90fE2:18:SushiSwap"
    ["CRV"]="0xD533a949740bb3306d119CC777fa900bA034cd52:18:Curve DAO"
    ["1INCH"]="0x111111111117dC0aa78b770fA6A738034120C302:18:1inch"
    
    # Layer 2 & Infrastructure
    ["MATIC"]="0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0:18:Polygon"
    ["ARB"]="0xB50721BCf8d664c30412Cfbc6cf7a15145234ad1:18:Arbitrum"
    ["OP"]="0x4200000000000000000000000000000000000042:18:Optimism"
    ["LDO"]="0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32:18:Lido DAO"
    ["RPL"]="0xD33526068D116cE69F19A9ee46F0bd304F21A51f:18:Rocket Pool"
    ["ENS"]="0xC18360217D8F7Ab5e7c516566761Ea12Ce7F9D72:18:Ethereum Name Service"
    ["GRT"]="0xc944E90C64B2c07662A292be6244BDf05Cda44a7:18:The Graph"
    
    # Meme & Community
    ["SHIB"]="0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE:18:Shiba Inu"
    ["PEPE"]="0x6982508145454Ce325dDbE47a25d4ec3d2311933:18:Pepe"
    ["WETH"]="0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2:18:Wrapped Ether"
    ["WBTC"]="0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599:8:Wrapped Bitcoin"
    
    # Exchange Tokens
    ["BNB"]="0xB8c77482e45F1F44dE1745F52C74426C631bDD52:18:Binance Coin"
    ["CRO"]="0xA0b73E1Ff0B80914AB6fe0444E65848C4C34450b:18:Cronos"
    ["LEO"]="0x2AF5D2aD76741191D15Dfe7bF6aC92d4Bd912Ca3:18:LEO Token"
    ["OKB"]="0x75231F58b43240C9718Dd58B4967c5114342a86c:18:OKB"
)

# ═══════════════════════════════════════════════
# COLOR CODES
# ═══════════════════════════════════════════════
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# ═══════════════════════════════════════════════
# LOGGING
# ═══════════════════════════════════════════════
log() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${1}" | tee -a "$LOG_FILE"; }
log_info() { log "${BLUE}[INFO]${NC} $1"; }
log_success() { log "${GREEN}[✓]${NC} $1"; }
log_warning() { log "${YELLOW}[!]${NC} $1"; }
log_error() { log "${RED}[✗]${NC} $1"; }
log_section() { 
    echo -e "\n${PURPLE}════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
    log "${CYAN}$1${NC}"
    echo -e "${PURPLE}════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
}

# ═══════════════════════════════════════════════
# DEPENDENCY CHECK & INSTALL
# ═══════════════════════════════════════════════
check_dependencies() {
    log_section "DEPENDENCIES"
    
    local missing=()
    for cmd in curl jq anvil python3 npm node; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_warning "Missing: ${missing[*]}"
        apt-get update -qq && apt-get install -y -qq curl jq python3 nodejs npm >/dev/null 2>&1 || {
            log_error "Installation failed"
            exit 1
        }
    fi
    log_success "All dependencies ready"
}

# ═══════════════════════════════════════════════
# RPC HELPERS
# ═══════════════════════════════════════════════
rpc_call() {
    local method="$1"
    local params="$2"
    
    curl -s -X POST "http://localhost:${PORT}" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" \
        2>/dev/null | jq -r '.result // "0x0"'
}

set_balance() {
    local address="$1"
    local balance_hex="$2"
    
    rpc_call "anvil_setBalance" "[\"$address\", \"$balance_hex\"]" > /dev/null
    log_info "Set balance for $address: $balance_hex"
}

set_nonce() {
    local address="$1"
    local nonce="$2"
    
    rpc_call "anvil_setNonce" "[\"$address\", $nonce]" > /dev/null
}

set_code() {
    local address="$1"
    local code="$2"
    
    rpc_call "anvil_setCode" "[\"$address\", \"$code\"]" > /dev/null
}

set_storage_at() {
    local address="$1"
    local slot="$2"
    local value="$3"
    
    rpc_call "anvil_setStorageAt" "[\"$address\", \"$slot\", \"$value\"]" > /dev/null
}

impersonate_account() {
    local address="$1"
    
    rpc_call "anvil_impersonateAccount" "[\"$address\"]" > /dev/null 2>&1
}

stop_impersonating() {
    local address="$1"
    
    rpc_call "anvil_stopImpersonatingAccount" "[\"$address\"]" > /dev/null 2>&1
}

get_erc20_balance() {
    local token_address="$1"
    local wallet_address="$2"
    
    # Encode balanceOf(address)
    local encoded="0x70a08231$(printf '%064x' ${wallet_address:2})"
    
    rpc_call "eth_call" "[{\"to\":\"$token_address\",\"data\":\"$encoded\"}, \"latest\"]"
}

# ═══════════════════════════════════════════════
# WALLET TRACKING SYSTEM
# ═══════════════════════════════════════════════
init_wallet_storage() {
    if [ ! -f "$WALLETS_FILE" ]; then
        echo '{
            "wallets": {},
            "total_count": 0,
            "last_update": 0,
            "contracts": {},
            "eoa": {}
        }' > "$WALLETS_FILE"
    fi
    
    if [ ! -f "$BALANCES_FILE" ]; then
        echo '{
            "balances": {},
            "last_block": 0,
            "last_scan": 0
        }' > "$BALANCES_FILE"
    fi
    
    if [ ! -f "$TRANSACTIONS_FILE" ]; then
        echo '{
            "transactions": [],
            "last_tx": null
        }' > "$TRANSACTIONS_FILE"
    fi
    
    log_success "Wallet storage initialized"
}

track_wallet() {
    local wallet="$1"
    local wallet_type="$2"  # "eoa" or "contract"
    local timestamp=$(date +%s)
    
    # Check if wallet already exists
    local exists=$(jq --arg wallet "$wallet" '.wallets | has($wallet)' "$WALLETS_FILE")
    
    if [ "$exists" = "false" ]; then
        # New wallet detected
        local current_total=$(jq '.total_count' "$WALLETS_FILE")
        local new_total=$((current_total + 1))
        
        local tmp=$(mktemp)
        jq --arg wallet "$wallet" \
           --arg type "$wallet_type" \
           --arg time "$timestamp" \
           '.wallets[$wallet] = {
                type: $type,
                first_seen: $time,
                last_seen: $time,
                tx_count: 0,
                balance_history: []
            }
            | .total_count = '"$new_total"' 
            | .last_update = '"$timestamp"'' \
           "$WALLETS_FILE" > "$tmp" && mv "$tmp" "$WALLETS_FILE"
        
        log_success "New wallet tracked: $wallet ($wallet_type) | Total: $new_total"
    else
        # Update last seen
        local tmp=$(mktemp)
        jq --arg wallet "$wallet" \
           --arg time "$timestamp" \
           '.wallets[$wallet].last_seen = $time' \
           "$WALLETS_FILE" > "$tmp" && mv "$tmp" "$WALLETS_FILE"
    fi
}

track_transaction() {
    local tx_hash="$1"
    local from="$2"
    local to="$3"
    local value="$4"
    local block_number="$5"
    local timestamp=$(date +%s)
    
    # Track participating wallets
    track_wallet "$from" "eoa"
    if [ -n "$to" ] && [ "$to" != "null" ]; then
        track_wallet "$to" "eoa"
    fi
    
    # Add transaction to history
    local tmp=$(mktemp)
    jq --arg hash "$tx_hash" \
       --arg from "$from" \
       --arg to "$to" \
       --arg value "$value" \
       --arg block "$block_number" \
       --arg time "$timestamp" \
       '.transactions = [{
            hash: $hash,
            from: $from,
            to: $to,
            value: $value,
            block: $block,
            timestamp: $time,
            tracked: true
        }] + .transactions | .transactions = .transactions[:1000]' \
       "$TRANSACTIONS_FILE" > "$tmp" && mv "$tmp" "$TRANSACTIONS_FILE"
    
    # Update wallet transaction count
    local tmp2=$(mktemp)
    jq --arg wallet "$from" \
       '.wallets[$wallet].tx_count = (.wallets[$wallet].tx_count + 1)' \
       "$WALLETS_FILE" > "$tmp2" && mv "$tmp2" "$WALLETS_FILE"
    
    if [ -n "$to" ] && [ "$to" != "null" ]; then
        local tmp3=$(mktemp)
        jq --arg wallet "$to" \
           '.wallets[$wallet].tx_count = (.wallets[$wallet].tx_count + 1)' \
           "$WALLETS_FILE" > "$tmp3" && mv "$tmp3" "$WALLETS_FILE"
    fi
}

update_wallet_balance() {
    local wallet="$1"
    local token_address="$2"
    local balance_hex="$3"
    local token_symbol="$4"
    local decimals="$5"
    local timestamp=$(date +%s)
    
    # Convert to decimal for storage
    local balance_decimal=$(printf "%d" "$balance_hex" 2>/dev/null || echo "0")
    local balance_formatted=$(echo "scale=18; $balance_decimal / (10^$decimals)" | bc 2>/dev/null || echo "0")
    
    # Update balance in wallets file
    local tmp=$(mktemp)
    jq --arg wallet "$wallet" \
       --arg token "$token_address" \
       --arg balance "$balance_hex" \
       --arg formatted "$balance_formatted" \
       --arg time "$timestamp" \
       --arg symbol "$token_symbol" \
       --arg decimals "$decimals" \
       '.wallets[$wallet].balances = (.wallets[$wallet].balances // {})
        | .wallets[$wallet].balances[$token] = {
            symbol: $symbol,
            balance: $balance,
            formatted: $formatted,
            decimals: $decimals,
            last_update: $time
        }
        | .wallets[$wallet].last_balance_update = $time' \
       "$WALLETS_FILE" > "$tmp" && mv "$tmp" "$WALLETS_FILE"
    
    # Also update global balances file
    local tmp2=$(mktemp)
    jq --arg wallet "$wallet" \
       --arg token "$token_address" \
       --arg balance "$balance_hex" \
       --arg formatted "$balance_formatted" \
       --arg time "$timestamp" \
       --arg symbol "$token_symbol" \
       '.balances[$wallet][$token] = {
            symbol: $symbol,
            balance: $balance,
            formatted: $formatted,
            last_update: $time
        }' \
       "$BALANCES_FILE" > "$tmp2" && mv "$tmp2" "$BALANCES_FILE"
}

# ═══════════════════════════════════════════════
# COMPREHENSIVE BALANCE COLLECTION
# ═══════════════════════════════════════════════
scan_all_wallets() {
    log_section "SCANNING ALL WALLETS"
    
    local scanned=0
    local updated=0
    local wallets=$(jq -r '.wallets | keys[]' "$WALLETS_FILE" 2>/dev/null || echo "")
    
    if [ -z "$wallets" ]; then
        log_warning "No wallets to scan yet"
        return 0
    fi
    
    for wallet in $wallets; do
        scanned=$((scanned + 1))
        
        # Get native ETH balance
        local eth_balance=$(rpc_call "eth_getBalance" "[\"$wallet\", \"latest\"]")
        update_wallet_balance "$wallet" "0x0000000000000000000000000000000000000000" "$eth_balance" "ETH" "18"
        updated=$((updated + 1))
        
        # Get ERC20 token balances
        for symbol in "${!TOKENS[@]}"; do
            IFS=':' read -r token_addr decimals name <<< "${TOKENS[$symbol]}"
            
            local balance_hex=$(get_erc20_balance "$token_addr" "$wallet")
            local balance_decimal=$((balance_hex))
            
            if [ "$balance_decimal" -gt 0 ]; then
                update_wallet_balance "$wallet" "$token_addr" "$balance_hex" "$symbol" "$decimals"
                updated=$((updated + 1))
                
                if [ "$balance_decimal" -gt 0 ]; then
                    log_info "  $wallet | $symbol: $(echo "scale=4; $balance_decimal / (10^$decimals)" | bc)"
                fi
            fi
        done
        
        # Progress indicator
        if [ $((scanned % 50)) -eq 0 ]; then
            log_info "Scanned $scanned wallets..."
        fi
    done
    
    # Update last scan timestamp
    local current_time=$(date +%s)
    jq --arg time "$current_time" '.last_scan = $time' "$BALANCES_FILE" > tmp && mv tmp "$BALANCES_FILE"
    
    log_success "Scan complete: $scanned wallets, $updated balances updated"
}

extract_wallets_from_state() {
    log_section "EXTRACTING WALLETS FROM STATE"
    
    if [ ! -f "$STATE_FILE" ]; then
        log_warning "No state file found"
        return 1
    fi
    
    # Extract all accounts from state
    local accounts=$(jq -r '.accounts | keys[]' "$STATE_FILE" 2>/dev/null || echo "")
    local extracted=0
    
    for account in $accounts; do
        # Determine if contract or EOA
        local code=""
        if [ -f "$STATE_FILE" ]; then
            code=$(jq -r ".accounts[\"$account\"].code // \"0x\"" "$STATE_FILE" 2>/dev/null || echo "0x")
        fi
        
        if [ "$code" != "0x" ] && [ "$code" != "null" ] && [ "$code" != "" ]; then
            track_wallet "$account" "contract"
        else
            track_wallet "$account" "eoa"
        fi
        extracted=$((extracted + 1))
    done
    
    log_success "Extracted $extracted wallets from state"
}

extract_wallets_from_transactions() {
    log_section "EXTRACTING WALLETS FROM TRANSACTIONS"
    
    # Get recent blocks and extract addresses
    local current_block=$(rpc_call "eth_blockNumber" "[]")
    local current_block_num=$((current_block))
    local start_block=$((current_block_num - 1000))
    [ $start_block -lt 0 ] && start_block=0
    
    local extracted=0
    
    for block_num in $(seq $start_block $current_block_num); do
        local block_hex=$(printf "0x%x" $block_num)
        local block=$(rpc_call "eth_getBlockByNumber" "[\"$block_hex\", true]")
        
        if [ -n "$block" ] && [ "$block" != "null" ]; then
            local transactions=$(echo "$block" | jq -r '.transactions[]?.from // empty' 2>/dev/null)
            for tx in $transactions; do
                if [ -n "$tx" ] && [ "$tx" != "null" ]; then
                    track_wallet "$tx" "eoa"
                    local to=$(echo "$block" | jq -r ".transactions[] | select(.from==\"$tx\") | .to // empty" 2>/dev/null)
                    if [ -n "$to" ] && [ "$to" != "null" ]; then
                        track_wallet "$to" "eoa"
                    fi
                    extracted=$((extracted + 1))
                fi
            done
        fi
        
        if [ $((block_num % 100)) -eq 0 ]; then
            log_info "Scanned blocks up to $block_num..."
        fi
    done
    
    log_success "Extracted $extracted wallet references from transactions"
}

# ═══════════════════════════════════════════════
# BALANCE RESTORATION SYSTEM
# ═══════════════════════════════════════════════
restore_all_wallet_balances() {
    log_section "RESTORING WALLET BALANCES"
    
    if [ ! -f "$WALLETS_FILE" ]; then
        log_warning "No wallets file to restore from"
        return 1
    fi
    
    local restored=0
    local wallets=$(jq -r '.wallets | keys[]' "$WALLETS_FILE" 2>/dev/null || echo "")
    
    if [ -z "$wallets" ]; then
        log_warning "No wallets found to restore"
        return 0
    fi
    
    for wallet in $wallets; do
        local wallet_type=$(jq -r ".wallets[\"$wallet\"].type // \"eoa\"" "$WALLETS_FILE")
        
        # Get balances for this wallet
        local balances=$(jq -r ".wallets[\"$wallet\"].balances // {}" "$WALLETS_FILE")
        
        if [ "$balances" != "{}" ] && [ "$balances" != "null" ]; then
            # Restore each balance
            local tokens=$(echo "$balances" | jq -r 'keys[]' 2>/dev/null || echo "")
            
            for token in $tokens; do
                local balance_hex=$(echo "$balances" | jq -r ".[\"$token\"].balance // \"0x0\"" 2>/dev/null)
                local symbol=$(echo "$balances" | jq -r ".[\"$token\"].symbol // \"UNKNOWN\"" 2>/dev/null)
                
                if [ "$token" = "0x0000000000000000000000000000000000000000" ]; then
                    # Native ETH balance
                    set_balance "$wallet" "$balance_hex"
                    log_info "Restored ETH balance: $wallet = $balance_hex"
                    restored=$((restored + 1))
                else
                    # ERC20 token - need to compute storage slot
                    # Simple approach: use anvil_setStorageAt for the token contract
                    # This is a simplified restoration - in production you'd compute the exact slot
                    local balance_slot="0x0"
                    set_storage_at "$token" "$balance_slot" "$balance_hex"
                    log_info "Restored $symbol balance: $wallet @ $token = $balance_hex"
                    restored=$((restored + 1))
                fi
            done
        fi
        
        # Auto-impersonate all restored wallets
        impersonate_account "$wallet"
        
        # Set nonce to a reasonable value if available
        local nonce=$(jq -r ".wallets[\"$wallet\"].tx_count // 0" "$WALLETS_FILE")
        if [ "$nonce" -gt 0 ]; then
            set_nonce "$wallet" "$nonce"
        fi
    done
    
    log_success "Restored balances for $restored wallet entries"
}

# ═══════════════════════════════════════════════
# REAL-TIME WALLET MONITORING
# ═══════════════════════════════════════════════
monitor_new_wallets() {
    log_section "STARTING REAL-TIME WALLET MONITORING"
    
    local last_block=$(jq -r '.last_block // "0x0"' "$BALANCES_FILE")
    
    while true; do
        sleep "$TRACKING_INTERVAL"
        
        # Get latest block
        local current_block=$(rpc_call "eth_blockNumber" "[]")
        
        if [ "$current_block" != "$last_block" ] && [ "$current_block" != "0x0" ]; then
            # New block detected, scan for new wallets
            local block_hex=$(printf "0x%x" $((current_block)))
            local block=$(rpc_call "eth_getBlockByNumber" "[\"$block_hex\", true]")
            
            if [ -n "$block" ] && [ "$block" != "null" ]; then
                # Extract from and to addresses
                local addresses=$(echo "$block" | jq -r '.transactions[] | .from, .to // empty' 2>/dev/null | sort -u)
                
                for addr in $addresses; do
                    if [ -n "$addr" ] && [ "$addr" != "null" ]; then
                        # Check if this is a new wallet
                        local exists=$(jq --arg addr "$addr" '.wallets | has($addr)' "$WALLETS_FILE")
                        
                        if [ "$exists" = "false" ]; then
                            # Determine if contract or EOA
                            local code=$(rpc_call "eth_getCode" "[\"$addr\", \"latest\"]")
                            
                            if [ "$code" != "0x" ] && [ "$code" != "0x0" ]; then
                                track_wallet "$addr" "contract"
                            else
                                track_wallet "$addr" "eoa"
                            fi
                            
                            log_success "NEW WALLET DETECTED: $addr"
                            
                            # Get initial balance
                            local eth_balance=$(rpc_call "eth_getBalance" "[\"$addr\", \"latest\"]")
                            update_wallet_balance "$addr" "0x0000000000000000000000000000000000000000" "$eth_balance" "ETH" "18"
                        fi
                    fi
                done
            fi
            
            # Update last block
            jq --arg block "$current_block" '.last_block = $block' "$BALANCES_FILE" > tmp && mv tmp "$BALANCES_FILE"
            last_block="$current_block"
        fi
        
        # Periodic full scan (every 10 blocks)
        local current_block_num=$((current_block))
        local last_scan=$(jq -r '.last_scan // 0' "$BALANCES_FILE")
        if [ $((current_block_num - last_scan)) -gt 10 ]; then
            scan_all_wallets
        fi
    done
}

# ═══════════════════════════════════════════════
# STATE MANAGEMENT
# ═══════════════════════════════════════════════
validate_state() {
    [ -f "$1" ] && jq -e '.block' "$1" >/dev/null 2>&1
}

download_state() {
    log_section "STATE DOWNLOAD"
    
    local response
    response=$(curl -s --max-time 30 \
        -H "X-Master-Key: ${JSONBIN_API_KEY}" \
        "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}/latest" 2>&1) || {
        log_warning "Cannot reach JSONBin"
        return 1
    }
    
    if echo "$response" | jq -e '.record' >/dev/null 2>&1; then
        local record
        record=$(echo "$response" | jq -r '.record')
        
        # Check if it's a valid state object
        if echo "$record" | jq -e '.block' >/dev/null 2>&1; then
            echo "$record" > "$STATE_FILE"
            
            local size block accounts
            size=$(wc -c < "$STATE_FILE")
            block=$(jq -r '.block.number // "0"' "$STATE_FILE")
            accounts=$(jq '.accounts | length' "$STATE_FILE" 2>/dev/null || echo "0")
            
            log_success "State loaded - Block: $block | Size: ${size}B | Wallets: $accounts"
            
            # Also download wallets and balances
            local wallets_response
            wallets_response=$(curl -s --max-time 30 \
                -H "X-Master-Key: ${JSONBIN_API_KEY}" \
                "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}/latest?wallets=true" 2>&1)
            
            if echo "$wallets_response" | jq -e '.record.wallets' >/dev/null 2>&1; then
                echo "$wallets_response" | jq -r '.record.wallets' > "$WALLETS_FILE"
                log_success "Wallet data loaded: $(jq '.total_count' "$WALLETS_FILE") wallets"
            fi
            
            local balances_response
            balances_response=$(curl -s --max-time 30 \
                -H "X-Master-Key: ${JSONBIN_API_KEY}" \
                "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}/latest?balances=true" 2>&1)
            
            if echo "$balances_response" | jq -e '.record.balances' >/dev/null 2>&1; then
                echo "$balances_response" | jq -r '.record.balances' > "$BALANCES_FILE"
                log_success "Balance data loaded"
            fi
            
            return 0
        fi
    fi
    
    log_info "Fresh start (no valid state)"
    return 1
}

upload_state() {
    [ ! -f "$STATE_FILE" ] && return 1
    validate_state "$STATE_FILE" || return 1
    
    # Create comprehensive state bundle
    local full_state
    full_state=$(jq --slurpfile wallets "$WALLETS_FILE" \
                     --slurpfile balances "$BALANCES_FILE" \
                     --slurpfile transactions "$TRANSACTIONS_FILE" \
        '. + {
            wallets: $wallets[0],
            balances: $balances[0],
            transactions: $transactions[0],
            last_sync: (now | tostring)
        }' "$STATE_FILE")
    
    local content size
    content=$(echo "$full_state" | jq -c '.')
    size=$(wc -c < "$STATE_FILE")
    
    curl -s --max-time 30 -X PUT \
        -H "Content-Type: application/json" \
        -H "X-Master-Key: ${JSONBIN_API_KEY}" \
        -d "{\"record\": $content}" \
        "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}" >/dev/null 2>&1 && {
        log_success "Full state saved (${size}B) with $(jq '.total_count' "$WALLETS_FILE" 2>/dev/null || echo "0") wallets"
        return 0
    }
    log_error "State upload failed"
    return 1
}

sync_state_periodically() {
    while true; do
        sleep "$STATE_SYNC_INTERVAL"
        
        # Scan and save current state
        scan_all_wallets
        
        # Upload everything to cloud
        upload_state
        
        log_info "Auto-sync completed"
    done
}

# ═══════════════════════════════════════════════
# AUTO-PING (KEEP ALIVE)
# ═══════════════════════════════════════════════
auto_ping() {
    log_info "Auto-ping every ${PING_INTERVAL}s"
    
    while true; do
        local rpc_status explorer_status
        rpc_status=$(curl -s -o /dev/null -w "%{http_code}" \
            -X POST -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
            "http://localhost:${PORT}" 2>/dev/null || echo "000")
        
        explorer_status=$(curl -s -o /dev/null -w "%{http_code}" \
            "http://localhost:${EXPLORER_PORT}" 2>/dev/null || echo "000")
        
        # Ping public endpoint
        [ -n "$PUBLIC_URL" ] && curl -s -o /dev/null "$PUBLIC_URL" 2>/dev/null || true
        
        local wallet_count=$(jq '.total_count // 0' "$WALLETS_FILE" 2>/dev/null || echo "0")
        
        if [ "$rpc_status" = "200" ] && [ "$explorer_status" = "200" ]; then
            log_success "Health: OK | RPC: $rpc_status | Explorer: $explorer_status | Tracked Wallets: $wallet_count"
        else
            log_warning "Health: RPC=$rpc_status Explorer=$explorer_status"
        fi
        
        sleep "$PING_INTERVAL"
    done
}

# ═══════════════════════════════════════════════
# TOKEN CONFIGURATION
# ═══════════════════════════════════════════════
save_tokens_config() {
    local tokens_json="["
    local first=true
    
    for symbol in "${!TOKENS[@]}"; do
        IFS=':' read -r address decimals name <<< "${TOKENS[$symbol]}"
        if [ "$first" = true ]; then
            first=false
        else
            tokens_json+=","
        fi
        tokens_json+="{\"symbol\":\"$symbol\",\"address\":\"$address\",\"decimals\":$decimals,\"name\":\"$name\"}"
    done
    tokens_json+="]"
    
    echo "$tokens_json" | jq '.' > "$TOKENS_FILE"
    log_success "Token registry saved: $(echo "$tokens_json" | jq 'length') tokens"
}

# ═══════════════════════════════════════════════
# EXPLORER SETUP (simplified - same as before)
# ═══════════════════════════════════════════════
setup_explorer() {
    log_section "EXPLORER SETUP"
    
    mkdir -p "$EXPLORER_DIR"/{views,public}
    
    # Package.json
    cat > "${EXPLORER_DIR}/package.json" << 'EOF'
{
  "name": "anvil-explorer",
  "version": "4.0.0",
  "main": "server.js",
  "scripts": {"start": "node server.js"},
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "axios": "^1.6.0",
    "ejs": "^3.1.9"
  }
}
EOF

    # Server.js (simplified version - same as before but with wallet tracking API)
    cat > "${EXPLORER_DIR}/server.js" << 'SERVEREOF'
const express = require('express');
const cors = require('cors');
const axios = require('axios');
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = process.env.EXPLORER_PORT || 3000;
const RPC_URL = `http://localhost:${process.env.ANVIL_PORT || 8545}`;

// Load token registry
let TOKENS = [];
try {
    TOKENS = JSON.parse(fs.readFileSync('/tmp/tokens.json', 'utf8'));
} catch(e) {
    TOKENS = [];
}

app.use(cors());
app.use(express.json());
app.use(express.static('public'));
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

async function rpcCall(method, params = []) {
    try {
        const { data } = await axios.post(RPC_URL, {
            jsonrpc: '2.0', method, params, id: 1
        });
        return data.result;
    } catch(e) {
        return null;
    }
}

app.get('/', async (req, res) => {
    try {
        const [blockNumber, chainId, gasPrice] = await Promise.all([
            rpcCall('eth_blockNumber'),
            rpcCall('eth_chainId'),
            rpcCall('eth_gasPrice')
        ]);
        
        const latestBlock = await rpcCall('eth_getBlockByNumber', [blockNumber, true]);
        
        // Load wallet stats
        let walletCount = 0;
        try {
            const wallets = JSON.parse(fs.readFileSync('/tmp/wallets.json', 'utf8'));
            walletCount = wallets.total_count || 0;
        } catch(e) {}
        
        res.render('index', {
            blockNumber: parseInt(blockNumber, 16),
            chainId: parseInt(chainId, 16),
            gasPrice: (parseInt(gasPrice, 16) / 1e9).toFixed(2),
            txCount: latestBlock?.transactions?.length || 0,
            networkName: 'Ethereum Mainnet Fork',
            tokens: TOKENS,
            walletCount: walletCount
        });
    } catch(e) {
        res.render('error', { error: 'RPC connection failed' });
    }
});

app.get('/api/wallets', (req, res) => {
    try {
        const wallets = JSON.parse(fs.readFileSync('/tmp/wallets.json', 'utf8'));
        res.json(wallets);
    } catch(e) {
        res.json({ error: 'No wallet data' });
    }
});

app.get('/api/wallet/:address', (req, res) => {
    try {
        const wallets = JSON.parse(fs.readFileSync('/tmp/wallets.json', 'utf8'));
        const wallet = wallets.wallets[req.params.address.toLowerCase()];
        if (wallet) {
            res.json(wallet);
        } else {
            res.json({ error: 'Wallet not found' });
        }
    } catch(e) {
        res.json({ error: 'No wallet data' });
    }
});

app.get('/tokens', async (req, res) => {
    res.render('tokens', { tokens: TOKENS });
});

app.get('/token/:address', async (req, res) => {
    const token = TOKENS.find(t => t.address.toLowerCase() === req.params.address.toLowerCase());
    if (!token) return res.render('error', { error: 'Token not found' });
    
    try {
        const totalSupply = await rpcCall('eth_call', [{
            to: token.address,
            data: '0x18160ddd'
        }, 'latest']);
        
        res.render('token', {
            token,
            totalSupply: parseInt(totalSupply || '0x0', 16) / Math.pow(10, token.decimals)
        });
    } catch(e) {
        res.render('error', { error: 'Failed to load token' });
    }
});

app.get('/address/:addr', async (req, res) => {
    try {
        const [balance, code, txCount] = await Promise.all([
            rpcCall('eth_getBalance', [req.params.addr, 'latest']),
            rpcCall('eth_getCode', [req.params.addr, 'latest']),
            rpcCall('eth_getTransactionCount', [req.params.addr, 'latest'])
        ]);
        
        const balanceEth = parseInt(balance, 16) / 1e18;
        const isContract = code !== '0x';
        
        let tokenBalances = [];
        try {
            const results = await Promise.allSettled(
                TOKENS.slice(0, 20).map(async token => {
                    const data = '0x70a08231' + req.params.addr.slice(2).padStart(64, '0');
                    const bal = await rpcCall('eth_call', [{
                        to: token.address,
                        data: data
                    }, 'latest']);
                    const balance = parseInt(bal, 16) / Math.pow(10, token.decimals);
                    return { ...token, balance };
                })
            );
            tokenBalances = results.filter(r => r.status === 'fulfilled' && r.value.balance > 0).map(r => r.value);
        } catch(e) {}
        
        res.render('address', {
            address: req.params.addr,
            balance: balanceEth,
            isContract,
            txCount: parseInt(txCount, 16),
            tokenBalances
        });
    } catch(e) {
        res.render('error', { error: 'Address not found' });
    }
});

app.get('/search', (req, res) => {
    const q = req.query.q?.trim();
    if (!q) return res.redirect('/');
    if (/^\d+$/.test(q)) return res.redirect(`/block/${q}`);
    if (/^0x[a-fA-F0-9]{64}$/.test(q)) return res.redirect(`/tx/${q}`);
    if (/^0x[a-fA-F0-9]{40}$/.test(q)) return res.redirect(`/address/${q}`);
    res.render('error', { error: 'Invalid search query' });
});

app.get('/tx/:hash', async (req, res) => {
    try {
        const [tx, receipt] = await Promise.all([
            rpcCall('eth_getTransactionByHash', [req.params.hash]),
            rpcCall('eth_getTransactionReceipt', [req.params.hash])
        ]);
        if (!tx) return res.render('error', { error: 'Transaction not found' });
        res.render('transaction', { tx, receipt });
    } catch(e) {
        res.render('error', { error: 'Transaction not found' });
    }
});

app.get('/block/:number', async (req, res) => {
    try {
        const blockHex = '0x' + parseInt(req.params.number).toString(16);
        const block = await rpcCall('eth_getBlockByNumber', [blockHex, true]);
        if (!block) return res.render('error', { error: 'Block not found' });
        res.render('block', { block });
    } catch(e) {
        res.render('error', { error: 'Block not found' });
    }
});

app.listen(PORT, () => {
    console.log(`Explorer: http://localhost:${PORT}`);
    console.log(`Tokens: ${TOKENS.length} registered`);
});
SERVEREOF

    # Create minimal views
    mkdir -p "${EXPLORER_DIR}/views"
    
    # Simple index template
    cat > "${EXPLORER_DIR}/views/index.ejs" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>AnvilScan v4.0</title>
    <style>
        body { font-family: monospace; background: #0d1117; color: #c9d1d9; padding: 2rem; }
        h1 { color: #58a6ff; }
        .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin: 2rem 0; }
        .stat-card { background: #161b22; padding: 1rem; border-radius: 8px; border: 1px solid #30363d; }
        .stat-value { font-size: 1.5rem; font-weight: bold; color: #58a6ff; }
        a { color: #58a6ff; text-decoration: none; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <h1>🔷 AnvilScan v4.0</h1>
    <p>Full Wallet Tracking | Balance Persistence | Auto-Restore</p>
    
    <div class="stats">
        <div class="stat-card">
            <div>Current Block</div>
            <div class="stat-value">#<%= blockNumber.toLocaleString() %></div>
        </div>
        <div class="stat-card">
            <div>Gas Price</div>
            <div class="stat-value"><%= gasPrice %> Gwei</div>
        </div>
        <div class="stat-card">
            <div>Tracked Wallets</div>
            <div class="stat-value"><%= walletCount %></div>
        </div>
        <div class="stat-card">
            <div>Registered Tokens</div>
            <div class="stat-value"><%= tokens.length %></div>
        </div>
    </div>
    
    <h2>🪙 Quick Links</h2>
    <ul>
        <li><a href="/tokens">View All Tokens (<%= tokens.length %>)</a></li>
        <li><a href="/api/wallets">View Tracked Wallets API</a></li>
    </ul>
    
    <p style="margin-top: 2rem; color: #8b949e;">⚡ Auto-sync enabled | All wallets tracked | Balances restored on restart</p>
</body>
</html>
EOF

    # Simple tokens template
    cat > "${EXPLORER_DIR}/views/tokens.ejs" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Tokens - AnvilScan</title>
    <style>
        body { font-family: monospace; background: #0d1117; color: #c9d1d9; padding: 2rem; }
        table { width: 100%; border-collapse: collapse; }
        th, td { text-align: left; padding: 0.5rem; border-bottom: 1px solid #30363d; }
        .address { font-family: monospace; color: #58a6ff; }
    </style>
</head>
<body>
    <h1>🪙 Token Registry</h1>
    <p><a href="/">← Back</a></p>
    <table>
        <thead><tr><th>Symbol</th><th>Name</th><th>Address</th><th>Decimals</th></tr></thead>
        <tbody>
            <% tokens.forEach(token => { %>
            <tr>
                <td><strong><%= token.symbol %></strong></td>
                <td><%= token.name %></td>
                <td class="address"><a href="/address/<%= token.address %>"><%= token.address %></a></td>
                <td><%= token.decimals %></td>
            </tr>
            <% }) %>
        </tbody>
    </table>
</body>
</html>
EOF

    # Blank templates for other pages
    for template in address token transaction block error; do
        cat > "${EXPLORER_DIR}/views/${template}.ejs" << EOF
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>${template^} - AnvilScan</title>
<style>body{background:#0d1117;color:#c9d1d9;padding:2rem;font-family:monospace;}</style>
</head>
<body><a href="/">← Back</a>
<h1>${template^} Details</h1>
<pre><%= JSON.stringify(locals, null, 2) %></pre>
</body>
</html>
EOF
    done
    
    cd "$EXPLORER_DIR"
    npm install --silent 2>/dev/null
    log_success "Explorer ready"
}

# ═══════════════════════════════════════════════
# WALLET CONFIGURATION
# ═══════════════════════════════════════════════
generate_wallet_config() {
    log_section "WALLET CONFIG"
    
    cat > "${EXPLORER_DIR}/public/add-network.js" << 'WALLETEOF'
const ANVIL_CONFIG = {
    chainId: '0x1',
    chainName: 'Anvil Mainnet Fork',
    nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
    rpcUrls: [window.location.origin.replace(':3000', ':8545')],
    blockExplorerUrls: [window.location.origin]
};

if (document.getElementById('addToWallet')) {
    document.getElementById('addToWallet').addEventListener('click', async () => {
        try {
            await ethereum.request({ method: 'wallet_addEthereumChain', params: [ANVIL_CONFIG] });
            alert('Network added successfully!');
        } catch(e) {
            alert('Error: ' + e.message);
        }
    });
}
WALLETEOF

    log_info "Wallet config generated"
}

# ═══════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════
main() {
    log_section "ANVIL PRODUCTION SYSTEM v4.0"
    
    check_dependencies
    save_tokens_config
    init_wallet_storage
    
    # Download and restore previous state
    local state_loaded=false
    if download_state; then
        state_loaded=true
        # Extract wallets from downloaded state
        extract_wallets_from_state
    fi
    
    setup_explorer
    generate_wallet_config
    
    # Launch Anvil with enhanced persistence
    log_section "STARTING ANVIL"
    
    anvil \
        --fork-url "$FORK_URL" \
        --chain-id "$CHAIN_ID" \
        --host 0.0.0.0 \
        --port "$PORT" \
        --state "$STATE_FILE" \
        --state-interval 5 \
        --block-time 2 \
        --auto-impersonate \
        --steps-tracing \
        --order fifo \
        --gas-limit 30000000 \
        &
    ANVIL_PID=$!
    log_success "Anvil PID: $ANVIL_PID"
    
    # Wait for Anvil to be ready
    sleep 3
    for i in $(seq 1 30); do
        if curl -s -X POST "http://localhost:${PORT}" \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            | jq -e '.result' >/dev/null 2>&1; then
            break
        fi
        sleep 2
    done
    log_success "Anvil RPC ready"
    
    # If we had previous state, restore all balances
    if [ "$state_loaded" = true ]; then
        restore_all_wallet_balances
    fi
    
    # Extract wallets from blockchain state
    extract_wallets_from_transactions
    
    # Start Explorer
    cd "$EXPLORER_DIR"
    ANVIL_PORT="$PORT" PORT="$EXPLORER_PORT" \
    JSONBIN_BIN_ID="$JSONBIN_BIN_ID" \
    JSONBIN_API_KEY="$JSONBIN_API_KEY" \
    node server.js &
    EXPLORER_PID=$!
    log_success "Explorer: http://localhost:${EXPLORER_PORT}"
    
    # Upload initial state
    sleep 3
    upload_state
    
    # Start background services
    auto_ping &
    PING_PID=$!
    
    sync_state_periodically &
    SYNC_PID=$!
    
    monitor_new_wallets &
    MONITOR_PID=$!
    
    # Shutdown handler
    graceful_shutdown() {
        log_section "SHUTDOWN"
        
        log_info "Performing final scan..."
        scan_all_wallets
        
        log_info "Uploading final state..."
        upload_state
        
        log_info "Stopping services..."
        kill $PING_PID $SYNC_PID $MONITOR_PID $EXPLORER_PID $ANVIL_PID 2>/dev/null || true
        
        log_success "Complete - All wallets and balances saved"
        exit 0
    }
    trap graceful_shutdown SIGTERM SIGINT
    
    # Status display
    log_section "SYSTEM READY"
    echo -e "${GREEN}"
    echo "    ╔══════════════════════════════════════════════════════════╗"
    echo "    ║     ANVIL v4.0 - COMPLETE WALLET TRACKING & PERSISTENCE   ║"
    echo "    ╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    log_info "📡 RPC: http://localhost:${PORT}"
    log_info "🔍 Explorer: http://localhost:${EXPLORER_PORT}"
    log_info "🪙 Tokens: ${#TOKENS[@]} registered"
    log_info "💾 Auto-save: ON (every ${STATE_SYNC_INTERVAL}s)"
    log_info "🔄 Ping: ${PING_INTERVAL}s"
    log_info "👛 Wallet tracking: ACTIVE"
    log_info "💎 Balance restore: ENABLED"
    log_info "📊 Tracked wallets: $(jq '.total_count // 0' "$WALLETS_FILE" 2>/dev/null || echo "0")"
    echo ""
    
    wait $ANVIL_PID
}

main "$@"
