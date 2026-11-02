#!/bin/bash
set -o pipefail

# ==============================================================================
#  ⚡ MACK AUTOMATED NODE SETUP :: PTERODACTYL v1 & v2
# ==============================================================================

# --- COLORS & STYLES ---
R="\e[31m"
G="\e[32m"
Y="\e[33m"
B="\e[34m"
M="\e[35m"
C="\e[36m"
W="\e[97m"
GR="\e[90m"
N="\e[0m"
BOLD="\e[1m"
CYAN="$C"
GREEN="$G"
YELLOW="$Y"
RED="$R"
BLUE="$B"
WHITE="$W"
NC="$N"

CREDENTIALS_FILE="/etc/pterodactyl/.panel_api"
CERT_FILE="/etc/certs/wing/fullchain.pem"
KEY_FILE="/etc/certs/wing/privkey.pem"

# Root Check
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${R}✖ Error: This script must be run as root.${N}"
    exit 1
fi

# Reset credentials flag
if [[ "$1" == "--reset" || "$1" == "--login" || "$1" == "reset" ]]; then
    rm -f "$CREDENTIALS_FILE" 2>/dev/null || true
    echo -e "${Y}✔ Saved panel credentials cleared.${N}"
fi

# UI Drawing Functions
draw_top() {
    echo -e "${B} ╔══════════════════════════════════════════════════════════╗${N}"
}
draw_line() {
    echo -e "${B} ╠══════════════════════════════════════════════════════════╣${N}"
}
draw_bottom() {
    echo -e "${B} ╚══════════════════════════════════════════════════════════╝${N}"
}

check_success() {
    if [ $? -eq 0 ]; then
        echo -e "${G}✔ $1${N}"
    else
        echo -e "${R}✖ $1 failed${N}"
    fi
}

header() {
    clear 2>/dev/null || true
    draw_top
    printf "${B} ║${W}${BOLD}   ⚡ MACK AUTOMATED NODE SETUP :: PTERODACTYL v1 & v2     ${B}║${N}\n"
    draw_line
    printf "${B} ║${GR}  OS   :${W} %-20s ${GR}WAN   :${W} %-20s${B}║${N}\n" "${OS_NAME:0:20}" "${PUBLIC_IP:0:20}"
    printf "${B} ║${GR}  Wings:${W} %-20s ${GR}Listen:${W} %-20s${B}║${N}\n" "${WINGS_STATUS:0:20}" "Port 8080 (LOCKED)"
    printf "${B} ║${GR}  Panel:${W} %-20s ${GR}Node  :${W} %-20s${B}║${N}\n" "${PANEL_URL_SHORT:0:20}" "Port 443 (LOCKED)"
    draw_bottom
    echo ""
}

# --- SYSTEM AUTO-DETECTION ---
detect_system() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_NAME="$PRETTY_NAME"
    else
        OS_NAME=$(uname -s)
    fi

    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  ARCH_TYPE="amd64" ;;
        aarch64) ARCH_TYPE="arm64" ;;
        *)       ARCH_TYPE="$ARCH" ;;
    esac

    PUBLIC_IP=$(curl -s --max-time 2 https://ipinfo.io/ip 2>/dev/null || curl -s --max-time 2 https://api.ipify.org 2>/dev/null || echo "127.0.0.1")
    LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    [ -z "$LOCAL_IP" ] && LOCAL_IP="127.0.0.1"

    if command -v free >/dev/null 2>&1; then
        RAM_USED=$(free -h 2>/dev/null | awk '/^Mem:/ {print $3 "/" $2}')
        TOTAL_RAM_MB=$(free -m 2>/dev/null | awk '/^Mem:/ {print $2}')
    else
        RAM_USED="N/A"
        TOTAL_RAM_MB="4096"
    fi

    TOTAL_DISK_MB=$(df -m / 2>/dev/null | awk 'NR==2 {print int($2 * 0.9)}')
    [ -z "$TOTAL_DISK_MB" ] && TOTAL_DISK_MB="50000"

    if command -v wings >/dev/null 2>&1; then
        RAW_VER=$(wings version 2>/dev/null | head -n 1 | awk '{print $2}')
        RAW_VER="v$(echo "$RAW_VER" | sed 's/^v*//')"
        if systemctl is-active --quiet wings 2>/dev/null; then
            WINGS_STATUS="Running ($RAW_VER)"
        else
            WINGS_STATUS="Stopped ($RAW_VER)"
        fi
    else
        WINGS_STATUS="Not Installed"
    fi

    PANEL_URL_SHORT="Not Saved"
    if [ -f "$CREDENTIALS_FILE" ]; then
        SAVED_URL=$(python3 -c "import json; print(json.load(open('$CREDENTIALS_FILE')).get('url', ''))" 2>/dev/null)
        if [ -n "$SAVED_URL" ]; then
            PANEL_URL_SHORT="${SAVED_URL#https://}"
            PANEL_URL_SHORT="${PANEL_URL_SHORT#http://}"
        fi
    fi
}

