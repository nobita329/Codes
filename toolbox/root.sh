#!/bin/bash

# ==============================================================================
#  SSH COMMANDER v4.0  ◈  SERVER ACCESS & ROOT SECURITY SYSTEM (NEW TYPE)
# ==============================================================================

# --- THEME & NEON COLOR PALETTE ---
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
GRAY='\033[1;90m'
BOLD='\033[1m'
NC='\033[0m' # No Color

CONFIG_FILE="/etc/ssh/sshd_config"
BACKUP_DIR="/etc/ssh/backups"
BACKUP_FILE="/etc/ssh/sshd_config.bak"

# --- HELPER FUNCTIONS ---
msg_info() { echo -e "  ${CYAN}[INFO]${NC} $1..."; }
msg_ok()   { echo -e "  ${GREEN}[DONE]${NC} $1"; }
msg_warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
msg_err()  { echo -e "  ${RED}[FAIL]${NC} $1"; }

# Check init system
has_systemd() {
    [[ -d "/run/systemd/system" ]]
}

# Detect SSH service daemon name (ssh vs sshd)
get_ssh_service_name() {
    if has_systemd; then
        if /bin/systemctl list-unit-files 2>/dev/null | grep -q "^sshd\.service"; then
            echo "sshd"
            return
        elif /bin/systemctl list-unit-files 2>/dev/null | grep -q "^ssh\.service"; then
            echo "ssh"
            return
        fi
    fi
    if [ -f /etc/init.d/sshd ]; then
        echo "sshd"
    else
        echo "ssh"
    fi
}

# Check if SSH daemon is running
is_ssh_running() {
    if pgrep -x sshd >/dev/null 2>&1; then
        return 0
    fi
    local srv
    srv=$(get_ssh_service_name)
    if has_systemd; then
        /bin/systemctl is-active --quiet "$srv" 2>/dev/null && return 0
    fi
    return 1
}

# Safely restart SSH daemon
restart_ssh() {
    local srv
    srv=$(get_ssh_service_name)
    
    # Pre-flight syntax validation
    if command -v sshd &>/dev/null; then
        if ! sshd -t >/dev/null 2>&1; then
            # If sshd -t fails because of missing hostkeys, ignore that check
            local err_output
            err_output=$(sshd -t 2>&1)
            if echo "$err_output" | grep -qv "hostkeys available"; then
                msg_err "SSHD configuration test failed: $err_output"
                return 1
            fi
        fi
    fi

    if has_systemd; then
        sudo /bin/systemctl restart "$srv" 2>/dev/null
    elif [ -x "/etc/init.d/$srv" ]; then
        sudo "/etc/init.d/$srv" restart 2>/dev/null
    elif command -v service &>/dev/null; then
        sudo service "$srv" restart 2>/dev/null
    else
        sudo pkill -HUP sshd 2>/dev/null || sudo /usr/sbin/sshd 2>/dev/null
    fi
    return 0
}

