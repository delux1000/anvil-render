#!/bin/bash

# ═══════════════════════════════════════════════════════════
# ANVIL PRODUCTION SYSTEM v5.0 — FIXED STATE PERSISTENCE
# Uses anvil_dumpState RPC for reliable state saving
# All wallet balances survive restarts
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
BALANCES_FILE="/tmp/balances.json"
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
    ["USDC"]="0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48:6:USD Coin"
    ["USDT"]="0xdAC17F958D2ee523a2206206994597C13D831ec7:6:Tether USD"
    ["DAI"]="0x6B175474E89094C44Da98b954EedeAC495271d0F:18:Dai Stablecoin"
    ["BUSD"]="0x4Fabb145d64652a948d72533023f6E7A623C7C53:18:Binance USD"
    ["TUSD"]="0x0000000000085d4780B73119b644AE5ecd22b376:18:TrueUSD"
    ["FRAX"]="0x853d955aCEf822Db058eb8505911ED77F175b99e:18:Frax"
    ["UNI"]="0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984:18:Uniswap"
    ["AAVE"]="0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9:18:Aave Token"
    ["LINK"]="0x514910771AF9Ca656af840dff83E8264EcF986CA:18:Chainlink"
    ["MKR"]="0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2:18:Maker"
    ["SNX"]="0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F:18:Synthetix"
    ["CRV"]="0xD533a949740bb3306d119CC777fa900bA034cd52:18:Curve DAO"
    ["1INCH"]="0x111111111117dC0aa78b770fA6A738034120C302:18:1inch"
    ["MATIC"]="0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0:18:Polygon"
    ["ENS"]="0xC18360217D8F7Ab5e7c516566761Ea12Ce7F9D72:18:Ethereum Name Service"
    ["GRT"]="0xc944E90C64B2c07662A292be6244BDf05Cda44a7:18:The Graph"
    ["SHIB"]="0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE:18:Shiba Inu"
    ["PEPE"]="0x6982508145454Ce325dDbE47a25d4ec3d2311933:18:Pepe"
    ["WETH"]="0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2:18:Wrapped Ether"
    ["WBTC"]="0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599:8:Wrapped Bitcoin"
    ["SAND"]="0x3845badAde8e6dFF049820680d1F14bD3903a5d0:18:The Sandbox"
    ["MANA"]="0x0F5D2fB29fb7d3CFeE444a200298f468908cC942:18:Decentraland"
    ["APE"]="0x4d224452801ACEd8B2F0aebE155379bb5D594381:18:ApeCoin"
    ["LDO"]="0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32:18:Lido DAO"
    ["OP"]="0x4200000000000000000000000000000000000042:18:Optimism"
    ["ARB"]="0xB50721BCf8d664c30412Cfbc6cf7a15145234ad1:18:Arbitrum"
    ["BNB"]="0xB8c77482e45F1F44dE1745F52C74426C631bDD52:18:Binance Coin"
    ["CRO"]="0xA0b73E1Ff0B80914AB6fe0444E65848C4C34450b:18:Cronos"
    ["COMP"]="0xc00e94Cb662C3520282E6f5717214004A7f26888:18:Compound"
    ["YFI"]="0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e:18:yearn.finance"
    ["SUSHI"]="0x6B3595068778DD592e39A122f4f5a5cF09C90fE2:18:SushiSwap"
)

# ═══════════════════════════════════════════════
# COLOR CODES
# ═══════════════════════════════════════════════
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; PURPLE='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

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
# RPC CALL HELPER (for localhost)
# ═══════════════════════════════════════════════
rpc_call() {
    curl -s --max-time 10 -X POST "http://localhost:${PORT}" \
        -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"$1\",\"params\":$2,\"id\":1}"
}

# ═══════════════════════════════════════════════
# DEPENDENCY CHECK
# ═══════════════════════════════════════════════
check_dependencies() {
    log_section "DEPENDENCIES"
    local missing=()
    for cmd in curl jq anvil; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        log_warning "Missing: ${missing[*]}"
        apt-get update -qq && apt-get install -y -qq curl jq >/dev/null 2>&1 || {
            log_error "Installation failed"
            exit 1
        }
    fi
    log_success "All dependencies ready"
}