# --- PRE-FLIGHT DEPENDENCIES ---
install_prerequisites() {
    MISSING_PKGS=()
    for pkg in curl tar python3 openssl; do
        if ! command -v "$pkg" >/dev/null 2>&1; then
            MISSING_PKGS+=("$pkg")
        fi
    done

    if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
        echo -e "${Y}➜ Installing dependencies: ${MISSING_PKGS[*]}...${N}"
        apt-get update -y >/dev/null 2>&1 || true
        apt-get install -y "${MISSING_PKGS[@]}" >/dev/null 2>&1 || true
    fi

    # Docker Engine Check
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "\n${Y}➜ Docker Engine is not installed. Installing Docker CE...${N}"
        curl -sSL https://get.docker.com/ | CHANNEL=stable bash || true
        systemctl enable --now docker 2>/dev/null || true
    else
        systemctl start docker 2>/dev/null || true
    fi

    # Kernel Swap Accounting
    if [ -f /etc/default/grub ]; then
        if ! grep -q "swapaccount=1" /etc/default/grub; then
            sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="swapaccount=1 /g' /etc/default/grub
            update-grub 2>/dev/null || true
        fi
    fi

    mkdir -p /etc/pterodactyl /etc/certs/wing /var/lib/pterodactyl/volumes /var/log/pterodactyl 2>/dev/null || true
    chmod 700 /etc/pterodactyl 2>/dev/null || true
}

# --- ENSURE WINGS BINARY ---
ensure_wings_binary() {
    if ! command -v wings >/dev/null 2>&1; then
        echo -e "\n${Y}➜ Wings binary not found. Downloading Wings for ${ARCH_TYPE}...${N}"
        WINGS_URL="https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${ARCH_TYPE}"
        curl -sSL -o /usr/local/bin/wings "$WINGS_URL"
        chmod u+x /usr/local/bin/wings
    fi

    cat << 'EOF' > /etc/systemd/system/wings.service
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload 2>/dev/null || true
    systemctl enable wings 2>/dev/null || true
}

# --- 4096-BIT LOCAL SSL GENERATION ---
generate_local_ssl() {
    echo -e "${Y}➜ Generating 4096-bit SSL Certificate...${N}"
    sudo mkdir -p /etc/certs/wing 2>/dev/null || mkdir -p /etc/certs/wing
    cd /etc/certs/wing || exit
    (sudo openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
        -subj "/C=NA/ST=NA/L=NA/O=NA/CN=Generic SSL Certificate" \
        -keyout privkey.pem -out fullchain.pem > /dev/null 2>&1) || \
    (openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
        -subj "/C=NA/ST=NA/L=NA/O=NA/CN=Generic SSL Certificate" \
        -keyout privkey.pem -out fullchain.pem > /dev/null 2>&1)
    check_success "SSL certificate generated"
    chmod 600 /etc/certs/wing/privkey.pem /etc/certs/wing/fullchain.pem 2>/dev/null || true
}