# Parse configuration status
get_conf_status() {
    local param=$1
    local default=$2
    local val=""

    # Check override files in sshd_config.d first
    if [ -d "/etc/ssh/sshd_config.d" ]; then
        val=$(grep -hE "^[[:space:]]*${param}[[:space:]]+" /etc/ssh/sshd_config.d/*.conf 2>/dev/null | tail -n 1 | awk '{print $2}')
    fi

    # Fallback to main sshd_config
    if [[ -z "$val" && -f "$CONFIG_FILE" ]]; then
        val=$(grep -E "^[[:space:]]*${param}[[:space:]]+" "$CONFIG_FILE" 2>/dev/null | tail -n 1 | awk '{print $2}')
    fi

    if [[ -z "$val" ]]; then val="$default"; fi

    val=$(echo "$val" | tr '[:upper:]' '[:lower:]')
    if [[ "$val" == "yes" ]]; then
        echo -e "${GREEN}[ ON ]${NC}"
    elif [[ "$val" == "no" ]]; then
        echo -e "${RED}[ OFF ]${NC}"
    else
        echo -e "${YELLOW}[ $val ]${NC}"
    fi
}

get_ssh_port() {
    local port=""
    if [ -d "/etc/ssh/sshd_config.d" ]; then
        port=$(grep -hE "^[[:space:]]*Port[[:space:]]+" /etc/ssh/sshd_config.d/*.conf 2>/dev/null | head -n 1 | awk '{print $2}')
    fi
    if [[ -z "$port" && -f "$CONFIG_FILE" ]]; then
        port=$(grep -E "^[[:space:]]*Port[[:space:]]+" "$CONFIG_FILE" 2>/dev/null | head -n 1 | awk '{print $2}')
    fi
    if [[ -z "$port" ]]; then echo "22 (Default)"; else echo "$port"; fi
}

# Local & Public IP
get_local_ip() {
    local ip
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    echo "${ip:-127.0.0.1}"
}

get_active_sessions() {
    local count
    count=$(who 2>/dev/null | grep -E "pts|tty" | wc -l | xargs)
    echo "${count:-0}"
}

# Backup configuration before any change
create_backup() {
    mkdir -p "$BACKUP_DIR" 2>/dev/null
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    cp "$CONFIG_FILE" "$BACKUP_FILE" 2>/dev/null
    cp "$CONFIG_FILE" "$BACKUP_DIR/sshd_config.$timestamp" 2>/dev/null
}

# --- HEADER UI ---
draw_header() {
    clear 2>/dev/null || true
    local hostname
    hostname=$(hostname 2>/dev/null || echo "localhost")
    local local_ip
    local_ip=$(get_local_ip)
    local active_sessions
    active_sessions=$(get_active_sessions)
    
    local srv_stat="${RED}STOPPED${NC}"
    if is_ssh_running; then
        srv_stat="${GREEN}ONLINE (ACTIVE)${NC}"
    fi
    
    local root_login
    root_login=$(get_conf_status "PermitRootLogin" "prohibit-password")
    local pass_auth
    pass_auth=$(get_conf_status "PasswordAuthentication" "no")
    local pubkey_auth
    pubkey_auth=$(get_conf_status "PubkeyAuthentication" "yes")
    local pam_stat
    pam_stat=$(get_conf_status "UsePAM" "yes")
    local current_port
    current_port=$(get_ssh_port)

    # Firewall status
    local fw_stat="${GRAY}Inactive${NC}"
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        fw_stat="${GREEN}UFW Active${NC}"
    fi

    echo -e "${PURPLE} ╭──────────────────────────────────────────────────────────────╮${NC}"
    echo -e "${PURPLE} │${NC}   ${YELLOW}⚡${NC}  ${WHITE}${BOLD}SSH COMMANDER v4.0${NC}  ${PURPLE}◈${NC}  ${CYAN}[SERVER ACCESS CONTROL SYSTEM]${NC} ${PURPLE}│${NC}"
    echo -e "${PURPLE} ╰──────────────────────────────────────────────────────────────╯${NC}"
    echo -e "${CYAN}  ┌─ SYSTEM TELEMETRY ─────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}  │${NC}  Host    : ${WHITE}$hostname${NC}           ${GRAY}│${NC}  Status   : $srv_stat"
    echo -e "${CYAN}  │${NC}  IP      : ${CYAN}$local_ip${NC}           ${GRAY}│${NC}  SSH Port : ${WHITE}$current_port${NC}"
    echo -e "${CYAN}  │${NC}  Clients : ${YELLOW}$active_sessions Active${NC}          ${GRAY}│${NC}  Firewall : $fw_stat"
    echo -e "${CYAN}  ├─ SECURITY POSTURE ─────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}  │${NC}  Root Login : $root_login         ${GRAY}│${NC}  Pubkey Auth : $pubkey_auth"
    echo -e "${CYAN}  │${NC}  Pass Auth  : $pass_auth         ${GRAY}│${NC}  UsePAM      : $pam_stat"
    echo -e "${CYAN}  └────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

# --- OPERATION 1: UNLOCK ACCESS ---
enable_access() {
    [[ "$CLI_MODE" != "true" ]] && draw_header
    echo -e "${WHITE}${BOLD}  UNLOCK SERVER ACCESS (ROOT + PASSWORD AUTH)${NC}"
    echo -e "${GRAY}  ────────────────────────────────────────────────────────────${NC}"
    msg_info "Backing up current configuration"
    create_backup

    msg_info "Configuring sshd_config for root login & password auth"
    
    # 1. Clean main sshd_config
    sed -i '/^[#[:space:]]*PermitRootLogin/d' "$CONFIG_FILE"
    sed -i '/^[#[:space:]]*PasswordAuthentication/d' "$CONFIG_FILE"
    sed -i '/^[#[:space:]]*KbdInteractiveAuthentication/d' "$CONFIG_FILE"
    sed -i '/^[#[:space:]]*ChallengeResponseAuthentication/d' "$CONFIG_FILE"
    
    echo "PermitRootLogin yes" >> "$CONFIG_FILE"
    echo "PasswordAuthentication yes" >> "$CONFIG_FILE"
    echo "KbdInteractiveAuthentication yes" >> "$CONFIG_FILE"
    echo "PubkeyAuthentication yes" >> "$CONFIG_FILE"
    echo "UsePAM yes" >> "$CONFIG_FILE"

    # 2. Update cloud-init / distro override files if present in sshd_config.d
    if [ -d "/etc/ssh/sshd_config.d" ]; then
        for f in /etc/ssh/sshd_config.d/*.conf; do
            if [ -f "$f" ]; then
                sed -i 's/^[#[:space:]]*PasswordAuthentication.*/PasswordAuthentication yes/g' "$f" 2>/dev/null
                sed -i 's/^[#[:space:]]*PermitRootLogin.*/PermitRootLogin yes/g' "$f" 2>/dev/null
            fi
        done
    fi
    
    msg_ok "Configuration updated (Root: YES, Password: YES)"

    msg_info "Reloading SSH daemon"
    restart_ssh
    if [ $? -eq 0 ]; then
        msg_ok "SSH service reloaded successfully."
    else
        msg_warn "SSH service restart reported an issue. Please verify status."
    fi

    echo ""
    echo -e "${YELLOW}  ${BOLD}IMPORTANT:${NC} Ensure a strong root password is set via Option [3]!"
    if [[ "$CLI_MODE" != "true" ]]; then
        echo ""
        read -p "  Press [Enter] to return..."
    fi
}

# --- OPERATION 2: SECURE LOCKDOWN ---
secure_lockdown() {
    [[ "$CLI_MODE" != "true" ]] && draw_header
    echo -e "${RED}${BOLD}  SECURE LOCKDOWN MODE (KEY-ONLY ACCESS)${NC}"
    echo -e "${GRAY}  This disables Root Password Login & restricts auth to SSH keys.${NC}"
    echo -e "${GRAY}  ────────────────────────────────────────────────────────────${NC}"
    
    # Warning if authorized_keys does not exist or is empty
    if [ ! -s "/root/.ssh/authorized_keys" ]; then
        echo -e "${YELLOW}  ⚠️  WARNING: /root/.ssh/authorized_keys is empty or missing!${NC}"
        echo -e "${YELLOW}  Disabling password auth now may completely lock you out!${NC}"
        echo ""
    fi

    if [[ -z "$confirm" ]]; then
        echo -ne "${PURPLE}  ➤ Confirm Lockdown? (y/N): ${NC}"
        read confirm
    fi
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        create_backup
        
        # Main config
        sed -i '/^[#[:space:]]*PermitRootLogin/d' "$CONFIG_FILE"
        sed -i '/^[#[:space:]]*PasswordAuthentication/d' "$CONFIG_FILE"
        sed -i '/^[#[:space:]]*KbdInteractiveAuthentication/d' "$CONFIG_FILE"
        
        echo "PermitRootLogin prohibit-password" >> "$CONFIG_FILE"
        echo "PasswordAuthentication no" >> "$CONFIG_FILE"
        echo "KbdInteractiveAuthentication no" >> "$CONFIG_FILE"
        echo "PubkeyAuthentication yes" >> "$CONFIG_FILE"
        echo "UsePAM yes" >> "$CONFIG_FILE"

        # Override files
        if [ -d "/etc/ssh/sshd_config.d" ]; then
            for f in /etc/ssh/sshd_config.d/*.conf; do
                if [ -f "$f" ]; then
                    sed -i 's/^[#[:space:]]*PasswordAuthentication.*/PasswordAuthentication no/g' "$f" 2>/dev/null
                    sed -i 's/^[#[:space:]]*PermitRootLogin.*/PermitRootLogin prohibit-password/g' "$f" 2>/dev/null
                fi
            done
        fi

        restart_ssh
        msg_ok "Server locked down. Only authorized SSH keys permitted."
    else
        msg_info "Operation cancelled."
    fi

    if [[ "$CLI_MODE" != "true" ]]; then
        echo ""
        read -p "  Press [Enter] to return..."
    fi
}

# --- OPERATION 3: ROOT PASSWORD MANAGEMENT ---
set_root_pass() {
    [[ "$CLI_MODE" != "true" ]] && draw_header
    echo -e "${WHITE}${BOLD}  ROOT PASSWORD MANAGEMENT${NC}"
    echo -e "${GRAY}  ────────────────────────────────────────────────────────────${NC}"

    # If password passed directly as parameter (CLI mode)
    if [[ -n "$1" ]]; then
        echo "root:$1" | chpasswd
        if [ $? -eq 0 ]; then
            msg_ok "Root password updated successfully."
            return 0
        else
            msg_err "Failed to update root password."
            return 1
        fi
    fi

    echo -e "  ${GREEN}[1]${NC} Quick Set Password ${GRAY}(Hidden Input)${NC}"
    echo -e "  ${CYAN}[2]${NC} Generate Strong Random Password ${GRAY}(Auto-assign)${NC}"
    echo -e "  ${BLUE}[3]${NC} Standard passwd Command ${GRAY}(Interactive System Flow)${NC}"
    echo -e "  ${GRAY}[0]${NC} Cancel"
    echo ""
    echo -ne "${PURPLE}  ➤ Choose option [0-3]: ${NC}"
    read p_choice

    case $p_choice in
        1)
            echo ""
            read -sp "  Enter new root password: " pass
            echo ""
            read -sp "  Confirm password: " confirm_pass
            echo ""
            
            if [[ "$pass" != "$confirm_pass" ]]; then
                msg_err "Passwords do not match!"
            elif [[ -z "$pass" ]]; then
                msg_err "Password cannot be empty!"
            else
                echo "root:$pass" | chpasswd
                if [ $? -eq 0 ]; then
                    msg_ok "Root password updated successfully."
                else
                    msg_err "Failed to update password."
                fi
            fi
            ;;
        2)
            local gen_pass
            gen_pass=$(tr -dc 'A-Za-z0-9!@#%^&*' </dev/urandom | head -c 16)
            echo "root:$gen_pass" | chpasswd
            if [ $? -eq 0 ]; then
                echo ""
                msg_ok "Generated and applied new Root Password:"
                echo -e "${GREEN}  ┌────────────────────────────────────────┐${NC}"
                echo -e "${GREEN}  │${NC}  ${WHITE}${BOLD}$gen_pass${NC}      ${GREEN}│${NC}"
                echo -e "${GREEN}  └────────────────────────────────────────┘${NC}"
                echo -e "${YELLOW}  Save this password in a secure password manager!${NC}"
            else
                msg_err "Failed to apply generated password."
            fi
            ;;
        3)
            echo ""
            passwd root
            [ $? -eq 0 ] && msg_ok "Password updated." || msg_err "Password change failed."
            ;;
        0)
            return
            ;;
        *)
            msg_err "Invalid selection."
            ;;
    esac

    if [[ "$CLI_MODE" != "true" ]]; then
        echo ""
        read -p "  Press [Enter] to return..."
    fi
}