# ═══════════════════════════════════════════════
# SAVE TOKENS CONFIG
# ═══════════════════════════════════════════════
save_tokens_config() {
    local tokens_json="["
    local first=true
    for symbol in "${!TOKENS[@]}"; do
        IFS=':' read -r address decimals name <<< "${TOKENS[$symbol]}"
        [ "$first" = true ] && first=false || tokens_json+=","
        tokens_json+="{\"symbol\":\"$symbol\",\"address\":\"$address\",\"decimals\":$decimals,\"name\":\"$name\"}"
    done
    tokens_json+="]"
    echo "$tokens_json" | jq '.' > "$TOKENS_FILE"
    log_info "Tokens saved: $(echo "$tokens_json" | jq 'length') tokens"
}

# ═══════════════════════════════════════════════
# VALIDATE STATE
# ═══════════════════════════════════════════════
validate_state() {
    [ -f "$1" ] && jq -e '.block' "$1" >/dev/null 2>&1
}

# ═══════════════════════════════════════════════
# DOWNLOAD STATE + BALANCES FROM JSONBIN
# ═══════════════════════════════════════════════
download_persisted_data() {
    log_section "DOWNLOADING PERSISTED DATA"
    
    local response
    response=$(curl -s --max-time 30 \
        -H "X-Master-Key: ${JSONBIN_API_KEY}" \
        "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}/latest" 2>&1) || {
        log_warning "Cannot reach JSONBin"
        echo '{}' > "$BALANCES_FILE"
        return 1
    }
    
    if echo "$response" | jq -e '.record' >/dev/null 2>&1; then
        local record
        record=$(echo "$response" | jq -r '.record')
        
        # New format with separate state + balances
        if echo "$record" | jq -e '.state' >/dev/null 2>&1; then
            echo "$record" | jq -r '.state' > "$STATE_FILE"
            echo "$record" | jq -r '.balances // {}' > "$BALANCES_FILE"
            local block accounts bal_count
            block=$(jq -r '.block.number // "0"' "$STATE_FILE" 2>/dev/null || echo "?")
            accounts=$(jq '.accounts | length' "$STATE_FILE" 2>/dev/null || echo "0")
            bal_count=$(jq 'length' "$BALANCES_FILE" 2>/dev/null || echo "0")
            log_success "Loaded — Block: $block | Accounts: $accounts | Saved Balances: $bal_count"
            return 0
        # Old format: just state
        elif echo "$record" | jq -e '.block' >/dev/null 2>&1; then
            echo "$record" > "$STATE_FILE"
            echo '{}' > "$BALANCES_FILE"
            log_success "Loaded state (old format)"
            return 0
        fi
    fi
    
    log_info "Fresh start"
    echo '{}' > "$BALANCES_FILE"
    return 1
}

# ═══════════════════════════════════════════════
# FORCE STATE DUMP TO FILE (using anvil_dumpState RPC)
# ═══════════════════════════════════════════════
force_dump_state() {
    local result
    result=$(rpc_call "anvil_dumpState" "[\"${STATE_FILE}\"]" | jq -r '.result // false')
    if [ "$result" = "true" ] && validate_state "$STATE_FILE"; then
        return 0
    fi
    return 1
}