# ==============================================================================
#  PYTHON API & CONFIGURATION ENGINE
# ==============================================================================
python_api_engine() {
    python3 - "$@" << 'PYEOF'
import sys, json, ssl, urllib.request, urllib.error
import yaml

action = sys.argv[1]
panel_url = sys.argv[2].rstrip('/')
api_key = sys.argv[3]

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

def api_call(endpoint, method='GET', data=None):
    url = f"{panel_url}{endpoint}"
    headers = {
        'Authorization': f'Bearer {api_key}',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'User-Agent': 'Mack-Node-Setup/4.5'
    }
    encoded = json.dumps(data).encode('utf-8') if data else None
    req = urllib.request.Request(url, data=encoded, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=15) as res:
            raw = res.read().decode('utf-8')
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        err_text = e.read().decode('utf-8')
        try:
            parsed = json.loads(err_text)
            err_msg = "; ".join([x.get("detail", str(x)) for x in parsed.get("errors", [])])
        except Exception:
            err_msg = err_text[:200]
        return {'__error__': True, 'status': e.code, 'message': err_msg or f"HTTP {e.code}"}
    except Exception as e:
        return {'__error__': True, 'status': 0, 'message': str(e)}

# ----------------- ACTIONS -----------------

if action == "test_connection":
    res = api_call("/api/application/nodes")
    if res.get("__error__"):
        print(json.dumps({"success": False, "error": res["message"]}))
    else:
        print(json.dumps({"success": True}))

elif action == "get_nodes":
    res = api_call("/api/application/nodes")
    if res.get("__error__"):
        print(json.dumps({"success": False, "error": res["message"]}))
    else:
        nodes = []
        for n in res.get("data", []):
            attr = n.get("attributes", {})
            nodes.append({
                "id": attr.get("id"),
                "name": attr.get("name"),
                "fqdn": attr.get("fqdn"),
                "scheme": attr.get("scheme"),
                "memory": attr.get("memory"),
                "disk": attr.get("disk"),
                "daemon_listen": attr.get("daemon_listen", 443),
                "daemon_sftp": attr.get("daemon_sftp", 2022)
            })
        print(json.dumps({"success": True, "nodes": nodes}))

elif action == "get_or_create_location":
    res = api_call("/api/application/locations")
    if res.get("__error__"):
        print(json.dumps({"success": False, "error": res["message"]}))
        sys.exit(0)
    
    locs = res.get("data", [])
    if locs:
        first_loc = locs[0].get("attributes", {})
        print(json.dumps({"success": True, "location_id": first_loc.get("id"), "name": first_loc.get("short")}))
    else:
        create_res = api_call("/api/application/locations", method='POST', data={
            "short": "loc-1",
            "long": "Default Node Location"
        })
        if create_res.get("__error__"):
            print(json.dumps({"success": False, "error": create_res["message"]}))
        else:
            loc_id = create_res.get("attributes", {}).get("id")
            print(json.dumps({"success": True, "location_id": loc_id, "name": "loc-1"}))

elif action == "create_node":
    node_payload = json.loads(sys.argv[4])
    # LOCK PANEL NODE PORT TO 443
    node_payload["daemon_listen"] = 443
    node_payload["daemon_sftp"] = 2022
    node_payload["scheme"] = "https"

    res = api_call("/api/application/nodes", method='POST', data=node_payload)
    if res.get("__error__"):
        print(json.dumps({"success": False, "error": res["message"]}))
    else:
        node_attr = res.get("attributes", {})
        print(json.dumps({
            "success": True,
            "node_id": node_attr.get("id"),
            "name": node_attr.get("name"),
            "fqdn": node_attr.get("fqdn"),
            "daemon_listen": node_attr.get("daemon_listen")
        }))

elif action == "create_allocations":
    node_id = sys.argv[4]
    alloc_ip = sys.argv[5]
    alloc_alias = sys.argv[6]
    alloc_ports = sys.argv[7].split(",")
    payload = {
        "ip": alloc_ip,
        "alias": alloc_alias if alloc_alias else None,
        "ports": alloc_ports
    }
    res = api_call(f"/api/application/nodes/{node_id}/allocations", method='POST', data=payload)
    if res.get("__error__"):
        print(json.dumps({"success": False, "error": res["message"]}))
    else:
        print(json.dumps({"success": True}))

elif action == "fetch_and_write_config":
    node_id = sys.argv[4]
    ssl_mode = sys.argv[5]
    cert_path = sys.argv[6]
    key_path = sys.argv[7]
    dest_file = sys.argv[8]

    res = api_call(f"/api/application/nodes/{node_id}/configuration")
    if res.get("__error__"):
        print(json.dumps({"success": False, "error": res["message"]}))
        sys.exit(0)

    cfg = res
    if "api" not in cfg:
        cfg["api"] = {}
    if "ssl" not in cfg["api"]:
        cfg["api"]["ssl"] = {}

    # LOCK WINGS DAEMON PORT TO 8080 ON THIS MACHINE
    cfg["api"]["host"] = "0.0.0.0"
    cfg["api"]["port"] = 8080

    if ssl_mode in ["public", "local"]:
        cfg["api"]["ssl"]["enabled"] = True
        cfg["api"]["ssl"]["cert"] = cert_path
        cfg["api"]["ssl"]["key"] = key_path
    else:
        cfg["api"]["ssl"]["enabled"] = False
        cfg["api"]["ssl"]["cert"] = ""
        cfg["api"]["ssl"]["key"] = ""

    if "system" not in cfg:
        cfg["system"] = {}
    cfg["system"]["data"] = "/var/lib/pterodactyl/volumes"

    try:
        with open(dest_file, "w") as f:
            yaml.dump(cfg, f, default_flow_style=False, sort_keys=False)
        print(json.dumps({"success": True}))
    except Exception as e:
        print(json.dumps({"success": False, "error": str(e)}))

PYEOF
}

