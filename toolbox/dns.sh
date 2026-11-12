#!/bin/bash

# ==============================================================================
#  CLOUDFLARE COMMANDER v4.0  ◈  NEXT-GEN TUNNEL ENGINE (NEW TYPE)
# ==============================================================================

# --- THEME & NEON COLOR PALETTE ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- STATUS ICONS ---
ICON_RUN="${GREEN}●${NC}"
ICON_STOP="${RED}●${NC}"
ICON_WAIT="${YELLOW}◌${NC}"
ICON_CHECK="${GREEN}✔${NC}"
ICON_ERR="${RED}✖${NC}"
ICON_BOLT="${YELLOW}⚡${NC}"
ICON_ARROW="${PURPLE}➜${NC}"

# Detect system architecture
get_arch() {
    local raw_arch
    raw_arch=$(dpkg --print-architecture 2>/dev/null || uname -m 2>/dev/null)
    case "$raw_arch" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l|armhf) echo "armhf" ;;
        i386|i686) echo "386" ;;
        *) echo "$raw_arch" ;;
    esac
}

# Check if systemd is active as init
has_systemd() {
    [[ -d "/run/systemd/system" ]]
}

# Check if cloudflared is running
is_service_running() {
    if pgrep -x cloudflared >/dev/null 2>&1; then
        return 0
    fi
    if has_systemd; then
        /bin/systemctl is-active --quiet cloudflared 2>/dev/null && return 0
    fi
    return 1
}

# Service Management Wrappers (handles both systemd and non-systemd/containers)
svc_start() {
    if has_systemd; then
        sudo /bin/systemctl start cloudflared 2>/dev/null
    elif [ -x /etc/init.d/cloudflared ]; then
        sudo /etc/init.d/cloudflared start 2>/dev/null
    elif command -v service &>/dev/null && [ -f /etc/init.d/cloudflared ]; then
        sudo service cloudflared start 2>/dev/null
    fi
}

svc_stop() {
    if has_systemd; then
        sudo /bin/systemctl stop cloudflared 2>/dev/null
    elif [ -x /etc/init.d/cloudflared ]; then
        sudo /etc/init.d/cloudflared stop 2>/dev/null
    elif command -v service &>/dev/null && [ -f /etc/init.d/cloudflared ]; then
        sudo service cloudflared stop 2>/dev/null
    fi
    sudo pkill -x cloudflared 2>/dev/null
}

svc_restart() {
    if has_systemd; then
        sudo /bin/systemctl restart cloudflared 2>/dev/null
    elif [ -x /etc/init.d/cloudflared ]; then
        sudo /etc/init.d/cloudflared restart 2>/dev/null
    elif command -v service &>/dev/null && [ -f /etc/init.d/cloudflared ]; then
        sudo service cloudflared restart 2>/dev/null
    else
        svc_stop
        sleep 1
        svc_start
    fi
}