# ═══════════════════════════════════════════════
# SAVE STATE + ALL WALLET BALANCES TO JSONBIN
# ═══════════════════════════════════════════════
save_all_to_jsonbin() {
    log_info "💾 Saving to JSONBin..."
    
    # Force Anvil to dump current state to file FIRST
    if ! force_dump_state; then
        log_warning "State dump failed — using existing file"
        [ ! -f "$STATE_FILE" ] && { log_error "No state file"; return 1; }
    fi
    
    validate_state "$STATE_FILE" || { log_error "Invalid state"; return 1; }
    
    local state_content bal_json combined count
    state_content=$(cat "$STATE_FILE")
    count=0
    
    # Collect all wallet balances from running node
    bal_json='{'
    local first=true
    local addresses
    addresses=$(jq -r '.accounts | keys[]' "$STATE_FILE" 2>/dev/null)
    
    for addr in $addresses; do
        local eth_bal
        eth_bal=$(rpc_call "eth_getBalance" "[\"${addr}\",\"latest\"]" | jq -r '.result // "0x0"')
        
        if [ "$eth_bal" != "0x0" ] && [ "$eth_bal" != "0x" ] && [ -n "$eth_bal" ]; then
            [ "$first" = true ] && first=false || bal_json+=','
            bal_json+="\"${addr}\":{\"eth\":\"${eth_bal}\"}"
            count=$((count + 1))
        fi
    done
    bal_json+='}'
    echo "$bal_json" | jq '.' > "$BALANCES_FILE"
    
    # Combine state + balances into one record
    combined=$(jq -n \
        --argfile state "$STATE_FILE" \
        --argfile balances "$BALANCES_FILE" \
        '{state: $state, balances: $balances}')
    
    # Upload to JSONBin
    local upload_response
    upload_response=$(curl -s --max-time 30 -X PUT \
        -H "Content-Type: application/json" \
        -H "X-Master-Key: ${JSONBIN_API_KEY}" \
        -d "{\"record\": ${combined}}" \
        "https://api.jsonbin.io/v3/b/${JSONBIN_BIN_ID}" 2>&1)
    
    if echo "$upload_response" | jq -e '.record' >/dev/null 2>&1; then
        local block
        block=$(jq -r '.block.number // "0"' "$STATE_FILE" 2>/dev/null || echo "?")
        log_success "Saved — Block: $block | Wallets: $count"
        return 0
    else
        log_error "Upload failed"
        return 1
    fi
}

# ═══════════════════════════════════════════════
# RESTORE WALLET BALANCES AFTER RESTART
# ═══════════════════════════════════════════════
restore_balances_from_save() {
    log_section "RESTORING WALLET BALANCES"
    
    [ ! -f "$BALANCES_FILE" ] && { log_info "No saved balances"; return 0; }
    [ ! -s "$BALANCES_FILE" ] && { log_info "Empty balances file"; return 0; }
    
    local wallets restored
    wallets=$(jq -r 'keys[]' "$BALANCES_FILE" 2>/dev/null)
    restored=0
    
    for addr in $wallets; do
        local eth_bal
        eth_bal=$(jq -r ".\"${addr}\".eth // empty" "$BALANCES_FILE" 2>/dev/null)
        
        if [ -n "$eth_bal" ] && [ "$eth_bal" != "null" ] && [ "$eth_bal" != "0x0" ]; then
            rpc_call "anvil_setBalance" "[\"${addr}\",\"${eth_bal}\"]" >/dev/null 2>&1 && {
                log_success "Restored: ${addr:0:10}...${addr: -6}"
                restored=$((restored + 1))
            }
        fi
    done
    
    log_success "Restored $restored wallet balances"
}

# ═══════════════════════════════════════════════
# TOUCH ALL WALLETS (forces them into state)
# ═══════════════════════════════════════════════
touch_all_wallets() {
    log_info "Touching wallets from state..."
    
    [ ! -f "$STATE_FILE" ] && return
    
    local addresses touched
    addresses=$(jq -r '.accounts | keys[]' "$STATE_FILE" 2>/dev/null)
    touched=0
    
    for addr in $addresses; do
        rpc_call "anvil_impersonateAccount" "[\"${addr}\"]" >/dev/null 2>&1
        rpc_call "eth_sendTransaction" "[{\"from\":\"${addr}\",\"to\":\"${addr}\",\"value\":\"0x0\"}]" >/dev/null 2>&1 && {
            touched=$((touched + 1))
        }
    done
    
    log_info "Touched $touched wallets"
}

# ═══════════════════════════════════════════════
# MONITOR BLOCKS & AUTO-SAVE (FIXED — uses anvil_dumpState)
# ═══════════════════════════════════════════════
monitor_and_autosave() {
    log_info "🔍 Block monitor active (checking every 3s)"
    local last_block="0x0"
    
    while true; do
        local current_block
        current_block=$(rpc_call "eth_blockNumber" "[]" | jq -r '.result // "0x0"')
        
        if [ "$current_block" != "$last_block" ] && [ "$current_block" != "0x0" ]; then
            local last_dec current_dec
            last_dec=$(printf "%d" "$last_block" 2>/dev/null || echo "0")
            current_dec=$(printf "%d" "$current_block" 2>/dev/null || echo "0")
            log_info "🔔 New block: ${last_dec} → ${current_dec}"
            
            # FORCE dump state via RPC then save
            save_all_to_jsonbin
            last_block="$current_block"
        fi
        sleep 3
    done
}