# ==============================================================================
#  URL & API KEY: ASKS ONLY ONCE, AUTO-LOADS SILENTLY
# ==============================================================================
get_panel_credentials() {
    # Check if credentials are saved
    if [ -f "$CREDENTIALS_FILE" ]; then
        SAVED_URL=$(python3 -c "import json; print(json.load(open('$CREDENTIALS_FILE')).get('url', ''))" 2>/dev/null)
        SAVED_KEY=$(python3 -c "import json; print(json.load(open('$CREDENTIALS_FILE')).get('key', ''))" 2>/dev/null)

        if [ -n "$SAVED_URL" ] && [ -n "$SAVED_KEY" ]; then
            PANEL_URL="$SAVED_URL"
            API_KEY="$SAVED_KEY"
            echo -e "${G}✔ Loaded saved Panel Credentials (${W}$PANEL_URL${G})${N}"
            return 0
        fi
    fi

    # IF NOT SAVED, ASK ONLY ONCE AND SAVE PERMANENTLY:
    while true; do
        echo -e "${C}${BOLD}┌─[ 🔑 PTERODACTYL APPLICATION API LOGIN (ONE-TIME SETUP) ]${N}"
        echo -e "${C}│${N} ${W}Panel URL and API Key will be saved permanently.${N}"
        echo -e "${C}│${N} ${GR}(To change later, run: bash /root/nodesetup.sh --reset)${N}"
        echo -ne "${C}├─╼ ${W}Enter Panel URL (e.g. https://panel.example.com): ${N}"
        read -r PANEL_URL
        PANEL_URL="${PANEL_URL%/}"

        echo -ne "${C}└─╼ ${W}Enter Application API Key (ptla_...): ${N}"
        read -r API_KEY

        echo -e "\n${Y}➜ Testing connection to $PANEL_URL...${N}"
        TEST_RES=$(python_api_engine "test_connection" "$PANEL_URL" "$API_KEY")
        IS_OK=$(echo "$TEST_RES" | python3 -c "import sys, json; print(json.load(sys.stdin).get('success'))" 2>/dev/null)

        if [ "$IS_OK" == "True" ]; then
            echo -e "${G}✔ Authentication Successful!${N}"
            # Save credentials permanently
            python3 -c "
import json
with open('$CREDENTIALS_FILE', 'w') as f:
    json.dump({'url': '$PANEL_URL', 'key': '$API_KEY'}, f, indent=2)
"
            chmod 600 "$CREDENTIALS_FILE" 2>/dev/null || true
            echo -e "${G}✔ Saved credentials to $CREDENTIALS_FILE (Won't ask again!)${N}"
            sleep 1
            break
        else
            ERR_MSG=$(echo "$TEST_RES" | python3 -c "import sys, json; print(json.load(sys.stdin).get('error', 'Authentication failed'))" 2>/dev/null)
            echo -e "${R}✖ Connection Failed: $ERR_MSG${N}"
            echo -ne "\n${W}Try again? [Y/n]: ${N}"; read -r RETRY
            [[ "$RETRY" == "n" || "$RETRY" == "N" ]] && exit 1
        fi
    done
}