# --- OPERATION 4: CHANGE SSH PORT ---
change_port() {
    [[ "$CLI_MODE" != "true" ]] && draw_header
    echo -e "${WHITE}${BOLD}  CHANGE SSH LISTENING PORT${NC}"
    echo -e "${GRAY}  ────────────────────────────────────────────────────────────${NC}"
    local cur_port
    cur_port=$(get_ssh_port)
    echo -e "  Current Port : ${CYAN}$cur_port${NC}"
    echo ""

    local new_port="${1:-}"
    if [[ -z "$new_port" ]]; then
        echo -ne "${PURPLE}  ➤ Enter New SSH Port (1-65535): ${NC}"
        read new_port
    fi

    # Validation
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        msg_err "Invalid port number. Must be between 1 and 65535."
        if [[ "$CLI_MODE" != "true" ]]; then
            read -p "  Press [Enter] to return..."
        fi
        return 1
    fi

    create_backup
    msg_info "Updating port configuration in $CONFIG_FILE"
    sed -i '/^[#[:space:]]*Port/d' "$CONFIG_FILE"
    echo "Port $new_port" >> "$CONFIG_FILE"

    # Firewall update if UFW is active
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        msg_info "Opening port $new_port in UFW firewall"
        ufw allow "${new_port}/tcp" >/dev/null 2>&1
    fi

    msg_info "Testing SSH configuration"
    restart_ssh
    if [ $? -eq 0 ]; then
        msg_ok "SSH Port successfully changed to ${WHITE}$new_port${NC}"
        echo -e "${YELLOW}  Remember to connect using: ssh -p $new_port root@$(get_local_ip)${NC}"
    else
        msg_err "Failed to reload SSH on new port. Reverting to backup."
        restore_backup_quiet
    fi

    if [[ "$CLI_MODE" != "true" ]]; then
        echo ""
        read -p "  Press [Enter] to return..."
    fi
}

# Helper: Append key to /root/.ssh/authorized_keys
install_authorized_key() {
    local key_str="$1"
    local source="${2:-manual}"

    if [[ -z "$key_str" ]]; then
        msg_err "SSH key is empty."
        return 1
    fi

    # Basic SSH key format validation
    if ! echo "$key_str" | grep -qE "^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|sk-ssh-ed25519|sk-ecdsa-sha2-nistp256)"; then
        msg_err "Invalid SSH key format. Must start with ssh-rsa, ssh-ed25519, or ecdsa-*"
        return 1
    fi

    mkdir -p /root/.ssh && chmod 700 /root/.ssh
    echo "$key_str" >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    msg_ok "Key successfully added from $source to /root/.ssh/authorized_keys"
    return 0
}

# Helper: Import from GitHub / URL
import_keys_from_url() {
    local target="$1"
    if [[ -z "$target" ]]; then
        msg_err "Target cannot be empty."
        return 1
    fi

    local url="$target"
    if ! echo "$target" | grep -qE "^https?://"; then
        url="https://github.com/${target}.keys"
        msg_info "Fetching public keys from GitHub for user: $target"
    else
        msg_info "Fetching public keys from: $url"
    fi

    local fetched_keys
    fetched_keys=$(curl -fsSL --connect-timeout 5 "$url" 2>/dev/null)

    if [[ -z "$fetched_keys" ]]; then
        msg_err "No public keys found or connection failed at: $url"
        return 1
    fi

    local count=0
    mkdir -p /root/.ssh && chmod 700 /root/.ssh
    while IFS= read -r line; do
        if echo "$line" | grep -qE "^(ssh-rsa|ssh-ed25519|ecdsa-sha2-)"; then
            echo "$line" >> /root/.ssh/authorized_keys
            ((count++))
        fi
    done <<< "$fetched_keys"
    chmod 600 /root/.ssh/authorized_keys

    if [ "$count" -gt 0 ]; then
        msg_ok "Imported $count key(s) into /root/.ssh/authorized_keys"
        return 0
    else
        msg_err "Downloaded content did not contain valid SSH public keys."
        return 1
    fi
}