# --- DYNAMIC TELEMETRY HEADER ---
show_header() {
    clear 2>/dev/null || true
    
    local s_status="${GRAY}NOT INSTALLED${NC}"
    local s_pid="${GRAY}---${NC}"
    local s_uptime="${GRAY}---${NC}"
    local s_ver="${GRAY}---${NC}"
    local s_mem="${GRAY}---${NC}"
    local s_latency="${GRAY}---${NC}"
    local arch
    arch=$(get_arch)

    # 1. Cloudflared Binary Check
    if command -v cloudflared &>/dev/null; then
        s_ver=$(cloudflared --version 2>/dev/null | awk '{print $3}' | head -n 1)
        [[ -z "$s_ver" ]] && s_ver="Installed"
        
        # Service Status Check
        if is_service_running; then
            s_status="${GREEN}ACTIVE (ONLINE)${NC}"
            local raw_pid
            raw_pid=$(pgrep -d ', ' -x cloudflared 2>/dev/null | head -n 1)
            s_pid="${WHITE}${raw_pid:-Active}${NC}"
            
            # Memory & Uptime
            if [[ -n "$raw_pid" ]]; then
                local first_pid="${raw_pid%%,*}"
                local mem_kb
                mem_kb=$(ps -p "$first_pid" -o rss= 2>/dev/null | xargs)
                if [[ -n "$mem_kb" && "$mem_kb" =~ ^[0-9]+$ ]]; then
                    s_mem="${CYAN}$(( mem_kb / 1024 ))MB${NC}"
                fi

                local el_time
                el_time=$(ps -p "$first_pid" -o etime= 2>/dev/null | xargs)
                [[ -n "$el_time" ]] && s_uptime="${CYAN}${el_time}${NC}"
            fi
            [[ "$s_uptime" == "---" ]] && s_uptime="${CYAN}Running${NC}"
        else
            s_status="${RED}INACTIVE (STOPPED)${NC}"
        fi
    fi

    # 2. Network Latency Check (Cloudflare 1.1.1.1)
    if command -v ping &>/dev/null; then
        local p
        p=$(ping -c 1 -W 1 1.1.1.1 2>/dev/null | grep -oP 'time=\K[0-9.]+' | head -n 1)
        if [[ -n "$p" ]]; then
            s_latency="${GREEN}${p}ms${NC}"
        else
            s_latency="${YELLOW}Timeout${NC}"
        fi
    elif timeout 1 bash -c "echo > /dev/tcp/1.1.1.1/53" 2>/dev/null; then
        s_latency="${GREEN}Connected${NC}"
    else
        s_latency="${GRAY}N/A${NC}"
    fi

    # 3. Render Next-Gen UI Frame
    echo -e "${PURPLE} ╭──────────────────────────────────────────────────────────────╮${NC}"
    echo -e "${PURPLE} │${NC}   ${YELLOW}⚡${NC}  ${WHITE}${BOLD}CLOUDFLARE COMMANDER v4.0${NC}  ${PURPLE}◈${NC}  ${CYAN}[NEXT-GEN TUNNEL ENGINE]${NC}  ${PURPLE}│${NC}"
    echo -e "${PURPLE} ╰──────────────────────────────────────────────────────────────╯${NC}"
    echo -e "${CYAN}  ┌─ SYSTEM TELEMETRY ─────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}  │${NC}  Status  : $s_status"
    echo -e "${CYAN}  │${NC}  Arch    : ${WHITE}$arch${NC}           ${GRAY}│${NC}  Version : ${WHITE}$s_ver${NC}"
    echo -e "${CYAN}  │${NC}  PID     : $s_pid             ${GRAY}│${NC}  Memory  : $s_mem"
    echo -e "${CYAN}  │${NC}  Uptime  : $s_uptime          ${GRAY}│${NC}  Latency : $s_latency"
    echo -e "${CYAN}  └────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

# Pretty Print Step Messages
step_msg() {
    echo -e "  ${CYAN}[INFO]${NC} $1..."
}

success_msg() {
    echo -e "  ${GREEN}[DONE]${NC} $1"
}

error_msg() {
    echo -e "  ${RED}[FAIL]${NC} $1"
}

warn_msg() {
    echo -e "  ${YELLOW}[WARN]${NC} $1"
}

# Universal Binary Installer (APT with GitHub Releases Direct Fallback)
ensure_binary_installed() {
    if command -v cloudflared &>/dev/null; then
        return 0
    fi

    local arch
    arch=$(get_arch)
    step_msg "Attempting repository installation"
    
    sudo mkdir -p --mode=0755 /usr/share/keyrings 2>/dev/null
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg 2>/dev/null | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list >/dev/null
    sudo apt-get update -qq >/dev/null 2>&1
    sudo apt-get install -y cloudflared -qq >/dev/null 2>&1

    # Fallback to direct standalone release binary if APT did not install
    if ! command -v cloudflared &>/dev/null; then
        step_msg "APT unavailable, falling back to direct binary download"
        local dl_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}"
        sudo curl -fsSL "$dl_url" -o /usr/local/bin/cloudflared >/dev/null 2>&1
        sudo chmod +x /usr/local/bin/cloudflared 2>/dev/null
    fi

    if command -v cloudflared &>/dev/null; then
        success_msg "Cloudflared binary successfully installed"
        return 0
    else
        error_msg "Failed to install cloudflared binary"
        return 1
    fi
}