# ==============================================================================
#  MAIN STREAMLINED SETUP WORKFLOW (ASKS ONLY ONCE)
# ==============================================================================
main() {
    detect_system
    install_prerequisites
    header

    # 1. Ask Domain / FQDN (ONCE)
    echo -e "${C}${BOLD}┌─[ 1. NODE DOMAIN / FQDN ]${N}"
    echo -e "${C}│${N} Detected Server WAN IP: ${G}$PUBLIC_IP${N}"
    echo -ne "${C}└─╼ ${W}Enter Node Domain / FQDN [${PUBLIC_IP}]: ${N}"
    read -r DOMAIN
    [ -z "$DOMAIN" ] && DOMAIN="$PUBLIC_IP"

    # 2. SSL Setup (ONCE)
    echo -e "\n${C}${BOLD}┌─[ 2. SSL CERTIFICATE SETUP ]${N}"
    echo -e "${C}│${N}  ${B}[1]${N} ${G}Local 4096-bit SSL (/etc/certs/wing/fullchain.pem & privkey.pem)${N}"
    echo -e "${C}│${N}  ${B}[2]${N} ${C}Public Certbot / Let's Encrypt SSL${N}"
    echo -e "${C}│${N}  ${B}[3]${N} ${Y}HTTP Mode (No SSL)${N}"
    echo -e "${C}└────────────────────────────────────────────────────────────${N}"
    echo -ne "${C}Choose SSL Mode [1-3] (default: 1): ${N}"
    read -r SSL_CHOICE
    [ -z "$SSL_CHOICE" ] && SSL_CHOICE="1"

    case "$SSL_CHOICE" in
        1)
            SSL_MODE="local"
            SCHEME="https"
            generate_local_ssl
            ;;
        2)
            SSL_MODE="public"
            SCHEME="https"
            echo -e "\n${Y}➜ Requesting Certbot SSL for ${W}$DOMAIN${Y}...${N}"
            apt-get install -y certbot >/dev/null 2>&1 || true
            systemctl stop wings nginx 2>/dev/null || true
            RANDOM_EMAIL="ssl_$(head /dev/urandom | tr -dc a-z0-9 | head -c 6)@$DOMAIN"
            if certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos --email "$RANDOM_EMAIL" 2>/dev/null; then
                mkdir -p /etc/certs/wing 2>/dev/null || true
                ln -sf "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$CERT_FILE"
                ln -sf "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "$KEY_FILE"
                echo -e "${G}✔ Certbot SSL obtained and symlinked!${N}"
            else
                echo -e "${Y}⚠️ Certbot failed. Falling back to 4096-bit Local SSL...${N}"
                SSL_MODE="local"
                generate_local_ssl
            fi
            ;;
        3)
            SSL_MODE="http"
            SCHEME="http"
            ;;
        *)
            SSL_MODE="local"
            SCHEME="https"
            generate_local_ssl
            ;;
    esac

    # 3. Panel URL & API Key (Silently loads if saved, asks ONCE if new)
    echo ""
    get_panel_credentials
    sleep 1

    header

    # 4. Node Create ya nahi menu ("node crate ya nhi")
    echo -e "${C}${BOLD}┌─[ 3. NODE CREATION / SELECTION ]${N}"
    echo -e "${C}│${N} Panel Target: ${W}$PANEL_URL${N}"
    echo -e "${C}│${N}"
    echo -e "${C}│${N}  ${B}[1]${N} ${G}⚡ Auto-Create a NEW Node on Panel (Port 443 Locked)${N}"
    echo -e "${C}│${N}  ${B}[2]${N} ${C}📋 Select an EXISTING Node from Panel${N}"
    echo -e "${C}└────────────────────────────────────────────────────────────${N}"
    echo -ne "${C}Node create karein ya existing select karein? [1/2] (default: 1): ${N}"
    read -r NODE_ACTION
    [ -z "$NODE_ACTION" ] && NODE_ACTION="1"

    if [ "$NODE_ACTION" == "1" ]; then
        # AUTO-CREATE NEW NODE
        echo -e "\n${Y}➜ Checking Location on Panel...${N}"
        LOC_RES=$(python_api_engine "get_or_create_location" "$PANEL_URL" "$API_KEY")
        LOC_ID=$(echo "$LOC_RES" | python3 -c "import sys, json; print(json.load(sys.stdin).get('location_id', 1))" 2>/dev/null)
        LOC_NAME=$(echo "$LOC_RES" | python3 -c "import sys, json; print(json.load(sys.stdin).get('name', 'Default'))" 2>/dev/null)
        echo -e "${G}✔ Using Location: $LOC_NAME (ID: $LOC_ID)${N}"

        DEFAULT_NAME="Node-$(hostname -s 2>/dev/null || echo "$RANDOM")"
        echo -ne "\n${W}Node Name [${DEFAULT_NAME}]: ${N}"; read -r NODE_NAME
        [ -z "$NODE_NAME" ] && NODE_NAME="$DEFAULT_NAME"

        echo -ne "${W}Total RAM in MB [${TOTAL_RAM_MB}]: ${N}"; read -r NODE_RAM
        [ -z "$NODE_RAM" ] && NODE_RAM="$TOTAL_RAM_MB"

        echo -ne "${W}Total Disk in MB [${TOTAL_DISK_MB}]: ${N}"; read -r NODE_DISK
        [ -z "$NODE_DISK" ] && NODE_DISK="$TOTAL_DISK_MB"

        echo -e "\n${GR}Panel Node Port  : 443 (LOCKED)${N}"
        echo -e "${GR}Wings Daemon Port: 8080 (LOCKED)${N}"
        echo -e "${GR}SFTP Port        : 2022 (LOCKED)${N}"

        PAYLOAD=$(python3 -c "
import json
p = {
    'name': '$NODE_NAME',
    'location_id': int('$LOC_ID'),
    'fqdn': '$DOMAIN',
    'scheme': 'https',
    'memory': int('$NODE_RAM'),
    'memory_overallocate': 0,
    'disk': int('$NODE_DISK'),
    'disk_overallocate': 0,
    'upload_size': 100,
    'daemon_sftp': 2022,
    'daemon_listen': 443,
    'behind_proxy': False,
    'maintenance_mode': False,
    'public': True
}
print(json.dumps(p))
")

        echo -e "\n${Y}➜ Creating Node '$NODE_NAME' on Panel with Port 443...${N}"
        CREATE_RES=$(python_api_engine "create_node" "$PANEL_URL" "$API_KEY" "$PAYLOAD")
        CREATE_SUCCESS=$(echo "$CREATE_RES" | python3 -c "import sys, json; print(json.load(sys.stdin).get('success'))" 2>/dev/null)

        if [ "$CREATE_SUCCESS" != "True" ]; then
            CREATE_ERR=$(echo "$CREATE_RES" | python3 -c "import sys, json; print(json.load(sys.stdin).get('error', 'Node creation failed'))" 2>/dev/null)
            echo -e "${R}✖ Failed to create node: $CREATE_ERR${N}"
            exit 1
        fi

        NODE_ID=$(echo "$CREATE_RES" | python3 -c "import sys, json; print(json.load(sys.stdin).get('node_id'))" 2>/dev/null)
        echo -e "${G}✔ Node '$NODE_NAME' successfully created with ID: $NODE_ID (Port 443)!${N}"

        # Auto IP Allocations
        echo -ne "\n${C}Auto-create initial IP allocations (ports 25565-25575)? [Y/n]: ${N}"
        read -r ALLOC_CHOICE
        if [[ "$ALLOC_CHOICE" != "n" && "$ALLOC_CHOICE" != "N" ]]; then
            PORTS="25565,25566,25567,25568,25569,25570,25571,25572,25573,25574,25575"
            echo -e "${Y}➜ Adding allocations for $PUBLIC_IP (ports 25565-25575)...${N}"
            python_api_engine "create_allocations" "$PANEL_URL" "$API_KEY" "$NODE_ID" "$PUBLIC_IP" "$DOMAIN" "$PORTS" >/dev/null 2>&1 || true
            echo -e "${G}✔ Allocations added successfully.${N}"
        fi

    else
        # SELECT EXISTING NODE
        echo -e "\n${Y}➜ Fetching existing nodes from Panel...${N}"
        NODES_RES=$(python_api_engine "get_nodes" "$PANEL_URL" "$API_KEY")

        echo -e "\n${W}Available Nodes on Panel:${N}"
        echo -e "${GR}────────────────────────────────────────────────────────────${N}"
        python3 -c "
import json
data = json.loads('''$NODES_RES''')
nodes = data.get('nodes', [])
if not nodes:
    print('  No nodes found on panel.')
else:
    for n in nodes:
        print(f\"  [{n['id']}] {n['name']} (FQDN: {n['fqdn']} | Port: {n.get('daemon_listen', 443)} | RAM: {n['memory']}MB)\")
"
        echo -e "${GR}────────────────────────────────────────────────────────────${N}"
        echo -ne "${Y}Enter Node ID to deploy: ${N}"
        read -r NODE_ID

        if [ -z "$NODE_ID" ]; then
            echo -e "${R}✖ Node ID cannot be empty.${N}"
            exit 1
        fi
    fi

    header

    # 5. Auto Config Setup (Wings Port 8080 LOCKED)
    echo -e "${C}${BOLD}┌─[ 4. AUTO-CONFIGURING WINGS (config.yml) ]${N}"
    echo -e "${C}│${N} Node ID          : ${W}$NODE_ID${N}"
    echo -e "${C}│${N} Wings Local Port : ${G}8080 (LOCKED)${N}"
    echo -e "${C}│${N} Panel Listen Port: ${G}443 (LOCKED)${N}"
    echo -e "${C}│${N} SSL Certificates : ${GR}$CERT_FILE & $KEY_FILE${N}"
    echo -e "${C}└────────────────────────────────────────────────────────────${N}"

    echo -e "\n${Y}➜ Pulling configuration from Panel & locking Wings port to 8080...${N}"
    CONFIG_RES=$(python_api_engine "fetch_and_write_config" "$PANEL_URL" "$API_KEY" "$NODE_ID" "$SSL_MODE" "$CERT_FILE" "$KEY_FILE" "/etc/pterodactyl/config.yml")
    chmod 600 /etc/pterodactyl/config.yml 2>/dev/null || true
    echo -e "${G}✔  updated successfully.${N}"

    # 6. Start & Verify Wings
    ensure_wings_binary
    echo -e "\n${Y}➜ Starting Wings daemon...${N}"
    systemctl daemon-reload 2>/dev/null || true
    systemctl restart wings 2>/dev/null || true
    sleep 2

    detect_system
    header

    # Completion Banner
    echo -e "${G}╔════════════════════════════════════════════════════════════╗${N}"
    echo -e "${G}║            🎉 NODE SETUP COMPLETED SUCCESSFULLY!           ║${N}"
    echo -e "${G}╚════════════════════════════════════════════════════════════╝${N}"
    echo -e "${W}  Node ID            :${G} $NODE_ID${N}"
    echo -e "${W}  Domain / FQDN      :${C} $DOMAIN${N}"
    echo -e "${W}  Panel URL          :${C} $PANEL_URL${N}"
    echo -e "${W}  Panel Node Port    :${G} 443 (LOCKED)${N}"
    echo -e "${W}  Wings Daemon Port  :${G} 8080 (LOCKED)${N}"
    echo -e "${W}  Wings Status       :${G} $WINGS_STATUS${N}"
    echo -e "${G}────────────────────────────────────────────────────────────${N}"
    echo -e "${W}Management Commands:${N}"
    echo -e "  • Check Status     : ${CYAN}systemctl status wings${N}"
    echo -e "  • Live Logs        : ${CYAN}journalctl -u wings -f${N}"
    echo -e "  • Reset Saved Login: ${CYAN}bash /root/nodesetup.sh --reset${N}"
    echo -e "  • Wings Manager    : ${CYAN}bash /root/run.sh${N}"
    echo -e "${G}────────────────────────────────────────────────────────────${N}\n"
}

main "$@"