# Helper: Display generated keypair with both PEM and PUB
display_keypair_result() {
    local key_path="$1"
    local key_label="$2"
    local key_filename
    key_filename=$(basename "$key_path")

    # Create .pem copy if doesn't exist
    if [ ! -f "${key_path}.pem" ]; then
        cp "$key_path" "${key_path}.pem" 2>/dev/null
        chmod 600 "${key_path}.pem" 2>/dev/null
    fi

    echo ""
    msg_ok "${key_label} Keypair generated successfully!"
    echo ""
    echo -e "${YELLOW}  ⚠️  STEP 1: COPY PRIVATE KEY (PEM FORMAT) TO YOUR CLIENT / PC${NC}"
    echo -e "${GREEN}  ╭─ PEM PRIVATE KEY (${key_filename}.pem) ───────────────────────╮${NC}"
    cat "$key_path"
    echo -e "${GREEN}  ╰────────────────────────────────────────────────────────────╯${NC}"
    echo -e "  ${GRAY}● Saved at: ${WHITE}${key_path}.pem${NC}"
    echo -e "  ${GRAY}● Client command: ${CYAN}ssh -i ${key_filename}.pem root@$(get_local_ip) -p $(get_ssh_port)${NC}"

    echo ""
    echo -e "${CYAN}  ╭─ PUB PUBLIC KEY (${key_filename}.pub) ────────────────────────╮${NC}"
    cat "${key_path}.pub"
    echo -e "${CYAN}  ╰────────────────────────────────────────────────────────────╯${NC}"

    echo ""
    echo -ne "${PURPLE}  ➤ Automatically add this PUB key to /root/.ssh/authorized_keys? (Y/n): ${NC}"
    read auth_local
    if [[ "$auth_local" =~ ^[Nn]$ ]]; then
        msg_info "Public key not added to authorized_keys."
    else
        cat "${key_path}.pub" >> /root/.ssh/authorized_keys
        chmod 600 /root/.ssh/authorized_keys
        msg_ok "Public key added to /root/.ssh/authorized_keys"
    fi
}

# --- KEY GENERATION ENGINE (ALL TYPES) ---

# Type 1: ED25519 (256-bit)
generate_key_ed25519() {
    mkdir -p /root/.ssh && chmod 700 /root/.ssh
    local key_path="/root/.ssh/id_ed25519"
    local comment="root@$(hostname)-ed25519-$(date +%Y%m%d)"

    if [ -f "$key_path" ]; then
        msg_warn "Key $key_path already exists."
        echo -ne "${PURPLE}  Overwrite existing ED25519 key? (y/N): ${NC}"
        read ow
        if ! [[ "$ow" =~ ^[Yy]$ ]]; then
            msg_info "Key generation cancelled."
            return 1
        fi
        rm -f "$key_path" "${key_path}.pub" "${key_path}.pem"
    fi

    msg_info "Generating Type 1: ED25519 (256-bit) keypair"
    ssh-keygen -t ed25519 -N "" -C "$comment" -f "$key_path" >/dev/null 2>&1
    chmod 600 "$key_path" && chmod 644 "${key_path}.pub"
    display_keypair_result "$key_path" "ED25519 (256-bit)"
    return 0
}

# Type 2: RSA 4096-bit (Classic PEM)
generate_key_rsa4096() {
    mkdir -p /root/.ssh && chmod 700 /root/.ssh
    local key_path="/root/.ssh/id_rsa"
    local comment="root@$(hostname)-rsa4096-$(date +%Y%m%d)"

    if [ -f "$key_path" ]; then
        msg_warn "Key $key_path already exists."
        echo -ne "${PURPLE}  Overwrite existing RSA 4096 key? (y/N): ${NC}"
        read ow
        if ! [[ "$ow" =~ ^[Yy]$ ]]; then
            msg_info "Key generation cancelled."
            return 1
        fi
        rm -f "$key_path" "${key_path}.pub" "${key_path}.pem"
    fi

    msg_info "Generating Type 2: RSA 4096-bit Classic PEM keypair"
    ssh-keygen -m PEM -t rsa -b 4096 -N "" -C "$comment" -f "$key_path" >/dev/null 2>&1
    chmod 600 "$key_path" && chmod 644 "${key_path}.pub"
    display_keypair_result "$key_path" "RSA (4096-bit PEM)"
    return 0
}

# Type 3: RSA 2048-bit (Cloud / AWS Standard PEM)
generate_key_rsa2048() {
    mkdir -p /root/.ssh && chmod 700 /root/.ssh
    local key_path="/root/.ssh/id_rsa_2048"
    local comment="root@$(hostname)-rsa2048-$(date +%Y%m%d)"

    if [ -f "$key_path" ]; then
        msg_warn "Key $key_path already exists."
        echo -ne "${PURPLE}  Overwrite existing RSA 2048 key? (y/N): ${NC}"
        read ow
        if ! [[ "$ow" =~ ^[Yy]$ ]]; then
            msg_info "Key generation cancelled."
            return 1
        fi
        rm -f "$key_path" "${key_path}.pub" "${key_path}.pem"
    fi

    msg_info "Generating Type 3: RSA 2048-bit Cloud PEM keypair"
    ssh-keygen -m PEM -t rsa -b 2048 -N "" -C "$comment" -f "$key_path" >/dev/null 2>&1
    chmod 600 "$key_path" && chmod 644 "${key_path}.pub"
    display_keypair_result "$key_path" "RSA (2048-bit Cloud PEM)"
    return 0
}

# Type 4: ECDSA (521-bit NIST Curve)
generate_key_ecdsa() {
    mkdir -p /root/.ssh && chmod 700 /root/.ssh
    local key_path="/root/.ssh/id_ecdsa"
    local comment="root@$(hostname)-ecdsa521-$(date +%Y%m%d)"

    if [ -f "$key_path" ]; then
        msg_warn "Key $key_path already exists."
        echo -ne "${PURPLE}  Overwrite existing ECDSA key? (y/N): ${NC}"
        read ow
        if ! [[ "$ow" =~ ^[Yy]$ ]]; then
            msg_info "Key generation cancelled."
            return 1
        fi
        rm -f "$key_path" "${key_path}.pub" "${key_path}.pem"
    fi

    msg_info "Generating Type 4: ECDSA (521-bit NIST) keypair"
    ssh-keygen -t ecdsa -b 521 -N "" -C "$comment" -f "$key_path" >/dev/null 2>&1
    chmod 600 "$key_path" && chmod 644 "${key_path}.pub"
    display_keypair_result "$key_path" "ECDSA (521-bit NIST)"
    return 0
}