# --- OPERATION 1: PRODUCTION TUNNEL (TOKEN-BASED SERVICE) ---
install_cf() {
    [[ "$CLI_MODE" != "true" ]] && show_header
    echo -e "${WHITE}${BOLD}  DEPLOY PRODUCTION TUNNEL (TOKEN SERVICE)${NC}"
    echo -e "${GRAY}  ────────────────────────────────────────────────────────────${NC}"
    sleep 0.5

    ensure_binary_installed || {
        if [[ "$CLI_MODE" != "true" ]]; then
            echo ""
            read -p "  Press [Enter] to return..."
        fi
        return 1
    }

    # Clean existing conflicting service
    if is_service_running; then
        step_msg "Stopping existing service instance"
        sudo cloudflared service uninstall >/dev/null 2>&1
        svc_stop
        success_msg "Old service cleaned"
    fi

    # Token Input
    if [[ -z "$USER_TOKEN" ]]; then
        echo ""
        echo -e "${YELLOW}  ╭──────────────────────────────────────────────────────────╮${NC}"
        echo -e "${YELLOW}  │${NC}                   ${WHITE}${BOLD}CLOUDFLARE TUNNEL TOKEN${NC}                ${YELLOW}│${NC}"
        echo -e "${YELLOW}  │${NC} Paste your Tunnel Token below.                            ${YELLOW}│${NC}"
        echo -e "${YELLOW}  │${NC} ${GRAY}(Accepts raw token or full 'cloudflared service...' cmd)${NC} ${YELLOW}│${NC}"
        echo -e "${YELLOW}  ╰──────────────────────────────────────────────────────────╯${NC}"
        echo ""
        echo -ne "${PURPLE}  ➤ INPUT TOKEN:${NC} " 
        read USER_TOKEN
    fi

    # Clean token if user pasted the entire command
    CLEAN_TOKEN=$(echo "$USER_TOKEN" | sed 's/sudo //g' | sed 's/cloudflared service install //g' | xargs)

    if [[ -z "$CLEAN_TOKEN" ]]; then
        error_msg "Token cannot be empty!"
        if [[ "$CLI_MODE" != "true" ]]; then
            echo ""
            read -p "  Press [Enter] to return..."
        fi
        return 1
    fi

    step_msg "Registering tunnel daemon"
    sudo cloudflared service uninstall >/dev/null 2>&1
    sudo cloudflared service install "$CLEAN_TOKEN" >/dev/null 2>&1
    
    if has_systemd; then
        sudo /bin/systemctl daemon-reload 2>/dev/null
        sudo /bin/systemctl enable cloudflared 2>/dev/null
        sudo /bin/systemctl start cloudflared 2>/dev/null
    else
        svc_start
    fi

    echo ""
    echo -e "${CYAN}  Initializing daemon and synchronizing with Cloudflare edge...${NC}"
    for i in {1..20}; do echo -ne "▓"; sleep 0.1; done
    echo ""

    if is_service_running; then
        echo ""
        echo -e "${GREEN}${BOLD}  ✔ SUCCESS: Tunnel is active, encrypted, and stable!${NC}"
    else
        echo ""
        echo -e "${RED}${BOLD}  ✖ ERROR: Service failed to enter running state.${NC}"
        echo -e "${GRAY}  Check token validity or run './dns.sh logs' to inspect.${NC}"
    fi

    echo ""
    if [[ "$CLI_MODE" != "true" ]]; then
        read -p "  Press [Enter] to return to menu..."
    fi
}

