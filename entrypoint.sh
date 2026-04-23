#!/bin/bash

# ═══════════════════════════════════════════════════════════
# ANVIL PRODUCTION SYSTEM v3.0
# Features: State Persistence, Explorer, Auto-Ping, Token Support
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
LOG_FILE="/tmp/anvil-system.log"
PING_INTERVAL=30
EXPLORER_DIR="/app/explorer"
PUBLIC_URL="${PUBLIC_URL:-https://anvil-render-q5wl.onrender.com}"

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
    ["AAVE"]="0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9:18:Aave Token"
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

# Store tokens configuration
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
            return 0
        fi
    fi
    
    log_info "Fresh start (no valid state)"
    return 1
}

upload_state() {
    [ ! -f "$STATE_FILE" ] && return 1
    validate_state "$STATE_FILE" || return 1
    
    local content size
    content=$(cat "$STATE_FILE")
    size=$(wc -c < "$STATE_FILE")
    
    curl -s --max-time 30 -X PUT \
        -H "Content-Type: application/json" \
        -H "X-Master-Key: ${JSONBIN_API_KEY}" \
        -d "{\"record\": $content}" \
        "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}" >/dev/null 2>&1 && {
        log_success "State saved (${size}B)"
        return 0
    }
    log_error "State upload failed"
    return 1
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
        
        if [ "$rpc_status" = "200" ] && [ "$explorer_status" = "200" ]; then
            log_success "Health: OK | RPC: $rpc_status | Explorer: $explorer_status"
        else
            log_warning "Health: RPC=$rpc_status Explorer=$explorer_status"
        fi
        
        sleep "$PING_INTERVAL"
    done
}