# Type 5: Convert existing private key to classic PEM format
convert_key_to_pem() {
    local available_keys=()
    for f in /root/.ssh/id_*; do
        if [[ -f "$f" && "$f" != *.pub && "$f" != *.pem ]]; then
            available_keys+=("$f")
        fi
    done

    if [ ${#available_keys[@]} -eq 0 ]; then
        msg_warn "No unconverted OpenSSH private keys found in /root/.ssh/"
        return 1
    fi

    local target_key="${available_keys[0]}"
    if [ ${#available_keys[@]} -gt 1 ]; then
        echo -e "${CYAN}  Select private key to convert to PEM format:${NC}"
        local idx=1
        for k in "${available_keys[@]}"; do
            echo -e "  ${GREEN}[$idx]${NC} $(basename "$k")"
            ((idx++))
        done
        echo -ne "${PURPLE}  ➤ Select key [1-${#available_keys[@]}]: ${NC}"
        read sel
        if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le ${#available_keys[@]} ]; then
            target_key="${available_keys[$((sel-1))]}"
        fi
    fi

    msg_info "Converting $(basename "$target_key") to Classic PEM format"
    chmod 600 "$target_key"
    ssh-keygen -p -P "" -N "" -m PEM -f "$target_key" >/dev/null 2>&1
    cp "$target_key" "${target_key}.pem" 2>/dev/null && chmod 600 "${target_key}.pem"
    msg_ok "Key converted to PEM format and saved as $(basename "$target_key").pem"
}

# --- SEPARATE DEDICATED KEY GENERATION MENU ---
key_gen_menu() {
    while true; do
        [[ "$CLI_MODE" != "true" ]] && draw_header
        echo -e "${PURPLE} ╭── KEY GENERATION STUDIO (ALL KEY TYPES) ─────────────────────╮${NC}"
        echo -e "${PURPLE} │${NC}                                                              ${PURPLE}│${NC}"
        echo -e "${PURPLE} │${NC}  ${YELLOW}[1]${NC} ${WHITE}${BOLD}⚡ Type 1: ED25519 Keypair${NC}    ${GRAY}(256-bit Fast & Modern)     ${NC}  ${PURPLE}│${NC}"
        echo -e "${PURPLE} │${NC}  ${BLUE}[2]${NC} ${WHITE}${BOLD}🗝️  Type 2: RSA 4096 PEM Key${NC}  ${GRAY}(Maximum Security Classic)  ${NC}  ${PURPLE}│${NC}"
        echo -e "${PURPLE} │${NC}  ${CYAN}[3]${NC} ${WHITE}${BOLD}🔑 Type 3: RSA 2048 PEM Key${NC}  ${GRAY}(AWS/Cloud Compatible PEM)  ${NC}  ${PURPLE}│${NC}"
        echo -e "${PURPLE} │${NC}  ${GREEN}[4]${NC} ${WHITE}${BOLD}🧬 Type 4: ECDSA 521-bit Key${NC} ${GRAY}(NIST P-521 Elliptic Curve) ${NC}  ${PURPLE}│${NC}"
        echo -e "${PURPLE} │${NC}  ${PURPLE}[5]${NC} ${WHITE}${BOLD}🔄 Convert Existing Key to PEM${NC}  ${GRAY}(Export .pem format)   ${NC}  ${PURPLE}│${NC}"
        echo -e "${PURPLE} │${NC}                                                              ${PURPLE}│${NC}"
        echo -e "${PURPLE} │${NC}  ${GRAY}[0] ↩  Return to Key Menu${NC}                                    ${PURPLE}│${NC}"
        echo -e "${PURPLE} ╰──────────────────────────────────────────────────────────────╯${NC}"
        echo ""
        echo -ne "${PURPLE}  ➤ Choose option [0-5]: ${NC}"
        read g_choice

        case $g_choice in
            1)
                generate_key_ed25519
                echo ""
                read -p "  Press [Enter] to continue..."
                ;;
            2)
                generate_key_rsa4096
                echo ""
                read -p "  Press [Enter] to continue..."
                ;;
            3)
                generate_key_rsa2048
                echo ""
                read -p "  Press [Enter] to continue..."
                ;;
            4)
                generate_key_ecdsa
                echo ""
                read -p "  Press [Enter] to continue..."
                ;;
            5)
                convert_key_to_pem
                echo ""
                read -p "  Press [Enter] to continue..."
                ;;
            0)
                break
                ;;
            *)
                msg_err "Invalid selection."
                sleep 1
                ;;
        esac
    done
}

# --- VIEW & EXPORT PEM / PUB KEYS ---

# View & Export Private Key (PEM format)
view_pem_key() {
    [[ "$CLI_MODE" != "true" ]] && draw_header
    echo -e "${WHITE}${BOLD}  VIEW & EXPORT PRIVATE KEY (PEM FORMAT)${NC}"
    echo -e "${GRAY}  ────────────────────────────────────────────────────────────${NC}"
    
    local available_keys=()
    for f in /root/.ssh/id_* /root/.ssh/*.pem; do
        if [[ -f "$f" && "$f" != *.pub ]]; then
            available_keys+=("$f")
        fi
    done

    if [ ${#available_keys[@]} -eq 0 ]; then
        msg_warn "No private PEM keys found in /root/.ssh/"
        echo -e "${YELLOW}  Use Option [1] Key Generation Menu to create a keypair first.${NC}"
        if [[ "$CLI_MODE" != "true" ]]; then
            echo ""
            read -p "  Press [Enter] to return..."
        fi
        return 1
    fi

    local key_file="${available_keys[0]}"
    if [ ${#available_keys[@]} -gt 1 ]; then
        echo -e "${CYAN}  Available Private Keys in /root/.ssh/:${NC}"
        local idx=1
        for k in "${available_keys[@]}"; do
            echo -e "  ${GREEN}[$idx]${NC} $(basename "$k")"
            ((idx++))
        done
        echo -ne "${PURPLE}  ➤ Select key [1-${#available_keys[@]}]: ${NC}"
        read sel
        if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le ${#available_keys[@]} ]; then
            key_file="${available_keys[$((sel-1))]}"
        fi
    fi

    echo ""
    echo -e "${YELLOW}  ⚠️  PRIVATE KEY (PEM FORMAT) - KEEP CONFIDENTIAL!${NC}"
    echo -e "${GREEN}  ╭─ PEM PRIVATE KEY ($(basename "$key_file")) ──────────────────────────╮${NC}"
    cat "$key_file"
    echo -e "${GREEN}  ╰────────────────────────────────────────────────────────────╯${NC}"
    echo ""
    echo -e "${CYAN}  Copy the text above and save it as '${key_file##*/}.pem' on your client.${NC}"
    echo -e "${WHITE}  SSH Command: ${CYAN}ssh -i ${key_file##*/}.pem root@$(get_local_ip) -p $(get_ssh_port)${NC}"
    
    if [[ "$CLI_MODE" != "true" ]]; then
        echo ""
        read -p "  Press [Enter] to return..."
    fi
}