# --- OPERATION 2: QUICK TUNNEL (EPHEMERAL / TRYCLOUDFLARE - NEW TYPE) ---
quick_tunnel() {
    [[ "$CLI_MODE" != "true" ]] && show_header
    echo -e "${WHITE}${BOLD}  LAUNCH EPHEMERAL QUICK TUNNEL (TRYCLOUDFLARE)${NC}"
    echo -e "${GRAY}  Instant public HTTPS tunnel without needing an account.${NC}"
    echo -e "${GRAY}  ────────────────────────────────────────────────────────────${NC}"

    ensure_binary_installed || {
        if [[ "$CLI_MODE" != "true" ]]; then
            echo ""
            read -p "  Press [Enter] to return..."
        fi
        return 1
    }

    local target_port="${1:-}"
    if [[ -z "$target_port" ]]; then
        echo -ne "\n${PURPLE}  ➤ Local Port to Expose (Default: 8080): ${NC}"
        read target_port
        target_port="${target_port:-8080}"
    fi

    echo ""
    step_msg "Establishing tunnel to http://localhost:${target_port}"
    echo -e "${YELLOW}  Press [Ctrl + C] at any time to terminate the quick tunnel.${NC}"
    echo -e "${GRAY}  ────────────────────────────────────────────────────────────${NC}"
    echo ""

    cloudflared tunnel --url "http://localhost:${target_port}"
    
    echo ""
    if [[ "$CLI_MODE" != "true" ]]; then
        read -p "  Tunnel stopped. Press [Enter] to return..."
    fi
}

# --- OPERATION 3: FULL SYSTEM UPDATE (BINARY & SERVICE RE-SYNC) ---
update_cf() {
    [[ "$CLI_MODE" != "true" ]] && show_header
    echo -e "${WHITE}${BOLD}  FULL SYSTEM UPDATE SEQUENCE${NC}"
    echo -e "${GRAY}  ────────────────────────────────────────────────────────────${NC}"
    sleep 0.5

    if ! command -v cloudflared &>/dev/null; then
        warn_msg "cloudflared is not currently installed"
        step_msg "Performing fresh installation"
        ensure_binary_installed
        if [[ "$CLI_MODE" != "true" ]]; then
            echo ""
            read -p "  Press [Enter] to return..."
        fi
        return
    fi

    local prev_ver
    prev_ver=$(cloudflared --version 2>/dev/null | awk '{print $3}' | head -n 1)
    step_msg "Current installed version: ${WHITE}${prev_ver:-unknown}${NC}"

    # 1. Update package managers
    step_msg "Refreshing package repositories"
    sudo apt-get update -qq >/dev/null 2>&1
    sudo apt-get --only-upgrade install -y cloudflared -qq >/dev/null 2>&1

    # 2. Trigger native binary self-update
    step_msg "Executing native cloudflared update"
    sudo cloudflared update >/dev/null 2>&1

    # 3. Direct GitHub binary update if needed
    local current_ver
    current_ver=$(cloudflared --version 2>/dev/null | awk '{print $3}' | head -n 1)
    local arch
    arch=$(get_arch)
    if [[ -z "$current_ver" || "$current_ver" == "$prev_ver" ]]; then
        step_msg "Checking Cloudflare releases for direct binary upgrade"
        sudo curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}" -o /tmp/cloudflared-latest 2>/dev/null
        if [[ -s /tmp/cloudflared-latest ]]; then
            sudo chmod +x /tmp/cloudflared-latest
            local target_bin
            target_bin=$(command -v cloudflared)
            sudo mv /tmp/cloudflared-latest "${target_bin:-/usr/local/bin/cloudflared}"
            current_ver=$(cloudflared --version 2>/dev/null | awk '{print $3}' | head -n 1)
        fi
    fi

    success_msg "Updated binary version: ${WHITE}${current_ver:-latest}${NC}"

    # 4. Service Re-synchronization
    if is_service_running; then
        step_msg "Reloading and restarting tunnel daemon"
        svc_restart
        
        echo ""
        echo -e "${CYAN}  Verifying service stabilization...${NC}"
        for i in {1..15}; do echo -ne "▓"; sleep 0.1; done
        echo ""

        if is_service_running; then
            success_msg "Tunnel service online and running smoothly!"
        else
            error_msg "Service restart encountered an issue"
        fi
    else
        step_msg "Tunnel service is stopped. Run option [1] to activate."
    fi

    echo ""
    if [[ "$CLI_MODE" != "true" ]]; then
        read -p "  Press [Enter] to return to menu..."
    fi
}

