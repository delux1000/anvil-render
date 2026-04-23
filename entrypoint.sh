#!/bin/bash

# ═══════════════════════════════════════════════════════════
# ANVIL PERSISTENCE SYSTEM WITH EXPLORER & AUTO-PING
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
TRANSACTIONS_FILE="/tmp/transactions.json"
LOG_FILE="/tmp/anvil-system.log"
PING_INTERVAL=30
EXPLORER_DIR="/app/explorer"
PUBLIC_URL="${PUBLIC_URL:-https://anvil-render-q5wl.onrender.com}"

# ═══════════════════════════════════════════════
# COLOR CODES FOR LOGGING
# ═══════════════════════════════════════════════
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# ═══════════════════════════════════════════════
# LOGGING FUNCTIONS
# ═══════════════════════════════════════════════
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${1}" | tee -a "$LOG_FILE"
}

log_info() { log "${BLUE}[INFO]${NC} $1"; }
log_success() { log "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { log "${YELLOW}[WARNING]${NC} $1"; }
log_error() { log "${RED}[ERROR]${NC} $1"; }
log_section() { 
    echo -e "\n${PURPLE}════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
    log "${CYAN}$1${NC}"
    echo -e "${PURPLE}════════════════════════════════════════${NC}\n" | tee -a "$LOG_FILE"
}

# ═══════════════════════════════════════════════
# DEPENDENCY CHECK
# ═══════════════════════════════════════════════
check_dependencies() {
    log_section "CHECKING DEPENDENCIES"
    
    local missing=()
    for cmd in curl jq anvil python3 npm node; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        log_info "Installing missing dependencies..."
        apt-get update -qq && apt-get install -y -qq curl jq python3 nodejs npm 2>/dev/null || {
            log_error "Failed to install dependencies"
            exit 1
        }
    fi
    log_success "All dependencies available"
}

# ═══════════════════════════════════════════════
# JSONBIN STATE MANAGEMENT
# ═══════════════════════════════════════════════
validate_state() {
    [ -f "$1" ] && jq -e '.block' "$1" >/dev/null 2>&1
}

download_state() {
    log_section "DOWNLOADING PREVIOUS STATE"
    
    local response
    response=$(curl -s --max-time 30 \
        -H "X-Master-Key: ${JSONBIN_API_KEY}" \
        "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}/latest" 2>&1) || {
        log_warning "Failed to connect to JSONBin"
        return 1
    }
    
    if echo "$response" | jq -e '.record' >/dev/null 2>&1; then
        echo "$response" | jq -r '.record' > "$STATE_FILE"
        
        if validate_state "$STATE_FILE"; then
            local size block wallet_count
            size=$(wc -c < "$STATE_FILE")
            block=$(jq -r '.block.number // .block' "$STATE_FILE" 2>/dev/null || echo "unknown")
            wallet_count=$(jq '.accounts | length' "$STATE_FILE" 2>/dev/null || echo "0")
            
            log_success "State loaded successfully"
            log_info "  • Block: $block"
            log_info "  • Size: ${size} bytes"
            log_info "  • Wallets: $wallet_count"
            return 0
        else
            rm -f "$STATE_FILE"
            log_warning "Downloaded state is invalid"
            return 1
        fi
    else
        log_info "No previous state found (fresh start)"
        return 1
    fi
}

upload_state() {
    [ ! -f "$STATE_FILE" ] && { log_warning "No state file to upload"; return 1; }
    validate_state "$STATE_FILE" || { log_warning "State file invalid"; return 1; }
    
    local state_content size accounts response
    state_content=$(cat "$STATE_FILE")
    size=$(wc -c < "$STATE_FILE")
    accounts=$(jq '.accounts | length' "$STATE_FILE" 2>/dev/null || echo "0")
    
    response=$(curl -s --max-time 30 -X PUT \
        -H "Content-Type: application/json" \
        -H "X-Master-Key: ${JSONBIN_API_KEY}" \
        -d "{\"record\": $state_content}" \
        "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}" 2>&1) || {
        log_error "Upload failed: network error"
        return 1
    }
    
    if echo "$response" | jq -e '.record' >/dev/null 2>&1; then
        log_success "State uploaded (${size} bytes, ${accounts} wallets)"
        return 0
    else
        log_error "Upload failed: invalid response"
        return 1
    fi
}

# ═══════════════════════════════════════════════
# TRANSACTION MONITORING & STORAGE
# ═══════════════════════════════════════════════
init_transactions_db() {
    [ ! -f "$TRANSACTIONS_FILE" ] && echo '{"transactions":[]}' > "$TRANSACTIONS_FILE"
}

save_transaction() {
    local tx_hash="$1" from="$2" to="$3" value="$4" block="$5" input="$6"
    
    local tx_json
    tx_json=$(jq -n \
        --arg hash "$tx_hash" \
        --arg from "$from" \
        --arg to "$to" \
        --arg value "$value" \
        --arg block "$block" \
        --arg input "$input" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            hash: $hash,
            from: $from,
            to: $to,
            value: $value,
            blockNumber: $block,
            input: $input,
            timestamp: $timestamp
        }')
    
    # Add to local DB
    local temp_file="${TRANSACTIONS_FILE}.tmp"
    jq --argjson tx "$tx_json" '.transactions = [$tx] + .transactions[:999]' \
        "$TRANSACTIONS_FILE" > "$temp_file" && mv "$temp_file" "$TRANSACTIONS_FILE"
    
    # Upload to JSONBin separately
    upload_transactions_to_jsonbin
}

upload_transactions_to_jsonbin() {
    [ ! -f "$TRANSACTIONS_FILE" ] && return 1
    
    local tx_content response
    tx_content=$(cat "$TRANSACTIONS_FILE")
    
    response=$(curl -s --max-time 30 -X PUT \
        -H "Content-Type: application/json" \
        -H "X-Master-Key: ${JSONBIN_API_KEY}" \
        -d "{\"record\": $tx_content}" \
        "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}/transactions" 2>/dev/null) || true
}

monitor_transactions() {
    log_section "TRANSACTION MONITOR"
    log_info "Watching for new transactions..."
    
    local last_block="0x0"
    
    while true; do
        local current_block
        current_block=$(curl -s -X POST "http://localhost:${PORT}" \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            | jq -r '.result // "0x0"')
        
        if [ "$current_block" != "$last_block" ] && [ "$current_block" != "0x0" ]; then
            local block_hex=$((16#${current_block#0x}))
            local prev_block_hex=$((16#${last_block#0x}))
            
            if [ "$block_hex" -gt "$prev_block_hex" ]; then
                log_info "🔗 New block: ${last_block} → ${current_block}"
                
                # Get block details
                local block_data
                block_data=$(curl -s -X POST "http://localhost:${PORT}" \
                    -H "Content-Type: application/json" \
                    -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$current_block\",true],\"id\":1}")
                
                # Extract transactions
                local tx_count
                tx_count=$(echo "$block_data" | jq '.result.transactions | length')
                
                if [ "$tx_count" -gt 0 ]; then
                    for i in $(seq 0 $((tx_count - 1))); do
                        local tx
                        tx=$(echo "$block_data" | jq -r ".result.transactions[$i]")
                        
                        local tx_hash from to value input
                        tx_hash=$(echo "$tx" | jq -r '.hash')
                        from=$(echo "$tx" | jq -r '.from')
                        to=$(echo "$tx" | jq -r '.to // "Contract Creation"')
                        value=$(echo "$tx" | jq -r '.value')
                        input=$(echo "$tx" | jq -r '.input')
                        
                        # Convert hex value to ETH
                        local value_eth
                        value_eth=$(python3 -c "print(float(int('$value', 16)) / 1e18)" 2>/dev/null || echo "0")
                        
                        save_transaction "$tx_hash" "$from" "$to" "$value_eth" "$block_hex" "${input:0:66}..."
                        log_info "  📝 TX: ${tx_hash:0:10}... | ${value_eth} ETH"
                    done
                fi
                
                # Upload state on new block
                upload_state
                last_block="$current_block"
            fi
        fi
        
        sleep 2
    done
}

# ═══════════════════════════════════════════════
# AUTO-PING SYSTEM
# ═══════════════════════════════════════════════
auto_ping() {
    log_section "AUTO-PING SYSTEM"
    log_info "Pinging every ${PING_INTERVAL}s to keep alive..."
    
    while true; do
        local timestamp
        timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        
        # Ping self
        local self_response
        self_response=$(curl -s -o /dev/null -w "%{http_code}" \
            "http://localhost:${PORT}" \
            -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
            2>/dev/null || echo "000")
        
        # Ping explorer
        local explorer_response
        explorer_response=$(curl -s -o /dev/null -w "%{http_code}" \
            "http://localhost:${EXPLORER_PORT}" \
            2>/dev/null || echo "000")
        
        # Ping public URL if set
        if [ -n "$PUBLIC_URL" ]; then
            curl -s -o /dev/null "$PUBLIC_URL" 2>/dev/null || true
        fi
        
        # Health check logging
        if [ "$self_response" = "200" ] && [ "$explorer_response" = "200" ]; then
            log_success "💚 Health Check OK | RPC: ${self_response} | Explorer: ${explorer_response} | ${timestamp}"
        else
            log_warning "💛 Health Check | RPC: ${self_response} | Explorer: ${explorer_response}"
        fi
        
        sleep "$PING_INTERVAL"
    done
}

# ═══════════════════════════════════════════════
# BLOCKCHAIN EXPLORER SETUP
# ═══════════════════════════════════════════════
setup_explorer() {
    log_section "SETTING UP BLOCKCHAIN EXPLORER"
    
    mkdir -p "$EXPLORER_DIR"
    
    # Create package.json
    cat > "${EXPLORER_DIR}/package.json" << 'PACKAGEJSON'
{
  "name": "anvil-explorer",
  "version": "1.0.0",
  "description": "Etherscan-like explorer for Anvil chain",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "axios": "^1.6.0",
    "ejs": "^3.1.9"
  }
}
PACKAGEJSON
    
    # Create server.js
    cat > "${EXPLORER_DIR}/server.js" << 'SERVERJS'
const express = require('express');
const cors = require('cors');
const axios = require('axios');
const path = require('path');
const app = express();
const PORT = process.env.EXPLORER_PORT || 3000;
const RPC_URL = `http://localhost:${process.env.PORT || 8545}`;
const JSONBIN_BIN_ID = process.env.JSONBIN_BIN_ID || '6936f28bae596e708f8bafc0';
const JSONBIN_API_KEY = process.env.JSONBIN_API_KEY;

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static('public'));
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

// Helper: RPC Call
async function rpcCall(method, params = []) {
    try {
        const response = await axios.post(RPC_URL, {
            jsonrpc: '2.0',
            method,
            params,
            id: 1
        });
        return response.data.result;
    } catch (error) {
        return null;
    }
}

// Routes
app.get('/', async (req, res) => {
    try {
        const blockNumber = await rpcCall('eth_blockNumber');
        const chainId = await rpcCall('eth_chainId');
        const gasPrice = await rpcCall('eth_gasPrice');
        
        const latestBlock = await rpcCall('eth_getBlockByNumber', [blockNumber, true]);
        const txCount = latestBlock ? latestBlock.transactions.length : 0;
        
        res.render('index', {
            blockNumber: parseInt(blockNumber, 16),
            chainId: parseInt(chainId, 16),
            gasPrice: parseInt(gasPrice, 16) / 1e9,
            txCount,
            networkName: 'Anvil Fork',
            rpcUrl: RPC_URL
        });
    } catch (error) {
        res.render('error', { error: 'Failed to connect to RPC' });
    }
});

app.get('/block/:number', async (req, res) => {
    try {
        const blockHex = '0x' + parseInt(req.params.number).toString(16);
        const block = await rpcCall('eth_getBlockByNumber', [blockHex, true]);
        
        if (!block) {
            return res.render('error', { error: 'Block not found' });
        }
        
        res.render('block', { block });
    } catch (error) {
        res.render('error', { error: 'Block not found' });
    }
});

app.get('/tx/:hash', async (req, res) => {
    try {
        const tx = await rpcCall('eth_getTransactionByHash', [req.params.hash]);
        const receipt = await rpcCall('eth_getTransactionReceipt', [req.params.hash]);
        
        if (!tx) {
            return res.render('error', { error: 'Transaction not found' });
        }
        
        res.render('transaction', { tx, receipt });
    } catch (error) {
        res.render('error', { error: 'Transaction not found' });
    }
});

app.get('/address/:addr', async (req, res) => {
    try {
        const balance = await rpcCall('eth_getBalance', [req.params.addr, 'latest']);
        const code = await rpcCall('eth_getCode', [req.params.addr, 'latest']);
        const txCount = await rpcCall('eth_getTransactionCount', [req.params.addr, 'latest']);
        
        const balanceEth = parseInt(balance, 16) / 1e18;
        const isContract = code !== '0x';
        
        // Get recent transactions for this address from JSONBin
        let recentTxs = [];
        try {
            const response = await axios.get(
                `https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}/latest`,
                { headers: { 'X-Master-Key': JSONBIN_API_KEY } }
            );
            const allTxs = response.data.record.transactions || [];
            recentTxs = allTxs.filter(tx => 
                tx.from.toLowerCase() === req.params.addr.toLowerCase() ||
                (tx.to && tx.to.toLowerCase() === req.params.addr.toLowerCase())
            ).slice(0, 25);
        } catch (e) {
            // Ignore JSONBin errors
        }
        
        res.render('address', {
            address: req.params.addr,
            balance: balanceEth,
            isContract,
            txCount: parseInt(txCount, 16),
            recentTxs
        });
    } catch (error) {
        res.render('error', { error: 'Address not found' });
    }
});

app.get('/search', async (req, res) => {
    const query = req.query.q;
    if (!query) return res.redirect('/');
    
    // Check if it's a block number
    if (/^\d+$/.test(query)) {
        return res.redirect(`/block/${query}`);
    }
    
    // Check if it's a transaction hash
    if (/^0x[a-fA-F0-9]{64}$/.test(query)) {
        return res.redirect(`/tx/${query}`);
    }
    
    // Check if it's an address
    if (/^0x[a-fA-F0-9]{40}$/.test(query)) {
        return res.redirect(`/address/${query}`);
    }
    
    res.render('error', { error: 'Invalid search query' });
});

// API Endpoints
app.get('/api/status', async (req, res) => {
    const blockNumber = await rpcCall('eth_blockNumber');
    const chainId = await rpcCall('eth_chainId');
    
    res.json({
        status: 'ok',
        blockNumber: parseInt(blockNumber, 16),
        chainId: parseInt(chainId, 16),
        timestamp: new Date().toISOString()
    });
});

app.get('/api/transactions', async (req, res) => {
    try {
        const response = await axios.get(
            `https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}/latest`,
            { headers: { 'X-Master-Key': JSONBIN_API_KEY } }
        );
        const transactions = response.data.record.transactions || [];
        
        const page = parseInt(req.query.page) || 1;
        const limit = parseInt(req.query.limit) || 25;
        const start = (page - 1) * limit;
        
        res.json({
            total: transactions.length,
            page,
            limit,
            transactions: transactions.slice(start, start + limit)
        });
    } catch (error) {
        res.json({ transactions: [], total: 0 });
    }
});

app.listen(PORT, () => {
    console.log(`🔍 Explorer running on port ${PORT}`);
    console.log(`📡 Connected to RPC: ${RPC_URL}`);
});
SERVERJS
    
    # Create views directory and templates
    mkdir -p "${EXPLORER_DIR}/views"
    mkdir -p "${EXPLORER_DIR}/public"
    
    # Create main layout
    cat > "${EXPLORER_DIR}/views/index.ejs" << 'INDEXEJS'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AnvilScan - Blockchain Explorer</title>
    <style>
        :root {
            --bg-primary: #0d1117;
            --bg-secondary: #161b22;
            --bg-tertiary: #21262d;
            --text-primary: #c9d1d9;
            --text-secondary: #8b949e;
            --accent-blue: #58a6ff;
            --accent-green: #3fb950;
            --accent-purple: #bc8cff;
            --border: #30363d;
            --danger: #f85149;
        }
        
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: var(--bg-primary);
            color: var(--text-primary);
            line-height: 1.6;
        }
        
        .header {
            background: var(--bg-secondary);
            border-bottom: 1px solid var(--border);
            padding: 1rem 2rem;
            position: sticky;
            top: 0;
            z-index: 100;
        }
        
        .header-content {
            max-width: 1400px;
            margin: 0 auto;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        
        .logo {
            font-size: 1.5rem;
            font-weight: bold;
            color: var(--accent-blue);
            text-decoration: none;
            display: flex;
            align-items: center;
            gap: 0.5rem;
        }
        
        .logo-icon {
            font-size: 2rem;
        }
        
        .search-container {
            flex: 1;
            max-width: 600px;
            margin: 0 2rem;
        }
        
        .search-box {
            width: 100%;
            padding: 0.75rem 1rem;
            background: var(--bg-tertiary);
            border: 1px solid var(--border);
            border-radius: 8px;
            color: var(--text-primary);
            font-size: 0.95rem;
            transition: all 0.3s;
        }
        
        .search-box:focus {
            outline: none;
            border-color: var(--accent-blue);
            box-shadow: 0 0 0 3px rgba(88, 166, 255, 0.1);
        }
        
        .network-badge {
            background: var(--accent-green);
            color: #000;
            padding: 0.25rem 0.75rem;
            border-radius: 20px;
            font-size: 0.85rem;
            font-weight: 600;
        }
        
        .container {
            max-width: 1400px;
            margin: 2rem auto;
            padding: 0 2rem;
        }
        
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 1.5rem;
            margin-bottom: 2rem;
        }
        
        .stat-card {
            background: var(--bg-secondary);
            border: 1px solid var(--border);
            border-radius: 12px;
            padding: 1.5rem;
            transition: transform 0.2s;
        }
        
        .stat-card:hover {
            transform: translateY(-2px);
        }
        
        .stat-label {
            color: var(--text-secondary);
            font-size: 0.85rem;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            margin-bottom: 0.5rem;
        }
        
        .stat-value {
            font-size: 1.75rem;
            font-weight: bold;
            color: var(--accent-blue);
        }
        
        .transactions-section {
            background: var(--bg-secondary);
            border: 1px solid var(--border);
            border-radius: 12px;
            overflow: hidden;
        }
        
        .section-header {
            padding: 1.5rem;
            border-bottom: 1px solid var(--border);
            font-size: 1.2rem;
            font-weight: 600;
        }
        
        .tx-table {
            width: 100%;
            border-collapse: collapse;
        }
        
        .tx-table th {
            text-align: left;
            padding: 1rem 1.5rem;
            background: var(--bg-tertiary);
            color: var(--text-secondary);
            font-size: 0.85rem;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            border-bottom: 1px solid var(--border);
        }
        
        .tx-table td {
            padding: 1rem 1.5rem;
            border-bottom: 1px solid var(--border);
        }
        
        .tx-hash {
            color: var(--accent-blue);
            text-decoration: none;
            font-family: 'Courier New', monospace;
        }
        
        .tx-hash:hover {
            text-decoration: underline;
        }
        
        .address-link {
            color: var(--accent-purple);
            text-decoration: none;
            font-family: 'Courier New', monospace;
        }
        
        .address-link:hover {
            text-decoration: underline;
        }
        
        .value {
            font-weight: 600;
        }
        
        .value-in {
            color: var(--accent-green);
        }
        
        .badge {
            display: inline-block;
            padding: 0.25rem 0.75rem;
            border-radius: 12px;
            font-size: 0.8rem;
            font-weight: 600;
        }
        
        .badge-success {
            background: rgba(63, 185, 80, 0.1);
            color: var(--accent-green);
            border: 1px solid rgba(63, 185, 80, 0.2);
        }
        
        .no-data {
            text-align: center;
            padding: 3rem;
            color: var(--text-secondary);
        }
        
        .footer {
            text-align: center;
            padding: 2rem;
            color: var(--text-secondary);
            border-top: 1px solid var(--border);
            margin-top: 3rem;
        }
        
        @media (max-width: 768px) {
            .header-content {
                flex-direction: column;
                gap: 1rem;
            }
            
            .search-container {
                margin: 0;
                width: 100%;
            }
            
            .tx-table {
                font-size: 0.85rem;
            }
            
            .tx-table th:nth-child(5),
            .tx-table td:nth-child(5) {
                display: none;
            }
        }
    </style>
</head>
<body>
    <header class="header">
        <div class="header-content">
            <a href="/" class="logo">
                <span class="logo-icon">🔷</span>
                AnvilScan
            </a>
            
            <div class="search-container">
                <form action="/search" method="GET">
                    <input 
                        type="text" 
                        name="q" 
                        class="search-box" 
                        placeholder="Search by Address / Txn Hash / Block"
                        autocomplete="off"
                    >
                </form>
            </div>
            
            <span class="network-badge">
                ⚡ <%= networkName %> (Chain ID: <%= chainId %>)
            </span>
        </div>
    </header>
    
    <main class="container">
        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-label">Current Block</div>
                <div class="stat-value">#<%= blockNumber.toLocaleString() %></div>
            </div>
            
            <div class="stat-card">
                <div class="stat-label">Gas Price</div>
                <div class="stat-value"><%= gasPrice.toFixed(2) %> Gwei</div>
            </div>
            
            <div class="stat-card">
                <div class="stat-label">Latest Block TXs</div>
                <div class="stat-value"><%= txCount %></div>
            </div>
            
            <div class="stat-card">
                <div class="stat-label">Network</div>
                <div class="stat-value" style="font-size: 1.2rem;"><%= networkName %></div>
            </div>
        </div>
        
        <div class="transactions-section">
            <div class="section-header">🔍 Explore Blockchain</div>
            
            <div style="padding: 2rem;">
                <p style="color: var(--text-secondary); margin-bottom: 1rem;">
                    Enter an address, transaction hash, or block number in the search bar above to explore the chain.
                </p>
                
                <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-top: 2rem;">
                    <a href="/block/<%= blockNumber %>" style="text-decoration: none;">
                        <div class="stat-card" style="text-align: center;">
                            <div style="font-size: 2rem;">📦</div>
                            <div style="color: var(--accent-blue); margin-top: 0.5rem;">Latest Block</div>
                        </div>
                    </a>
                    
                    <a href="/address/0x0000000000000000000000000000000000000000" style="text-decoration: none;">
                        <div class="stat-card" style="text-align: center;">
                            <div style="font-size: 2rem;">🔥</div>
                            <div style="color: var(--accent-purple); margin-top: 0.5rem;">Zero Address</div>
                        </div>
                    </a>
                </div>
            </div>
        </div>
    </main>
    
    <footer class="footer">
        <p>AnvilScan - Local Blockchain Explorer | Connected to <%= rpcUrl %></p>
        <p style="margin-top: 0.5rem; font-size: 0.85rem;">
            Compatible with MetaMask, TokenPocket, MathWallet & other Web3 wallets
        </p>
    </footer>
</body>
</html>
INDEXEJS
    
    # Create other view templates (simplified for length)
    for template in block transaction address error; do
        cat > "${EXPLORER_DIR}/views/${template}.ejs" << TEMPLATE
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AnvilScan - ${template^}</title>
    <style>
        :root {
            --bg-primary: #0d1117;
            --bg-secondary: #161b22;
            --bg-tertiary: #21262d;
            --text-primary: #c9d1d9;
            --text-secondary: #8b949e;
            --accent-blue: #58a6ff;
            --border: #30363d;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            background: var(--bg-primary);
            color: var(--text-primary);
            margin: 0;
            padding: 2rem;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: var(--bg-secondary);
            border: 1px solid var(--border);
            border-radius: 12px;
            padding: 2rem;
        }
        h1 { color: var(--accent-blue); }
        .data-row {
            display: flex;
            justify-content: space-between;
            padding: 1rem 0;
            border-bottom: 1px solid var(--border);
        }
        .label { color: var(--text-secondary); }
        .value { font-family: 'Courier New', monospace; }
        a { color: var(--accent-blue); text-decoration: none; }
        a:hover { text-decoration: underline; }
        .back-link { margin-bottom: 1rem; display: inline-block; }
    </style>
</head>
<body>
    <div class="container">
        <a href="/" class="back-link">← Back to Home</a>
        <h1>${template^} Details</h1>
        <pre style="background: var(--bg-tertiary); padding: 1rem; border-radius: 8px; overflow-x: auto;">
<%= JSON.stringify(locals, null, 2) %>
        </pre>
    </div>
</body>
</html>
TEMPLATE
    done
    
    # Install dependencies and start explorer
    cd "$EXPLORER_DIR"
    npm install --silent 2>/dev/null || log_warning "npm install had warnings"
    
    log_success "Explorer setup complete"
}

# ═══════════════════════════════════════════════
# WALLET CONFIGURATION GENERATOR
# ═══════════════════════════════════════════════
generate_wallet_config() {
    log_section "WALLET CONFIGURATION"
    
    local chain_id_dec=$((CHAIN_ID))
    
    cat > /tmp/chain-config.json << WALLETCFG
{
    "chainId": "0x${chain_id_dec}",
    "chainName": "Anvil Fork",
    "nativeCurrency": {
        "name": "Ether",
        "symbol": "ETH",
        "decimals": 18
    },
    "rpcUrls": ["${PUBLIC_URL}"],
    "blockExplorerUrls": ["${PUBLIC_URL}:${EXPLORER_PORT}"]
}
WALLETCFG
    
    log_info "Wallet Configuration:"
    log_info "  Network Name: Anvil Fork"
    log_info "  RPC URL: ${PUBLIC_URL}"
    log_info "  Chain ID: ${CHAIN_ID}"
    log_info "  Currency: ETH"
    log_info "  Explorer: ${PUBLIC_URL}:${EXPLORER_PORT}"
    
    # For MetaMask, users can add this network manually
    cat > "${EXPLORER_DIR}/public/wallet-config.js" << 'WALLETJS'
// MetaMask Network Configuration
const ANVIL_NETWORK = {
    chainId: '0x1',
    chainName: 'Anvil Fork',
    nativeCurrency: {
        name: 'Ether',
        symbol: 'ETH',
        decimals: 18
    },
    rpcUrls: [window.location.origin],
    blockExplorerUrls: [window.location.origin + ':3000']
};

// Add network to wallet
async function addAnvilNetwork() {
    try {
        await window.ethereum.request({
            method: 'wallet_addEthereumChain',
            params: [ANVIL_NETWORK]
        });
        console.log('Anvil network added successfully!');
    } catch (error) {
        console.error('Failed to add network:', error);
    }
}
WALLETJS
}

# ═══════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════
main() {
    log_section "ANVIL PERSISTENCE SYSTEM v2.0"
    log_info "Initializing..."
    
    # Checks
    check_dependencies
    init_transactions_db
    
    # Download state
    local state_loaded=false
    download_state && state_loaded=true
    
    # Setup explorer
    setup_explorer
    
    # Generate wallet config
    generate_wallet_config
    
    # Launch Anvil
    log_section "STARTING ANVIL NODE"
    
    local anvil_cmd="anvil"
    anvil_cmd+=" --fork-url ${FORK_URL}"
    anvil_cmd+=" --chain-id ${CHAIN_ID}"
    anvil_cmd+=" --host 0.0.0.0"
    anvil_cmd+=" --port ${PORT}"
    anvil_cmd+=" --state ${STATE_FILE}"
    anvil_cmd+=" --state-interval 1"
    anvil_cmd+=" --block-time 2"
    
    if [ "$state_loaded" = true ]; then
        log_info "Starting with persisted state"
    else
        log_info "Starting fresh (no previous state)"
    fi
    
    $anvil_cmd &
    ANVIL_PID=$!
    log_success "Anvil started (PID: $ANVIL_PID)"
    
    # Wait for Anvil to be ready
    log_info "Waiting for Anvil to initialize..."
    sleep 3
    
    for i in $(seq 1 30); do
        if curl -s -X POST "http://localhost:${PORT}" \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            | jq -e '.result' >/dev/null 2>&1; then
            log_success "Anvil RPC is ready"
            break
        fi
        sleep 2
    done
    
    # Start Explorer
    log_section "STARTING EXPLORER"
    cd "$EXPLORER_DIR"
    PORT="$EXPLORER_PORT" JSONBIN_BIN_ID="$JSONBIN_BIN_ID" JSONBIN_API_KEY="$JSONBIN_API_KEY" \
        node server.js &
    EXPLORER_PID=$!
    log_success "Explorer started (PID: $EXPLORER_PID)"
    
    # Initial state upload
    sleep 2
    upload_state
    
    # Start services
    log_section "STARTING BACKGROUND SERVICES"
    
    # Transaction monitor
    monitor_transactions &
    MONITOR_PID=$!
    
    # Auto-ping
    auto_ping &
    PING_PID=$!
    
    # Graceful shutdown handler
    graceful_shutdown() {
        log_section "SHUTTING DOWN"
        log_info "Saving state..."
        upload_state
        log_info "Stopping services..."
        kill $MONITOR_PID $PING_PID $EXPLORER_PID $ANVIL_PID 2>/dev/null || true
        log_success "Shutdown complete"
        exit 0
    }
    
    trap graceful_shutdown SIGTERM SIGINT
    
    # Display system status
    log_section "🎯 SYSTEM READY"
    echo -e "${GREEN}"
    cat << "BANNER"
    ╔════════════════════════════════════════╗
    ║     ANVIL PERSISTENCE SYSTEM v2.0     ║
    ╚════════════════════════════════════════╝
BANNER
    echo -e "${NC}"
    log_info "📡 RPC Endpoint: http://localhost:${PORT}"
    log_info "🔍 Explorer: http://localhost:${EXPLORER_PORT}"
    log_info "💾 State: Auto-saved after each transaction"
    log_info "🔄 Ping: Every ${PING_INTERVAL}s"
    log_info "🔒 All balances & state preserved"
    log_info "💳 Wallet Compatible: MetaMask, TokenPocket, MathWallet"
    echo ""
    log_info "Press Ctrl+C to stop"
    echo ""
    
    # Wait for Anvil to exit
    wait $ANVIL_PID
}

# Execute
main "$@"