# View & Export Public Key (PUB format)
view_pub_key() {
    [[ "$CLI_MODE" != "true" ]] && draw_header
    echo -e "${WHITE}${BOLD}  VIEW & EXPORT PUBLIC KEY (PUB FORMAT)${NC}"
    echo -e "${GRAY}  ────────────────────────────────────────────────────────────${NC}"

    local available_pubs=()
    for f in /root/.ssh/*.pub /root/.ssh/authorized_keys; do
        if [ -s "$f" ]; then
            available_pubs+=("$f")
        fi
    done

    if [ ${#available_pubs[@]} -eq 0 ]; then
        msg_warn "No public keys found in /root/.ssh/"
        if [[ "$CLI_MODE" != "true" ]]; then
            echo ""
            read -p "  Press [Enter] to return..."
        fi
        return 1
    fi

    local pub_file="${available_pubs[0]}"
    if [ ${#available_pubs[@]} -gt 1 ]; then
        echo -e "${CYAN}  Available Public Keys in /root/.ssh/:${NC}"
        local idx=1
        for k in "${available_pubs[@]}"; do
            echo -e "  ${GREEN}[$idx]${NC} $(basename "$k")"
            ((idx++))
        done
        echo -ne "${PURPLE}  ➤ Select public key [1-${#available_pubs[@]}]: ${NC}"
        read sel
        if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le ${#available_pubs[@]} ]; then
            pub_file="${available_pubs[$((sel-1))]}"
        fi
    fi

    echo ""
    echo -e "${CYAN}  ╭─ PUBLIC KEY ($(basename "$pub_file")) ──────────────────────────────╮${NC}"
    cat "$pub_file"
    echo -e "${CYAN}  ╰────────────────────────────────────────────────────────────╯${NC}"
    echo ""
    echo -e "${GRAY}  Fingerprint: $(ssh-keygen -lf "$pub_file" 2>/dev/null | head -n 1)${NC}"

    if [[ "$CLI_MODE" != "true" ]]; then
        echo ""
        read -p "  Press [Enter] to return..."
    fi
}

# --- PAM (PLUGGABLE AUTHENTICATION MODULES) CONTROLLER ---
toggle_pam() {
    [[ "$CLI_MODE" != "true" ]] && draw_header
    echo -e "${WHITE}${BOLD}  PAM (PLUGGABLE AUTHENTICATION MODULES) CONFIGURATION${NC}"
    echo -e "${GRAY}  ────────────────────────────────────────────────────────────${NC}"
    local cur_pam
    cur_pam=$(get_conf_status "UsePAM" "yes")
    echo -e "  Current UsePAM Status: $cur_pam"
    echo ""

    local target_state="${1:-}"
    if [[ -z "$target_state" ]]; then
        echo -e "  ${GREEN}[1]${NC} Enable UsePAM (yes)"
        echo -e "  ${RED}[2]${NC} Disable UsePAM (no)"
        echo -e "  ${GRAY}[0]${NC} Cancel"
        echo ""
        echo -ne "${PURPLE}  ➤ Choose option [0-2]: ${NC}"
        read p_opt
        case $p_opt in
            1) target_state="yes" ;;
            2) target_state="no" ;;
            *) return ;;
        esac
    fi

    if [[ "$target_state" == "on" || "$target_state" == "1" ]]; then target_state="yes"; fi
    if [[ "$target_state" == "off" || "$target_state" == "0" ]]; then target_state="no"; fi

    create_backup
    msg_info "Updating UsePAM to $target_state"
    sed -i '/^[#[:space:]]*UsePAM/d' "$CONFIG_FILE"
    echo "UsePAM $target_state" >> "$CONFIG_FILE"

    if [ -d "/etc/ssh/sshd_config.d" ]; then
        for f in /etc/ssh/sshd_config.d/*.conf; do
            if [ -f "$f" ]; then
                sed -i "s/^[#[:space:]]*UsePAM.*/UsePAM $target_state/g" "$f" 2>/dev/null
            fi
        done
    fi

    restart_ssh
    msg_ok "UsePAM set to $target_state and SSH daemon reloaded."

    if [[ "$CLI_MODE" != "true" ]]; then
        echo ""
        read -p "  Press [Enter] to return..."
    fi
}

# --- OPERATION 5: SSH KEY MANAGEMENT ---
ssh_key_menu() {
    while true; do
        [[ "$CLI_MODE" != "true" ]] && draw_header
        echo -e "${PURPLE} ╭── SSH KEY MANAGEMENT MATRIX ─────────────────────────────────╮${NC}"
        echo -e "${PURPLE} │${NC}                                                              ${PURPLE}│${NC}"
        echo -e "${PURPLE} │${NC}  ${WHITE}${BOLD}── KEY GENERATION STUDIO ───────────────────────────────────${NC}  ${PURPLE}│${NC}"
        echo -e "${PURPLE} │${NC}  ${YELLOW}[1]${NC} ${WHITE}${BOLD}🔑 Key Generation Menu${NC}      ${GRAY}(ED25519, RSA-PEM, ECDSA)  ${NC}  ${PURPLE}│${NC}"
        echo -e "${PURPLE} │${NC}                                                              ${PURPLE}│${NC}"
        echo -e "${PURPLE} │${NC}  ${WHITE}${BOLD}── VIEW & EXPORT KEYS (PEM & PUB) ──────────────────────────${NC}  ${PURPLE}│${NC}"
        echo -e "${PURPLE} │${NC}  ${GREEN}[2]${NC} ${WHITE}${BOLD}📄 View PEM Private Key${NC}     ${GRAY}(Export .pem for SSH Client)${NC}  ${PURPLE}│${NC}"
        echo -e "${PURPLE} │${NC}  ${CYAN}[3]${NC} ${WHITE}${BOLD}🌐 View PUB Public Key${NC}      ${GRAY}(Export .pub for Server)   ${NC}  ${PURPLE}│${NC}"
        echo -e "${PURPLE} │${NC}                                                              ${PURPLE}│${NC}"
        echo -e "${PURPLE} │${NC}  ${WHITE}${BOLD}── ADD & IMPORT PUBLIC KEYS ────────────────────────────────${NC}  ${PURPLE}│${NC}"
        echo -e "${PURPLE} │${NC}  ${BLUE}[4]${NC} ${WHITE}${BOLD}➕ Manual Paste Public Key${NC}  ${GRAY}(Add to authorized_keys)   ${NC}  ${PURPLE}│${NC}"
        echo -e "${PURPLE} │${NC}  ${PURPLE}[5]${NC} ${WHITE}${BOLD}📥 Import from GitHub / URL${NC} ${GRAY}(github.com/<user>.keys)   ${NC}  ${PURPLE}│${NC}"
        echo -e "${PURPLE} │${NC}                                                              ${PURPLE}│${NC}"
        echo -e "${PURPLE} │${NC}  ${WHITE}${BOLD}── MANAGE AUTHORIZED KEYS ──────────────────────────────────${NC}  ${PURPLE}│${NC}"
        echo -e "${PURPLE} │${NC}  ${WHITE}[6]${NC} ${WHITE}${BOLD}📋 List Authorized Keys${NC}     ${GRAY}(View fingerprints)        ${NC}  ${PURPLE}│${NC}"
        echo -e "${PURPLE} │${NC}  ${RED}[7]${NC} ${WHITE}${BOLD}🗑️  Clear All Keys${NC}          ${GRAY}(Revoke key access)        ${NC}  ${PURPLE}│${NC}"
        echo -e "${PURPLE} │${NC}                                                              ${PURPLE}│${NC}"
        echo -e "${PURPLE} │${NC}  ${GRAY}[0] ↩  Return to Main Menu${NC}                                    ${PURPLE}│${NC}"
        echo -e "${PURPLE} ╰──────────────────────────────────────────────────────────────╯${NC}"
        echo ""
        echo -ne "${PURPLE}  ➤ Choose option [0-7]: ${NC}"
        read k_choice

        case $k_choice in
            1) key_gen_menu ;;
            2) view_pem_key ;;
            3) view_pub_key ;;
            4)
                echo ""
                echo -e "${YELLOW}  Paste your SSH Public Key (e.g., ssh-ed25519 AAAAC3... user@host):${NC}"
                echo -ne "${PURPLE}  ➤ ${NC}"
                read new_key
                install_authorized_key "$new_key" "manual input"
                sleep 2
                ;;
            5)
                echo ""
                echo -e "${CYAN}  Enter GitHub username (e.g. 'nobita') or full keys URL:${NC}"
                echo -ne "${PURPLE}  ➤ ${NC}"
                read target_user
                import_keys_from_url "$target_user"
                sleep 2
                ;;
            6)
                echo ""
                if [ -s "/root/.ssh/authorized_keys" ]; then
                    echo -e "${CYAN}  AUTHORIZED PUBLIC KEYS (/root/.ssh/authorized_keys):${NC}"
                    echo -e "${GRAY}  ────────────────────────────────────────────────────────────${NC}"
                    cat -n /root/.ssh/authorized_keys
                    echo ""
                    echo -e "${CYAN}  KEY FINGERPRINTS:${NC}"
                    ssh-keygen -lf /root/.ssh/authorized_keys 2>/dev/null
                else
                    msg_warn "No authorized keys found in /root/.ssh/authorized_keys"
                fi
                echo ""
                read -p "  Press [Enter] to continue..."
                ;;
            7)
                echo ""
                echo -ne "${RED}  Are you sure you want to remove ALL authorized keys? (y/N): ${NC}"
                read c_clear
                if [[ "$c_clear" =~ ^[Yy]$ ]]; then
                    rm -f /root/.ssh/authorized_keys
                    msg_ok "Authorized keys file removed."
                else
                    msg_info "Operation cancelled."
                fi
                sleep 2
                ;;
            0)
                break
                ;;
            *)
                msg_err "Invalid selection."
                sleep 1
                ;;
        esac
    done
}