# --- OPERATION 4: TOKEN MANAGEMENT ---
update_token_cf() {
    [[ "$CLI_MODE" != "true" ]] && show_header
    echo -e "${WHITE}${BOLD}  UPDATE TUNNEL TOKEN / REBIND${NC}"
    echo -e "${GRAY}  ────────────────────────────────────────────────────────────${NC}"

    if ! command -v cloudflared &>/dev/null; then
        error_msg "cloudflared binary not found. Please run Install first."
        if [[ "$CLI_MODE" != "true" ]]; then
            echo ""
            read -p "  Press [Enter] to return..."
        fi
        return 1
    fi

    echo ""
    echo -e "${YELLOW}  ╭──────────────────────────────────────────────────────────╮${NC}"
    echo -e "${YELLOW}  │${NC}                    ${WHITE}${BOLD}NEW TUNNEL TOKEN${NC}                      ${YELLOW}│${NC}"
    echo -e "${YELLOW}  │${NC} Paste your new Cloudflare Tunnel Token below:             ${YELLOW}│${NC}"
    echo -e "${YELLOW}  ╰──────────────────────────────────────────────────────────╯${NC}"
    echo ""
    echo -ne "${PURPLE}  ➤ INPUT NEW TOKEN:${NC} " 
    read USER_TOKEN

    CLEAN_TOKEN=$(echo "$USER_TOKEN" | sed 's/sudo //g' | sed 's/cloudflared service install //g' | xargs)

    if [[ -z "$CLEAN_TOKEN" ]]; then
        error_msg "Token cannot be empty!"
        if [[ "$CLI_MODE" != "true" ]]; then
            echo ""
            read -p "  Press [Enter] to return..."
        fi
        return 1
    fi

    step_msg "Rebinding service to new token"
    sudo cloudflared service uninstall >/dev/null 2>&1
    sudo cloudflared service install "$CLEAN_TOKEN" >/dev/null 2>&1
    svc_restart

    echo ""
    echo -e "${CYAN}  Re-initializing tunnel connection...${NC}"
    for i in {1..20}; do echo -ne "▓"; sleep 0.1; done
    echo ""

    if is_service_running; then
        echo ""
        echo -e "${GREEN}${BOLD}  ✔ SUCCESS: Tunnel re-bound and actively connected!${NC}"
    else
        echo ""
        echo -e "${RED}${BOLD}  ✖ ERROR: Failed to establish tunnel with new token.${NC}"
    fi

    echo ""
    if [[ "$CLI_MODE" != "true" ]]; then
        read -p "  Press [Enter] to return to menu..."
    fi
}

# --- OPERATION 5: POWER & SERVICE CONTROL ---
power_menu() {
    while true; do
        show_header
        echo -e "${WHITE}${BOLD}  POWER & SERVICE CONTROLLER${NC}"
        echo -e "${GRAY}  ────────────────────────────────────────────────────────────${NC}"
        echo -e "  ${CYAN}[1]${NC} 🔄 Restart Service"
        echo -e "  ${GREEN}[2]${NC} ▶  Start Service"
        echo -e "  ${RED}[3]${NC} ⏹  Stop Service"
        echo -e "  ${YELLOW}[4]${NC} 📌 Enable Auto-start on Boot"
        echo -e "  ${GRAY}[5]${NC} 🚫 Disable Auto-start on Boot"
        echo -e "  ${WHITE}[0]${NC} ↩  Return to Main Menu"
        echo ""
        echo -ne "${PURPLE}  ➤ SELECT [0-5]: ${NC}"
        read p_choice

        case $p_choice in
            1)
                step_msg "Restarting cloudflared"
                svc_restart
                sleep 1
                is_service_running && success_msg "Service active" || error_msg "Service inactive"
                sleep 1.5
                ;;
            2)
                step_msg "Starting cloudflared"
                svc_start
                sleep 1
                is_service_running && success_msg "Service running" || error_msg "Failed to start"
                sleep 1.5
                ;;
            3)
                step_msg "Stopping cloudflared"
                svc_stop
                sleep 1
                success_msg "Service stopped"
                sleep 1.5
                ;;
            4)
                if has_systemd; then
                    sudo /bin/systemctl enable cloudflared 2>/dev/null
                fi
                success_msg "Auto-start enabled"
                sleep 1.5
                ;;
            5)
                if has_systemd; then
                    sudo /bin/systemctl disable cloudflared 2>/dev/null
                fi
                success_msg "Auto-start disabled"
                sleep 1.5
                ;;
            0)
                break
                ;;
            *)
                echo -e "  ${RED}Invalid Option${NC}"
                sleep 1
                ;;
        esac
    done
}