# ═══════════════════════════════════════════════
# AUTO-PING (KEEP ALIVE)
# ═══════════════════════════════════════════════
auto_ping() {
    log_info "Auto-ping every ${PING_INTERVAL}s"
    while true; do
        rpc_call "eth_chainId" "[]" >/dev/null 2>&1
        [ -n "$PUBLIC_URL" ] && curl -s -o /dev/null "$PUBLIC_URL" 2>/dev/null || true
        sleep "$PING_INTERVAL"
    done
}

# ═══════════════════════════════════════════════
# EXPLORER SETUP (unchanged)
# ═══════════════════════════════════════════════
setup_explorer() {
    log_section "EXPLORER SETUP"
    mkdir -p "$EXPLORER_DIR"/{views,public}
    
    cat > "${EXPLORER_DIR}/package.json" << 'EOF'
{"name":"anvil-explorer","version":"5.0.0","main":"server.js","scripts":{"start":"node server.js"},"dependencies":{"express":"^4.18.2","cors":"^2.8.5","axios":"^1.6.0","ejs":"^3.1.9"}}
EOF

    # Server.js
    cat > "${EXPLORER_DIR}/server.js" << 'SERVEREOF'
const express = require('express');
const cors = require('cors');
const axios = require('axios');
const path = require('path');
const fs = require('fs');
const app = express();
const PORT = process.env.EXPLORER_PORT || 3000;
const RPC_URL = `http://localhost:${process.env.ANVIL_PORT || 8545}`;
let TOKENS = [];
try { TOKENS = JSON.parse(fs.readFileSync('/tmp/tokens.json','utf8')); } catch(e) { TOKENS = []; }
app.use(cors()); app.use(express.json()); app.use(express.static('public'));
app.set('view engine','ejs'); app.set('views',path.join(__dirname,'views'));

async function rpcCall(m,p=[]) {
    try { const {data} = await axios.post(RPC_URL,{jsonrpc:'2.0',method:m,params:p,id:1}); return data.result; } catch(e) { return null; }
}

function encodeBalanceOf(a) { return '0x70a08231'+a.toLowerCase().replace('0x','').padStart(64,'0'); }
async function getTokenBalance(ta,wa) {
    const d = encodeBalanceOf(wa);
    const r = await rpcCall('eth_call',[{to:ta,data:d},'latest']);
    return r||'0x0';
}

app.get('/', async (req,res) => {
    try {
        const [bn,ci,gp] = await Promise.all([rpcCall('eth_blockNumber'),rpcCall('eth_chainId'),rpcCall('eth_gasPrice')]);
        const lb = await rpcCall('eth_getBlockByNumber',[bn,true]);
        res.render('index',{blockNumber:parseInt(bn,16),chainId:parseInt(ci,16),gasPrice:(parseInt(gp,16)/1e9).toFixed(2),txCount:lb?.transactions?.length||0,networkName:'Anvil Mainnet Fork',tokens:TOKENS});
    } catch(e) { res.render('error',{error:'RPC connection failed'}); }
});

app.get('/tokens',(req,res)=>res.render('tokens',{tokens:TOKENS}));
app.get('/token/:address',async(req,res)=>{
    const t = TOKENS.find(x=>x.address.toLowerCase()===req.params.address.toLowerCase());
    if(!t) return res.render('error',{error:'Token not found'});
    try {
        const ts = await rpcCall('eth_call',[{to:t.address,data:'0x18160ddd'},'latest']);
        res.render('token',{token:t,totalSupply:parseInt(ts||'0x0',16)/Math.pow(10,t.decimals)});
    } catch(e) { res.render('error',{error:'Failed'}); }
});

app.get('/address/:addr',async(req,res)=>{
    try {
        const [bal,code,txc] = await Promise.all([rpcCall('eth_getBalance',[req.params.addr,'latest']),rpcCall('eth_getCode',[req.params.addr,'latest']),rpcCall('eth_getTransactionCount',[req.params.addr,'latest'])]);
        const eth = parseInt(bal,16)/1e18;
        const isC = code!=='0x';
        let tbs = [];
        try {
            const rs = await Promise.allSettled(TOKENS.slice(0,20).map(async t=>{const b=await getTokenBalance(t.address,req.params.addr);const bal=parseInt(b,16)/Math.pow(10,t.decimals);return{...t,balance:bal};}));
            tbs = rs.filter(r=>r.status==='fulfilled'&&r.value.balance>0).map(r=>r.value);
        } catch(e) {}
        res.render('address',{address:req.params.addr,balance:eth,isContract:isC,txCount:parseInt(txc,16),tokenBalances:tbs});
    } catch(e) { res.render('error',{error:'Address not found'}); }
});

app.get('/tx/:hash',async(req,res)=>{
    try {
        const [tx,rc] = await Promise.all([rpcCall('eth_getTransactionByHash',[req.params.hash]),rpcCall('eth_getTransactionReceipt',[req.params.hash])]);
        if(!tx) return res.render('error',{error:'Not found'});
        res.render('transaction',{tx,receipt:rc});
    } catch(e) { res.render('error',{error:'Not found'}); }
});

app.get('/block/:number',async(req,res)=>{
    try {
        const bh = '0x'+parseInt(req.params.number).toString(16);
        const bl = await rpcCall('eth_getBlockByNumber',[bh,true]);
        if(!bl) return res.render('error',{error:'Not found'});
        res.render('block',{block:bl});
    } catch(e) { res.render('error',{error:'Not found'}); }
});

app.get('/search',(req,res)=>{
    const q=req.query.q?.trim();
    if(!q) return res.redirect('/');
    if(/^\d+$/.test(q)) return res.redirect('/block/'+q);
    if(/^0x[a-fA-F0-9]{64}$/.test(q)) return res.redirect('/tx/'+q);
    if(/^0x[a-fA-F0-9]{40}$/.test(q)) return res.redirect('/address/'+q);
    res.render('error',{error:'Invalid search'});
});

app.get('/api/status',async(req,res)=>{
    const [bn,ci]=await Promise.all([rpcCall('eth_blockNumber'),rpcCall('eth_chainId')]);
    res.json({status:'ok',blockNumber:parseInt(bn,16),chainId:parseInt(ci,16),tokens:TOKENS.length});
});

app.get('/api/tokens',(req,res)=>res.json(TOKENS));
app.get('/api/balance/:address',async(req,res)=>{
    try {
        const bal={};
        for(const t of TOKENS.slice(0,10)) { const b=await getTokenBalance(t.address,req.params.address); const h=parseInt(b,16)/Math.pow(10,t.decimals); if(h>0) bal[t.symbol]=h; }
        res.json({address:req.params.address,balances:bal});
    } catch(e) { res.json({error:e.message}); }
});

// Create templates
const viewsDir = path.join(__dirname,'views');
if(!fs.existsSync(viewsDir)) fs.mkdirSync(viewsDir,{recursive:true});

const templates = {
    index: `<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>AnvilScan</title><style>:root{--bg:#0d1117;--bg2:#161b22;--bg3:#21262d;--text:#c9d1d9;--text2:#8b949e;--blue:#58a6ff;--green:#3fb950;--border:#30363d;}*{margin:0;padding:0;box-sizing:border-box;}body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:var(--bg);color:var(--text);}.header{background:var(--bg2);border-bottom:1px solid var(--border);padding:1rem 2rem;}.header-inner{max-width:1400px;margin:0 auto;display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:1rem;}.logo{font-size:1.5rem;font-weight:bold;color:var(--blue);text-decoration:none;}.search-box{flex:1;max-width:600px;}.search-box form{display:flex;}.search-box input{flex:1;padding:0.75rem 1rem;background:var(--bg3);border:1px solid var(--border);border-radius:8px 0 0 8px;color:var(--text);font-size:0.95rem;outline:none;}.search-box input:focus{border-color:var(--blue);}.search-box button{padding:0.75rem 1.25rem;background:var(--blue);color:#000;border:none;border-radius:0 8px 8px 0;font-weight:600;cursor:pointer;}.badge{background:var(--green);color:#000;padding:0.25rem 0.75rem;border-radius:20px;font-size:0.85rem;font-weight:600;}.nav{background:var(--bg2);border-bottom:1px solid var(--border);padding:0.5rem 2rem;}.nav-inner{max-width:1400px;margin:0 auto;display:flex;gap:1.5rem;}.nav a{color:var(--text2);text-decoration:none;font-size:0.9rem;padding:0.5rem 0;border-bottom:2px solid transparent;}.nav a:hover,.nav a.active{color:var(--text);border-bottom-color:var(--blue);}.container{max-width:1400px;margin:2rem auto;padding:0 2rem;}.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:1rem;margin-bottom:2rem;}.stat-card{background:var(--bg2);border:1px solid var(--border);border-radius:12px;padding:1.5rem;}.stat-label{color:var(--text2);font-size:0.8rem;text-transform:uppercase;letter-spacing:0.5px;}.stat-value{font-size:1.5rem;font-weight:bold;color:var(--blue);margin-top:0.5rem;}.section{background:var(--bg2);border:1px solid var(--border);border-radius:12px;margin-bottom:2rem;overflow:hidden;}.section-header{padding:1.25rem 1.5rem;border-bottom:1px solid var(--border);font-weight:600;font-size:1.1rem;}.section-body{padding:1.5rem;}.token-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:0.75rem;}.token-card{background:var(--bg3);border:1px solid var(--border);border-radius:8px;padding:1rem;text-decoration:none;color:var(--text);transition:all 0.2s;display:flex;align-items:center;gap:0.5rem;}.token-card:hover{border-color:var(--blue);transform:translateY(-1px);}.token-icon{width:36px;height:36px;border-radius:50%;background:var(--blue);display:flex;align-items:center;justify-content:center;font-weight:bold;font-size:0.7rem;color:#000;}.token-sym{font-weight:600;}.token-name{font-size:0.75rem;color:var(--text2);}.footer{text-align:center;padding:2rem;color:var(--text2);border-top:1px solid var(--border);font-size:0.85rem;}@media(max-width:768px){.header-inner{flex-direction:column;}.search-box{max-width:100%;}}</style></head><body><header class="header"><div class="header-inner"><a href="/" class="logo">⬨ AnvilScan v5.0</a><div class="search-box"><form action="/search"><input type="text" name="q" placeholder="Search Address / Tx / Block / Token..."><button>🔍</button></form></div><span class="badge">⚡ <%= networkName %> (<%= chainId %>)</span></div></header><nav class="nav"><div class="nav-inner"><a href="/" class="active">Home</a><a href="/tokens">Tokens</a><a href="/api/status">API</a></div></nav><main class="container"><div class="stats"><div class="stat-card"><div class="stat-label">Latest Block</div><div class="stat-value">#<%= blockNumber.toLocaleString() %></div></div><div class="stat-card"><div class="stat-label">Gas Price</div><div class="stat-value"><%= gasPrice %> Gwei</div></div><div class="stat-card"><div class="stat-label">TXs in Block</div><div class="stat-value"><%= txCount %></div></div><div class="stat-card"><div class="stat-label">Tokens</div><div class="stat-value"><%= tokens.length %></div></div></div><div class="section"><div class="section-header">🪙 Popular Tokens</div><div class="section-body"><div class="token-grid"><% tokens.slice(0,12).forEach(t => { %><a href="/token/<%= t.address %>" class="token-card"><div class="token-icon"><%= t.symbol.slice(0,2) %></div><div><div class="token-sym"><%= t.symbol %></div><div class="token-name"><%= t.name %></div></div></a><% }) %></div><a href="/tokens" style="display:inline-block;margin-top:1rem;color:var(--blue);">View all →</a></div></div></main><footer class="footer">AnvilScan v5.0 | Chain ID: <%= chainId %> | State Persistence: ON</footer></body></html>`
};

for (const [name, html] of Object.entries(templates)) {
    fs.writeFileSync(path.join(viewsDir, name+'.ejs'), html);
}

const generic = `<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>AnvilScan</title><style>:root{--bg:#0d1117;--bg2:#161b22;--text:#c9d1d9;--blue:#58a6ff;--border:#30363d;}body{font-family:sans-serif;background:var(--bg);color:var(--text);padding:2rem;}a{color:var(--blue);text-decoration:none;}.container{max-width:1200px;margin:0 auto;background:var(--bg2);border:1px solid var(--border);border-radius:12px;padding:2rem;}pre{background:#21262d;padding:1rem;border-radius:8px;overflow-x:auto;}</style></head><body><div class="container"><a href="/">← Back</a><br><br><%= JSON.stringify(locals,null,2).replace(/</g,'&lt;') %></div></body></html>`;
['tokens','token','address','transaction','block','error'].forEach(t => {
    fs.writeFileSync(path.join(viewsDir, t+'.ejs'), generic);
});

app.listen(PORT, () => console.log(`Explorer: http://localhost:${PORT} | Tokens: ${TOKENS.length}`));
SERVEREOF

    cd "$EXPLORER_DIR" && npm install --silent 2>/dev/null
    log_success "Explorer ready"
}