# --- OPERATION 6: SERVICE CONTROLS ---
service_menu() {
    while true; do
        [[ "$CLI_MODE" != "true" ]] && draw_header
        local srv
        srv=$(get_ssh_service_name)
        echo -e "${WHITE}${BOLD}  SSH SERVICE CONTROLLER (Daemon: $srv)${NC}"
        echo -e "${GRAY}  ────────────────────────────────────────────────────────────${NC}"
        echo -e "  ${CYAN}[1]${NC} 🔄 Restart SSH Daemon"
        echo -e "  ${GREEN}[2]${NC} ▶  Start SSH Daemon"
        echo -e "  ${RED}[3]${NC} ⏹  Stop SSH Daemon"
        echo -e "  ${YELLOW}[4]${NC} 🧪 Test Configuration Integrity (sshd -t)"
        echo -e "  ${PURPLE}[5]${NC} ⚙️  Toggle UsePAM (yes/no)"
        echo -e "  ${WHITE}[0]${NC} ↩  Return to Main Menu"
        echo ""
        echo -ne "${PURPLE}  ➤ Choose option [0-5]: ${NC}"
        read s_choice

        case $s_choice in
            1)
                msg_info "Restarting SSH"
                restart_ssh && msg_ok "Service restarted" || msg_err "Restart failed"
                sleep 1.5
                ;;
            2)
                msg_info "Starting SSH"
                if has_systemd; then
                    sudo /bin/systemctl start "$srv" 2>/dev/null
                elif [ -x "/etc/init.d/$srv" ]; then
                    sudo "/etc/init.d/$srv" start 2>/dev/null
                fi
                is_ssh_running && msg_ok "Service running" || msg_err "Start failed"
                sleep 1.5
                ;;
            3)
                msg_info "Stopping SSH"
                if has_systemd; then
                    sudo /bin/systemctl stop "$srv" 2>/dev/null
                elif [ -x "/etc/init.d/$srv" ]; then
                    sudo "/etc/init.d/$srv" stop 2>/dev/null
                fi
                msg_ok "Service stopped"
                sleep 1.5
                ;;
            4)
                echo ""
                msg_info "Running: sshd -t"
                if sshd -t; then
                    echo ""
                    msg_ok "Configuration syntax is VALID and clean."
                else
                    echo ""
                    msg_err "Configuration syntax error detected above."
                fi
                echo ""
                read -p "  Press [Enter] to continue..."
                ;;
            5)
                toggle_pam
                ;;
            0)
                break
                ;;
            *)
                msg_err "Invalid selection."
                sleep 1
                ;;
        esac
    done
}

# --- OPERATION 7: ACTIVE SESSIONS ---
view_sessions() {
    [[ "$CLI_MODE" != "true" ]] && draw_header
    echo -e "${WHITE}${BOLD}  ACTIVE SSH SESSIONS & CLIENT CONNECTIONS${NC}"
    echo -e "${GRAY}  ────────────────────────────────────────────────────────────${NC}"
    echo ""
    
    echo -e "${CYAN}  LOGGED-IN USERS (who):${NC}"
    who 2>/dev/null || echo "  No active sessions found."
    echo ""

    echo -e "${CYAN}  ESTABLISHED SSH SOCKETS (Port 22/custom):${NC}"
    if command -v ss &>/dev/null; then
        ss -tnp 2>/dev/null | grep sshd || echo "  No active sshd socket connections."
    elif command -v netstat &>/dev/null; then
        netstat -tnp 2>/dev/null | grep sshd || echo "  No active sshd socket connections."
    fi

    echo ""
    if [[ "$CLI_MODE" != "true" ]]; then
        read -p "  Press [Enter] to return..."
    fi
}

# --- OPERATION 8: BACKUP & RESTORE ---
restore_backup_quiet() {
    if [ -f "$BACKUP_FILE" ]; then
        cp "$BACKUP_FILE" "$CONFIG_FILE"
        restart_ssh
    fi
}

restore_backup() {
    [[ "$CLI_MODE" != "true" ]] && draw_header
    echo -e "${WHITE}${BOLD}  RESTORE CONFIGURATION SNAPSHOT${NC}"
    echo -e "${GRAY}  ────────────────────────────────────────────────────────────${NC}"
    
    if [ -f "$BACKUP_FILE" ]; then
        msg_info "Restoring configuration from $BACKUP_FILE"
        cp "$BACKUP_FILE" "$CONFIG_FILE"
        restart_ssh
        msg_ok "Configuration restored and SSH reloaded."
    else
        msg_err "No backup file found at $BACKUP_FILE."
    fi

    if [[ "$CLI_MODE" != "true" ]]; then
        echo ""
        read -p "  Press [Enter] to return..."
    fi
}