# --- OPERATION 6: LIVE LOGS & TELEMETRY ---
view_logs() {
    [[ "$CLI_MODE" != "true" ]] && show_header
    echo -e "${WHITE}${BOLD}  LIVE CLOUDFLARE TUNNEL LOGS${NC}"
    echo -e "${GRAY}  ────────────────────────────────────────────────────────────${NC}"
    echo ""

    if has_systemd && command -v journalctl &>/dev/null; then
        sudo journalctl -u cloudflared -n 30 --no-pager
        echo ""
        echo -e "${CYAN}  Entering live stream mode (Press Ctrl+C to exit)...${NC}"
        sudo journalctl -u cloudflared -f
    elif [ -f /var/log/cloudflared.log ]; then
        tail -n 30 /var/log/cloudflared.log
        echo ""
        echo -e "${CYAN}  Entering live stream mode (Press Ctrl+C to exit)...${NC}"
        tail -f /var/log/cloudflared.log
    else
        step_msg "Checking process output"
        if pgrep -x cloudflared >/dev/null; then
            success_msg "cloudflared process is running (PID: $(pgrep -d ' ' -x cloudflared))"
        else
            warn_msg "No active service logs or running cloudflared process detected."
        fi
    fi

    echo ""
    if [[ "$CLI_MODE" != "true" ]]; then
        read -p "  Press [Enter] to return..."
    fi
}

# --- OPERATION 7: NETWORK & HEALTH CHECK ---
health_check() {
    [[ "$CLI_MODE" != "true" ]] && show_header
    echo -e "${WHITE}${BOLD}  NETWORK & HEALTH DIAGNOSTICS${NC}"
    echo -e "${GRAY}  ────────────────────────────────────────────────────────────${NC}"

    # 1. Cloudflare DNS check
    echo -ne "  ${CYAN}●${NC} Cloudflare Edge 1.1.1.1  : "
    if command -v ping &>/dev/null; then
        local p
        p=$(ping -c 2 -W 1 1.1.1.1 2>/dev/null | grep -oP 'time=\K[0-9.]+' | tail -n 1)
        if [[ -n "$p" ]]; then
            echo -e "${GREEN}${BOLD}REACHABLE${NC} (${p}ms)"
        else
            echo -e "${RED}${BOLD}UNREACHABLE / TIMEOUT${NC}"
        fi
    elif timeout 1 bash -c "echo > /dev/tcp/1.1.1.1/53" 2>/dev/null; then
        echo -e "${GREEN}${BOLD}REACHABLE${NC} (TCP/53)"
    else
        echo -e "${YELLOW}OFFLINE / BLOCKED${NC}"
    fi

    # 2. DNS resolution check
    echo -ne "  ${CYAN}●${NC} Cloudflare API DNS       : "
    if getent hosts api.cloudflare.com &>/dev/null; then
        echo -e "${GREEN}${BOLD}RESOLVED${NC}"
    else
        echo -e "${RED}${BOLD}FAILED TO RESOLVE${NC}"
    fi

    # 3. Binary state
    echo -ne "  ${CYAN}●${NC} Binary Integrity         : "
    if command -v cloudflared &>/dev/null; then
        local b_path
        b_path=$(command -v cloudflared)
        echo -e "${GREEN}${BOLD}VALID${NC} ($b_path)"
    else
        echo -e "${RED}${BOLD}MISSING${NC}"
    fi

    # 4. Service status
    echo -ne "  ${CYAN}●${NC} Daemon Service Status    : "
    if is_service_running; then
        echo -e "${GREEN}${BOLD}RUNNING (ONLINE)${NC}"
    else
        echo -e "${RED}${BOLD}STOPPED / OFFLINE${NC}"
    fi

    echo ""
    if [[ "$CLI_MODE" != "true" ]]; then
        read -p "  Press [Enter] to return..."
    fi
}