# ═══════════════════════════════════════════════
# EXPLORER SETUP
# ═══════════════════════════════════════════════
setup_explorer() {
    log_section "EXPLORER SETUP"
    
    mkdir -p "$EXPLORER_DIR"/{views,public}
    
    # Package.json
    cat > "${EXPLORER_DIR}/package.json" << 'EOF'
{
  "name": "anvil-explorer",
  "version": "3.0.0",
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

    # Server.js with full token support
    cat > "${EXPLORER_DIR}/server.js" << 'SERVEREOF'
const express = require('express');
const cors = require('cors');
const axios = require('axios');
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = process.env.EXPLORER_PORT || 3000;
const RPC_URL = `http://localhost:${process.env.ANVIL_PORT || 8545}`;
const BIN_ID = process.env.JSONBIN_BIN_ID || '6936f28bae596e708f8bafc0';
const API_KEY = process.env.JSONBIN_API_KEY || '';

// Token ABI (minimal for balanceOf)
const ERC20_ABI = [
    "function balanceOf(address) view returns (uint256)",
    "function decimals() view returns (uint8)",
    "function symbol() view returns (string)",
    "function name() view returns (string)",
    "function totalSupply() view returns (uint256)",
    "function transfer(address,uint256) returns (bool)",
    "function allowance(address,address) view returns (uint256)",
    "function approve(address,uint256) returns (bool)"
];

// Token registry
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

// RPC call helper
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

// Encode balanceOf call
function encodeBalanceOf(address) {
    const selector = '0x70a08231';
    const padded = address.toLowerCase().replace('0x', '').padStart(64, '0');
    return selector + padded;
}

// Get token balance
async function getTokenBalance(tokenAddress, walletAddress) {
    const data = encodeBalanceOf(walletAddress);
    const result = await rpcCall('eth_call', [{
        to: tokenAddress,
        data: data
    }, 'latest']);
    return result || '0x0';
}

// Routes
app.get('/', async (req, res) => {
    try {
        const [blockNumber, chainId, gasPrice] = await Promise.all([
            rpcCall('eth_blockNumber'),
            rpcCall('eth_chainId'),
            rpcCall('eth_gasPrice')
        ]);
        
        const latestBlock = await rpcCall('eth_getBlockByNumber', [blockNumber, true]);
        
        res.render('index', {
            blockNumber: parseInt(blockNumber, 16),
            chainId: parseInt(chainId, 16),
            gasPrice: (parseInt(gasPrice, 16) / 1e9).toFixed(2),
            txCount: latestBlock?.transactions?.length || 0,
            networkName: 'Ethereum Mainnet Fork',
            tokens: TOKENS
        });
    } catch(e) {
        res.render('error', { error: 'RPC connection failed' });
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
        
        // Get token balances for popular tokens
        let tokenBalances = [];
        try {
            const results = await Promise.allSettled(
                TOKENS.slice(0, 20).map(async token => {
                    const bal = await getTokenBalance(token.address, req.params.addr);
                    const balance = parseInt(bal, 16) / Math.pow(10, token.decimals);
                    return { ...token, balance };
                })
            );
            tokenBalances = results
                .filter(r => r.status === 'fulfilled' && r.value.balance > 0)
                .map(r => r.value);
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

app.get('/search', (req, res) => {
    const q = req.query.q?.trim();
    if (!q) return res.redirect('/');
    if (/^\d+$/.test(q)) return res.redirect(`/block/${q}`);
    if (/^0x[a-fA-F0-9]{64}$/.test(q)) return res.redirect(`/tx/${q}`);
    if (/^0x[a-fA-F0-9]{40}$/.test(q)) return res.redirect(`/address/${q}`);
    res.render('error', { error: 'Invalid search query' });
});

// API
app.get('/api/status', async (req, res) => {
    const [blockNumber, chainId] = await Promise.all([
        rpcCall('eth_blockNumber'),
        rpcCall('eth_chainId')
    ]);
    res.json({
        status: 'ok',
        blockNumber: parseInt(blockNumber, 16),
        chainId: parseInt(chainId, 16),
        tokens: TOKENS.length,
        timestamp: new Date().toISOString()
    });
});

app.get('/api/tokens', (req, res) => {
    res.json(TOKENS);
});

app.get('/api/balance/:address', async (req, res) => {
    try {
        const balances = {};
        for (const token of TOKENS.slice(0, 10)) {
            const bal = await getTokenBalance(token.address, req.params.address);
            const balance = parseInt(bal, 16) / Math.pow(10, token.decimals);
            if (balance > 0) balances[token.symbol] = balance;
        }
        res.json({ address: req.params.address, balances });
    } catch(e) {
        res.json({ error: 'Failed to fetch balances' });
    }
});

app.listen(PORT, () => {
    console.log(`Explorer: http://localhost:${PORT}`);
    console.log(`Tokens: ${TOKENS.length} registered`);
});
SERVEREOF

    # Create views
    create_explorer_views
    
    cd "$EXPLORER_DIR"
    npm install --silent 2>/dev/null
    log_success "Explorer ready"
}

create_explorer_views() {
    # Main index.ejs
    cat > "${EXPLORER_DIR}/views/index.ejs" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AnvilScan - Blockchain Explorer</title>
    <style>
        :root {
            --bg: #0d1117; --bg2: #161b22; --bg3: #21262d;
            --text: #c9d1d9; --text2: #8b949e;
            --blue: #58a6ff; --green: #3fb950; --purple: #bc8cff;
            --border: #30363d; --orange: #d2991d;
        }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: var(--bg); color: var(--text); line-height: 1.6; }
        .header { background: var(--bg2); border-bottom: 1px solid var(--border); padding: 1rem 2rem; }
        .header-inner { max-width: 1400px; margin: 0 auto; display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 1rem; }
        .logo { font-size: 1.5rem; font-weight: bold; color: var(--blue); text-decoration: none; }
        .search-box { flex: 1; max-width: 600px; }
        .search-box input { width: 100%; padding: 0.75rem 1rem; background: var(--bg3); border: 1px solid var(--border); border-radius: 8px; color: var(--text); font-size: 0.95rem; }
        .search-box input:focus { outline: none; border-color: var(--blue); }
        .badge { background: var(--green); color: #000; padding: 0.25rem 0.75rem; border-radius: 20px; font-size: 0.85rem; font-weight: 600; }
        .nav { background: var(--bg2); border-bottom: 1px solid var(--border); padding: 0.5rem 2rem; }
        .nav-inner { max-width: 1400px; margin: 0 auto; display: flex; gap: 1.5rem; }
        .nav a { color: var(--text2); text-decoration: none; font-size: 0.9rem; padding: 0.5rem 0; border-bottom: 2px solid transparent; transition: all 0.2s; }
        .nav a:hover, .nav a.active { color: var(--text); border-bottom-color: var(--blue); }
        .container { max-width: 1400px; margin: 2rem auto; padding: 0 2rem; }
        .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-bottom: 2rem; }
        .stat-card { background: var(--bg2); border: 1px solid var(--border); border-radius: 12px; padding: 1.5rem; }
        .stat-label { color: var(--text2); font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 0.5rem; }
        .stat-value { font-size: 1.5rem; font-weight: bold; color: var(--blue); }
        .section { background: var(--bg2); border: 1px solid var(--border); border-radius: 12px; margin-bottom: 2rem; }
        .section-header { padding: 1.25rem 1.5rem; border-bottom: 1px solid var(--border); font-weight: 600; font-size: 1.1rem; }
        .section-body { padding: 1.5rem; }
        .token-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(250px, 1fr)); gap: 1rem; }
        .token-card { background: var(--bg3); border: 1px solid var(--border); border-radius: 8px; padding: 1rem; display: flex; align-items: center; gap: 0.75rem; transition: all 0.2s; text-decoration: none; color: var(--text); }
        .token-card:hover { border-color: var(--blue); transform: translateY(-1px); }
        .token-icon { width: 40px; height: 40px; border-radius: 50%; background: var(--blue); display: flex; align-items: center; justify-content: center; font-weight: bold; font-size: 0.8rem; color: #000; }
        .token-info { flex: 1; }
        .token-symbol { font-weight: 600; }
        .token-name { font-size: 0.8rem; color: var(--text2); }
        .footer { text-align: center; padding: 2rem; color: var(--text2); border-top: 1px solid var(--border); margin-top: 2rem; }
    </style>
</head>
<body>
    <header class="header">
        <div class="header-inner">
            <a href="/" class="logo">🔷 AnvilScan</a>
            <div class="search-box">
                <form action="/search">
                    <input type="text" name="q" placeholder="Search by Address / Txn Hash / Block / Token">
                </form>
            </div>
            <span class="badge">⚡ <%= networkName %> (<%= chainId %>)</span>
        </div>
    </header>
    
    <nav class="nav">
        <div class="nav-inner">
            <a href="/" class="active">Home</a>
            <a href="/tokens">Tokens</a>
            <a href="/api/status">API</a>
        </div>
    </nav>
    
    <main class="container">
        <div class="stats">
            <div class="stat-card">
                <div class="stat-label">Current Block</div>
                <div class="stat-value">#<%= blockNumber.toLocaleString() %></div>
            </div>
            <div class="stat-card">
                <div class="stat-label">Gas Price</div>
                <div class="stat-value"><%= gasPrice %> Gwei</div>
            </div>
            <div class="stat-card">
                <div class="stat-label">TXs in Latest Block</div>
                <div class="stat-value"><%= txCount %></div>
            </div>
            <div class="stat-card">
                <div class="stat-label">Registered Tokens</div>
                <div class="stat-value"><%= tokens.length %></div>
            </div>
        </div>
        
        <div class="section">
            <div class="section-header">🪙 Popular Tokens</div>
            <div class="section-body">
                <div class="token-grid">
                    <% tokens.slice(0, 12).forEach(token => { %>
                    <a href="/token/<%= token.address %>" class="token-card">
                        <div class="token-icon"><%= token.symbol.slice(0, 2) %></div>
                        <div class="token-info">
                            <div class="token-symbol"><%= token.symbol %></div>
                            <div class="token-name"><%= token.name %></div>
                        </div>
                    </a>
                    <% }) %>
                </div>
                <a href="/tokens" style="display: inline-block; margin-top: 1rem; color: var(--blue);">View all <%= tokens.length %> tokens →</a>
            </div>
        </div>
    </main>
    
    <footer class="footer">
        <p>AnvilScan v3.0 | Ethereum Mainnet Fork | <strong>MetaMask • TokenPocket • MathWallet</strong> Compatible</p>
    </footer>
</body>
</html>
EOF

    # Tokens page
    cat > "${EXPLORER_DIR}/views/tokens.ejs" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Tokens - AnvilScan</title>
    <style>
        :root { --bg: #0d1117; --bg2: #161b22; --bg3: #21262d; --text: #c9d1d9; --text2: #8b949e; --blue: #58a6ff; --border: #30363d; --green: #3fb950; }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: var(--bg); color: var(--text); }
        .header { background: var(--bg2); border-bottom: 1px solid var(--border); padding: 1rem 2rem; }
        .header a { color: var(--blue); text-decoration: none; font-size: 1.5rem; font-weight: bold; }
        .container { max-width: 1400px; margin: 2rem auto; padding: 0 2rem; }
        h1 { margin-bottom: 1.5rem; color: var(--blue); }
        table { width: 100%; border-collapse: collapse; background: var(--bg2); border: 1px solid var(--border); border-radius: 12px; overflow: hidden; }
        th { text-align: left; padding: 1rem; background: var(--bg3); color: var(--text2); font-size: 0.85rem; text-transform: uppercase; }
        td { padding: 1rem; border-bottom: 1px solid var(--border); }
        .address { font-family: monospace; color: var(--blue); }
        .symbol { font-weight: 600; color: var(--green); }
    </style>
</head>
<body>
    <div class="header"><a href="/">← AnvilScan</a></div>
    <div class="container">
        <h1>🪙 Token Registry (<%= tokens.length %> tokens)</h1>
        <table>
            <thead>
                <tr>
                    <th>#</th>
                    <th>Symbol</th>
                    <th>Name</th>
                    <th>Contract Address</th>
                    <th>Decimals</th>
                </tr>
            </thead>
            <tbody>
                <% tokens.forEach((token, i) => { %>
                <tr>
                    <td><%= i + 1 %></td>
                    <td class="symbol"><a href="/token/<%= token.address %>" style="color: var(--green);"><%= token.symbol %></a></td>
                    <td><%= token.name %></td>
                    <td class="address"><a href="/address/<%= token.address %>" style="color: var(--blue);"><%= token.address %></a></td>
                    <td><%= token.decimals %></td>
                </tr>
                <% }) %>
            </tbody>
        </table>
    </div>
</body>
</html>
EOF

    # Simple templates for other pages
    for template in block transaction address token error; do
        cat > "${EXPLORER_DIR}/views/${template}.ejs" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${template^} - AnvilScan</title>
    <style>
        :root { --bg: #0d1117; --bg2: #161b22; --bg3: #21262d; --text: #c9d1d9; --text2: #8b949e; --blue: #58a6ff; --border: #30363d; }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: var(--bg); color: var(--text); padding: 2rem; }
        .container { max-width: 1200px; margin: 0 auto; background: var(--bg2); border: 1px solid var(--border); border-radius: 12px; padding: 2rem; }
        h1 { color: var(--blue); margin-bottom: 1rem; }
        a { color: var(--blue); text-decoration: none; }
        pre { background: var(--bg3); padding: 1rem; border-radius: 8px; overflow-x: auto; font-size: 0.85rem; }
    </style>
</head>
<body>
    <div class="container">
        <a href="/">← Back to Home</a>
        <h1>${template^} Details</h1>
        <pre><%= JSON.stringify(locals, null, 2) %></pre>
    </div>
</body>
</html>
EOF
    done
}

# ═══════════════════════════════════════════════
# WALLET CONFIGURATION
# ═══════════════════════════════════════════════
generate_wallet_config() {
    log_section "WALLET CONFIG"
    
    cat > "${EXPLORER_DIR}/public/add-network.js" << 'WALLETEOF'
// Add Anvil network to any Web3 wallet
const ANVIL_CONFIG = {
    chainId: '0x1',
    chainName: 'Anvil Mainnet Fork',
    nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
    rpcUrls: [window.location.origin.replace(':3000', ':8545')],
    blockExplorerUrls: [window.location.origin]
};

document.getElementById('addToWallet')?.addEventListener('click', async () => {
    try {
        await ethereum.request({ method: 'wallet_addEthereumChain', params: [ANVIL_CONFIG] });
        alert('Network added successfully!');
    } catch(e) {
        alert('Error: ' + e.message);
    }
});
WALLETEOF

    log_info "Wallet config generated"
}

# ═══════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════
main() {
    log_section "ANVIL PRODUCTION SYSTEM v3.0"
    
    check_dependencies
    save_tokens_config
    
    local state_loaded=false
    download_state && state_loaded=true
    
    setup_explorer
    generate_wallet_config
    
    # Launch Anvil
    log_section "STARTING ANVIL"
    
    anvil \
        --fork-url "$FORK_URL" \
        --chain-id "$CHAIN_ID" \
        --host 0.0.0.0 \
        --port "$PORT" \
        --state "$STATE_FILE" \
        --state-interval 1 \
        --block-time 2 \
        --auto-impersonate \
        &
    ANVIL_PID=$!
    log_success "Anvil PID: $ANVIL_PID"
    
    # Wait for readiness
    sleep 3
    for i in $(seq 1 30); do
        curl -s -X POST "http://localhost:${PORT}" \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            | jq -e '.result' >/dev/null 2>&1 && break
        sleep 2
    done
    log_success "Anvil RPC ready"
    
    # Start Explorer
    cd "$EXPLORER_DIR"
    ANVIL_PORT="$PORT" PORT="$EXPLORER_PORT" \
    JSONBIN_BIN_ID="$JSONBIN_BIN_ID" \
    JSONBIN_API_KEY="$JSONBIN_API_KEY" \
    node server.js &
    EXPLORER_PID=$!
    log_success "Explorer: http://localhost:${EXPLORER_PORT}"
    
    # Upload state
    sleep 2
    upload_state
    
    # Background services
    auto_ping &
    PING_PID=$!
    
    # Shutdown handler
    graceful_shutdown() {
        log_section "SHUTDOWN"
        upload_state
        kill $PING_PID $EXPLORER_PID $ANVIL_PID 2>/dev/null || true
        log_success "Complete"
        exit 0
    }
    trap graceful_shutdown SIGTERM SIGINT
    
    # Status
    log_section "SYSTEM READY"
    echo -e "${GREEN}"
    echo "    ╔══════════════════════════════════╗"
    echo "    ║  ANVIL SYSTEM v3.0 - RUNNING   ║"
    echo "    ╚══════════════════════════════════╝"
    echo -e "${NC}"
    log_info "📡 RPC: http://localhost:${PORT}"
    log_info "🔍 Explorer: http://localhost:${EXPLORER_PORT}"
    log_info "🪙 Tokens: ${#TOKENS[@]} registered"
    log_info "💾 Auto-save: ON"
    log_info "🔄 Ping: ${PING_INTERVAL}s"
    log_info "💳 Wallets: MetaMask, TokenPocket, MathWallet"
    echo ""
    
    wait $ANVIL_PID
}

main "$@"