# ═══════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════
main() {
    log_section "ANVIL v5.0 — FIXED STATE PERSISTENCE"
    
    check_dependencies
    save_tokens_config
    
    # Download previous state + balances
    local state_loaded=false
    download_persisted_data && state_loaded=true
    
    # Setup explorer
    setup_explorer
    
    # Launch Anvil
    log_section "STARTING ANVIL"
    
    local cmd="anvil --fork-url ${FORK_URL} --chain-id ${CHAIN_ID} --host 0.0.0.0 --port ${PORT}"
    [ "$state_loaded" = true ] && [ -f "$STATE_FILE" ] && cmd="${cmd} --state ${STATE_FILE}"
    
    $cmd &
    ANVIL_PID=$!
    log_success "Anvil PID: $ANVIL_PID"
    
    # Wait for readiness
    sleep 3
    for i in $(seq 1 30); do
        rpc_call "eth_blockNumber" "[]" | jq -e '.result' >/dev/null 2>&1 && break
        sleep 2
    done
    log_success "Anvil RPC ready"
    
    # 🔥 RESTORE SAVED BALANCES
    restore_balances_from_save
    
    # 🔥 TOUCH ALL WALLETS
    touch_all_wallets
    
    # Start Explorer
    cd "$EXPLORER_DIR"
    ANVIL_PORT="$PORT" PORT="$EXPLORER_PORT" node server.js &
    EXPLORER_PID=$!
    log_success "Explorer: http://localhost:${EXPLORER_PORT}"
    
    # Initial save
    sleep 2
    save_all_to_jsonbin
    
    # Start monitor
    monitor_and_autosave &
    MONITOR_PID=$!
    
    # Start ping
    auto_ping &
    PING_PID=$!
    
    # Shutdown handler
    graceful_shutdown() {
        log_section "SHUTDOWN"
        save_all_to_jsonbin
        kill $PING_PID $MONITOR_PID $EXPLORER_PID $ANVIL_PID 2>/dev/null || true
        log_success "Complete"
        exit 0
    }
    trap graceful_shutdown SIGTERM SIGINT
    
    log_section "SYSTEM READY"
    echo -e "${GREEN}"
    echo "    ╔══════════════════════════════════╗"
    echo "    ║  ANVIL v5.0 — STATE FIXED      ║"
    echo "    ║  anvil_dumpState RPC Active    ║"
    echo "    ╚══════════════════════════════════╝"
    echo -e "${NC}"
    log_info "📡 RPC: http://localhost:${PORT}"
    log_info "🔍 Explorer: http://localhost:${EXPLORER_PORT}"
    log_info "🪙 Tokens: ${#TOKENS[@]} registered"
    log_info "💾 State: anvil_dumpState → JSONBin (every block)"
    log_info "🔒 Balances: Survive restarts"
    echo ""
    
    wait $ANVIL_PID
}

main "$@"