# --- OPERATION 8: CLEAN UNINSTALL & PURGE ---
uninstall_cf() {
    [[ "$CLI_MODE" != "true" ]] && show_header
    echo -e "${RED}${BOLD}  ⚠️  DANGER: COMPLETE SYSTEM PURGE${NC}"
    echo -e "${GRAY}  This will terminate and delete the tunnel service, remove the${NC}"
    echo -e "${GRAY}  cloudflared binary, and delete all associated configuration files.${NC}"
    echo ""
    if [[ -z "$confirm" ]]; then
        echo -ne "${RED}  Confirm purge? [y/N]: ${NC}"
        read confirm
    fi
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo ""
        step_msg "De-registering and stopping service"
        svc_stop
        sudo cloudflared service uninstall >/dev/null 2>&1
        if has_systemd; then
            sudo /bin/systemctl stop cloudflared >/dev/null 2>&1
            sudo /bin/systemctl disable cloudflared >/dev/null 2>&1
            sudo rm -f /etc/systemd/system/cloudflared.service
            sudo /bin/systemctl daemon-reload >/dev/null 2>&1
        fi

        step_msg "Removing cloudflared binaries"
        sudo apt-get remove -y --purge cloudflared -qq >/dev/null 2>&1
        sudo rm -f /usr/local/bin/cloudflared /usr/bin/cloudflared

        step_msg "Purging repository keys and cache"
        sudo rm -f /etc/apt/sources.list.d/cloudflared.list
        sudo rm -f /usr/share/keyrings/cloudflare-main.gpg
        sudo rm -rf /etc/cloudflared

        echo ""
        success_msg "Cloudflare Commander & cloudflared completely eradicated."
    else
        echo -e "\n  ${GRAY}Operation cancelled.${NC}"
    fi

    if [[ "$CLI_MODE" != "true" ]]; then
        sleep 2
    fi
}

# --- CLI ARGUMENT HANDLER ---
if [[ -n "$1" ]]; then
    CLI_MODE=true
    case "$1" in
        update|upgrade|full-update)
            update_cf
            ;;
        install)
            [[ -n "$2" ]] && USER_TOKEN="$2"
            install_cf
            ;;
        quick|temp)
            quick_tunnel "$2"
            ;;
        token|update-token)
            [[ -n "$2" ]] && USER_TOKEN="$2"
            update_token_cf
            ;;
        restart)
            svc_restart
            is_service_running && success_msg "Service restarted" || error_msg "Service restart failed"
            ;;
        start)
            svc_start
            is_service_running && success_msg "Service started" || error_msg "Service start failed"
            ;;
        stop)
            svc_stop
            success_msg "Service stopped"
            ;;
        logs|log)
            view_logs
            ;;
        health|check)
            health_check
            ;;
        status)
            show_header
            ;;
        uninstall|purge)
            [[ "$2" == "-y" || "$2" == "--yes" ]] && confirm="y"
            uninstall_cf
            ;;
        help|--help|-h)
            echo "Cloudflare Commander v4.0 (Next-Gen Tunnel Engine)"
            echo "Usage: $0 [COMMAND] [ARGS]"
            echo ""
            echo "Commands:"
            echo "  install [TOKEN]     Deploy production token tunnel service"
            echo "  quick [PORT]        Launch zero-config ephemeral trycloudflare tunnel"
            echo "  update              Run full system & binary update"
            echo "  token [TOKEN]       Rebind tunnel with a new token"
            echo "  restart             Restart cloudflared service"
            echo "  start               Start cloudflared service"
            echo "  stop                Stop cloudflared service"
            echo "  logs                Stream live tunnel logs"
            echo "  health              Run network & DNS diagnostics"
            echo "  status              Display telemetry dashboard"
            echo "  uninstall [-y]      Purge all cloudflared binaries and services"
            exit 0
            ;;
        *)
            echo "Unknown command: $1"
            echo "Run '$0 help' for available options."
            exit 1
            ;;
    esac
    exit 0