# --- CLI READ-ONLY DISPATCH ---
if [[ "$1" == "help" || "$1" == "--help" || "$1" == "-h" ]]; then
    echo "SSH Commander v4.0 (Server Access & Security)"
    echo "Usage: $0 [COMMAND] [ARGS]"
    echo ""
    echo "Commands:"
    echo "  unlock              Enable root login & password authentication"
    echo "  lock [-y]           Lock down server to key-only authentication"
    echo "  pass [PASSWORD]     Set root password directly"
    echo "  port [PORT]         Change SSH listening port"
    echo "  pem                 View & export private key (PEM format)"
    echo "  pub                 View & export public key (PUB format)"
    echo "  pam [yes|no]        Configure UsePAM authentication"
    echo "  key gen [type]      Generate key (ed25519, rsa4096, rsa2048, ecdsa)"
    echo "  key add \"<KEY>\"     Add public key to authorized_keys"
    echo "  key gh <USER>       Import public keys from GitHub"
    echo "  key list            List installed authorized keys"
    echo "  restart             Restart SSH daemon safely"
    echo "  test                Validate SSH configuration (sshd -t)"
    echo "  sessions            Display active connected SSH sessions"
    echo "  status              Display security telemetry dashboard"
    echo "  restore             Restore previous sshd_config snapshot"
    exit 0
fi

if [[ "$1" == "status" ]]; then
    draw_header
    exit 0
fi

# --- ROOT PRIVILEGES CHECK ---
if [ "$EUID" -ne 0 ]; then
    if command -v sudo &>/dev/null; then
        exec sudo bash "$0" "$@"
    else
        echo -e "${RED}Error: This script requires root privileges.${NC}"
        echo "Please re-run as root: sudo $0"
        exit 1
    fi
fi

# --- CLI ARGUMENT HANDLER ---
if [[ -n "$1" ]]; then
    CLI_MODE=true
    case "$1" in
        unlock|enable|open)
            enable_access
            ;;
        lock|lockdown|secure)
            [[ "$2" == "-y" || "$2" == "--yes" ]] && confirm="y"
            secure_lockdown
            ;;
        pass|password)
            set_root_pass "$2"
            ;;
        port)
            change_port "$2"
            ;;
        pem|private-key)
            view_pem_key
            ;;
        pub|public-key)
            view_pub_key
            ;;
        pam)
            toggle_pam "$2"
            ;;
        key)
            case "$2" in
                pem)
                    view_pem_key
                    ;;
                pub)
                    view_pub_key
                    ;;
                add)
                    install_authorized_key "$3" "CLI"
                    ;;
                gh|github|import)
                    import_keys_from_url "$3"
                    ;;
                gen)
                    case "$3" in
                        rsa|rsa4096|4096)
                            generate_key_rsa4096
                            ;;
                        rsa2048|2048)
                            generate_key_rsa2048
                            ;;
                        ecdsa|521)
                            generate_key_ecdsa
                            ;;
                        *)
                            generate_key_ed25519
                            ;;
                    esac
                    ;;
                menu)
                    key_gen_menu
                    ;;
                list)
                    if [ -s "/root/.ssh/authorized_keys" ]; then
                        cat -n /root/.ssh/authorized_keys
                        ssh-keygen -lf /root/.ssh/authorized_keys 2>/dev/null
                    else
                        echo "No authorized keys found."
                    fi
                    ;;
                *)
                    ssh_key_menu
                    ;;
            esac
            ;;
        restart)
            restart_ssh && msg_ok "SSH restarted" || msg_err "Restart failed"
            ;;
        test)
            sshd -t
            ;;
        sessions|who)
            view_sessions
            ;;
        restore)
            restore_backup
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
    draw_header
    
    echo -e "${PURPLE} ╭── ACCESS & SECURITY MATRIX ──────────────────────────────────╮${NC}"
    echo -e "${PURPLE} │${NC}                                                              ${PURPLE}│${NC}"
    echo -e "${PURPLE} │${NC}  ${GREEN}[1]${NC} ${WHITE}${BOLD}🔓 Unlock Server Access${NC}     ${GRAY}(Root: YES  | Pass: YES)${NC}      ${PURPLE}│${NC}"
    echo -e "${PURPLE} │${NC}  ${RED}[2]${NC} ${WHITE}${BOLD}🔒 Secure Key Lockdown${NC}      ${GRAY}(Root: NO   | Pass: NO) ${NC}      ${PURPLE}│${NC}"
    echo -e "${PURPLE} │${NC}  ${YELLOW}[3]${NC} ${WHITE}${BOLD}🔑 Set Root Password${NC}        ${GRAY}(Quick / Random / Manual)${NC}     ${PURPLE}│${NC}"
    echo -e "${PURPLE} │${NC}  ${CYAN}[4]${NC} ${WHITE}${BOLD}🌐 Change SSH Port${NC}          ${GRAY}(Switch from default 22)${NC}      ${PURPLE}│${NC}"
    echo -e "${PURPLE} │${NC}  ${PURPLE}[5]${NC} ${WHITE}${BOLD}🛡️  SSH Key Manager${NC}          ${GRAY}(All Types | PEM & PUB) ${NC}      ${PURPLE}│${NC}"
    echo -e "${PURPLE} │${NC}  ${BLUE}[6]${NC} ${WHITE}${BOLD}⚡ Service & PAM Control${NC}   ${GRAY}(Restart / Test / UsePAM)${NC}     ${PURPLE}│${NC}"
    echo -e "${PURPLE} │${NC}  ${WHITE}[7]${NC} ${WHITE}${BOLD}📋 View Active Sessions${NC}     ${GRAY}(Connected Clients & IPs)${NC}     ${PURPLE}│${NC}"
    echo -e "${PURPLE} │${NC}  ${GRAY}[8]${NC} ${WHITE}${BOLD}💾 Backup & Restore${NC}         ${GRAY}(Rollback Configuration)${NC}      ${PURPLE}│${NC}"
    echo -e "${PURPLE} │${NC}                                                              ${PURPLE}│${NC}"
    echo -e "${PURPLE} │${NC}  ${GRAY}[0] 🚪 Exit Commander${NC}                                        ${PURPLE}│${NC}"
    echo -e "${PURPLE} ╰──────────────────────────────────────────────────────────────╯${NC}"
    echo ""
    echo -e "${PURPLE}  ╭─(${WHITE}root@ssh-commander${PURPLE})─[${CYAN}v4.0-access${PURPLE}]${NC}"
    echo -ne "${PURPLE}  ╰─➤ ${WHITE}SELECT [0-8]: ${NC}"
    read option

    case $option in
        1) enable_access ;;
        2) secure_lockdown ;;
        3) set_root_pass ;;
        4) change_port ;;
        5) ssh_key_menu ;;
        6) service_menu ;;
        7) view_sessions ;;
        8) restore_backup ;;
        0) clear 2>/dev/null || true; exit 0 ;;
        *) msg_err "Invalid Option"; sleep 1 ;;
    esac
done