fi

# --- MAIN TUI MENU LOOP ---
while true; do
    show_header
    
    echo -e "${PURPLE} ╭── OPERATIONS MATRIX ─────────────────────────────────────────╮${NC}"
    echo -e "${PURPLE} │${NC}                                                              ${PURPLE}│${NC}"
    echo -e "${PURPLE} │${NC}  ${GREEN}[1]${NC} ${WHITE}${BOLD}🚀 Production Tunnel${NC}     ${GRAY}(Deploy Token Daemon Service)${NC}  ${PURPLE}│${NC}"
    echo -e "${PURPLE} │${NC}  ${CYAN}[2]${NC} ${WHITE}${BOLD}🌐 Quick Tunnel (Temp)${NC}   ${GRAY}(Instant trycloudflare URL) ${NC}  ${PURPLE}│${NC}"
    echo -e "${PURPLE} │${NC}  ${YELLOW}[3]${NC} ${WHITE}${BOLD}🔄 Full System Update${NC}    ${GRAY}(Upgrade Binary & Core Re-sync)${NC}${PURPLE}│${NC}"
    echo -e "${PURPLE} │${NC}  ${PURPLE}[4]${NC} ${WHITE}${BOLD}🔑 Token Management${NC}      ${GRAY}(Swap / Rebind Secret Key)  ${NC}  ${PURPLE}│${NC}"
    echo -e "${PURPLE} │${NC}  ${BLUE}[5]${NC} ${WHITE}${BOLD}⚡ Power Controller${NC}      ${GRAY}(Restart / Start / Stop)    ${NC}  ${PURPLE}│${NC}"
    echo -e "${PURPLE} │${NC}  ${WHITE}[6]${NC} ${WHITE}${BOLD}📊 Live Logs & Telemetry${NC} ${GRAY}(Stream Realtime Daemon Log)${NC}  ${PURPLE}│${NC}"
    echo -e "${PURPLE} │${NC}  ${GREEN}[7]${NC} ${WHITE}${BOLD}🩺 Network Diagnostics${NC}   ${GRAY}(Edge Latency & DNS Health) ${NC}  ${PURPLE}│${NC}"
    echo -e "${PURPLE} │${NC}  ${RED}[8]${NC} ${WHITE}${BOLD}🗑️  Purge & Eradicate${NC}    ${GRAY}(Clean Wipe All Traces)     ${NC}  ${PURPLE}│${NC}"
    echo -e "${PURPLE} │${NC}                                                              ${PURPLE}│${NC}"
    echo -e "${PURPLE} │${NC}  ${GRAY}[0] 🚪 Exit Commander${NC}                                        ${PURPLE}│${NC}"
    echo -e "${PURPLE} ╰──────────────────────────────────────────────────────────────╯${NC}"
    echo ""
    echo -e "${PURPLE}  ╭─(${WHITE}root@cloudflared${PURPLE})─[${CYAN}v4.0-engine${PURPLE}]${NC}"
    echo -ne "${PURPLE}  ╰─➤ ${WHITE}SELECT [0-8]: ${NC}"
    read choice

    case $choice in
        1) install_cf ;;
        2) quick_tunnel ;;
        3) update_cf ;;
        4) update_token_cf ;;
        5) power_menu ;;
        6) view_logs ;;
        7) health_check ;;
        8) uninstall_cf ;;
        0) clear 2>/dev/null || true; exit 0 ;;
        *) echo -e "  ${RED}Invalid Option${NC}"; sleep 1 ;;
    esac
done

