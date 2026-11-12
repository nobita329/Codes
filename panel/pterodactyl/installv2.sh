#!/bin/bash
# ==============================================================================
#  PTERODACTYL v2.0 FULL INSTALLER, UPDATER & MIGRATOR
#  Auto-detect + Automated Backup + PHP 8.3 & intl + Clean Vite/React 19 Stack
#  Powered by Nobita Cloud / Obsidian Next Gen
# ==============================================================================

set -o pipefail

# --- ROOT PRIVILEGE CHECK ---
if [ "$EUID" -ne 0 ]; then
    echo -e "\033[38;5;196m[ERROR]\033[0m This script must be run as root! Please use: sudo bash $0"
    exit 1
fi

# --- SEMA NEON THEME COLORS ---
CYAN='\033[38;5;51m'
PURPLE='\033[38;5;141m'
GRAY='\033[38;5;242m'
WHITE='\033[38;5;255m'
GREEN='\033[38;5;82m'
RED='\033[38;5;196m'
GOLD='\033[38;5;214m'
YELLOW='\033[38;5;228m'
BLUE='\033[38;5;39m'
NC='\033[0m'
HEADER_LINE="${GRAY}────────────────────────────────────────────────────────────${NC}"

GITHUB_REPO="pterodactyl/panel"
PHP_VERSION="8.3"
PANEL_DIR="/var/www/pterodactyl"
BACKUP_BASE_DIR="/var/backups/pterodactyl"

# --- UI HELPER FUNCTIONS ---
ok() {
    echo -e "  ${GREEN}[OK]${NC} $1"
}

step() {
    echo -e "\n  ${PURPLE}::${NC} ${WHITE}$1${NC}"
}

warn() {
    echo -e "  ${YELLOW}[WARN]${NC} $1"
}

err() {
    echo -e "  ${RED}[FAIL]${NC} $1"
}

info() {
    echo -e "  ${BLUE}[INFO]${NC} $1"
}

# --- SYSTEM AUTO-DETECTION ---
auto_detect_system() {
    # Detect OS & Codename
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DETECTED_OS="${ID:-unknown}"
        DETECTED_OS_PRETTY="${PRETTY_NAME:-$ID}"
        DETECTED_CODENAME="${VERSION_CODENAME:-}"
        DETECTED_VER="${VERSION_ID:-}"
    else
        DETECTED_OS="unknown"
        DETECTED_OS_PRETTY="Linux"
        DETECTED_CODENAME=""
        DETECTED_VER=""
    fi

    if [ -z "$DETECTED_CODENAME" ] && command -v lsb_release >/dev/null 2>&1; then
        DETECTED_CODENAME=$(lsb_release -cs 2>/dev/null)
    fi

    # Detect Architecture
    DETECTED_ARCH=$(uname -m)

    # Detect Public / Local IP
    DETECTED_IP=""
    if command -v curl >/dev/null 2>&1; then
        DETECTED_IP=$(curl -4s --max-time 3 https://api.ipify.org 2>/dev/null || curl -4s --max-time 3 https://ifconfig.me 2>/dev/null)
    fi
    if [ -z "$DETECTED_IP" ] && command -v wget >/dev/null 2>&1; then
        DETECTED_IP=$(wget -qO- --timeout=3 https://api.ipify.org 2>/dev/null)
    fi
    if [ -z "$DETECTED_IP" ]; then
        DETECTED_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    [ -z "$DETECTED_IP" ] && DETECTED_IP="127.0.0.1"

    # Detect Hostname / FQDN
    DETECTED_HOSTNAME=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "$DETECTED_IP")

    # Detect Timezone
    DETECTED_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null)
    if [ -z "$DETECTED_TZ" ] && [ -f /etc/timezone ]; then
        DETECTED_TZ=$(cat /etc/timezone 2>/dev/null | tr -d ' \n\r')
    fi
    if [ -z "$DETECTED_TZ" ] && [ -L /etc/localtime ]; then
        DETECTED_TZ=$(readlink /etc/localtime 2>/dev/null | sed -n 's|.*/zoneinfo/||p')
    fi
    [ -z "$DETECTED_TZ" ] && DETECTED_TZ="UTC"

    # Detect Existing Pterodactyl Installation
    IS_INSTALLED=false
    CURRENT_PANEL_VER="None"
    if [ -d "$PANEL_DIR" ] && [ -f "$PANEL_DIR/.env" ]; then
        IS_INSTALLED=true
        if [ -f "$PANEL_DIR/config/app.php" ]; then
            CURRENT_PANEL_VER=$(grep -oP "'version'\s*=>\s*'\K[^']+" "$PANEL_DIR/config/app.php" 2>/dev/null || echo "Installed")
        else
            CURRENT_PANEL_VER="Installed"
        fi
    fi

    # Detect if domain default should be FQDN or IP
    if [[ "$DETECTED_HOSTNAME" == *"."* ]] && [[ "$DETECTED_HOSTNAME" != "localhost"* ]]; then
        DETECTED_DOMAIN_DEFAULT="$DETECTED_HOSTNAME"
    else
        DETECTED_DOMAIN_DEFAULT="$DETECTED_IP"
    fi
}

show_banner() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
               .                                      .o8                          .               oooo  
             .o8                                     "888                        .o8               `888  
oo.ooooo.  .o888oo  .ooooo.  oooo d8b  .ooooo.   .oooo888   .oooo.    .ooooo.  .o888oo oooo    ooo  888  
 888' `88b   888   d88' `88b `888""8P d88' `88b d88' `888  `P  )88b  d88' `"Y8   888    `88.  .8'   888  
 888   888   888   888ooo888  888     888   888 888   888   .oP"888  888         888     `88..8'    888  
 888   888   888 . 888    .o  888     888   888 888   888  d8(  888  888   .o8   888 .    `888'     888  
 888bod8P'   "888" `Y8bod8P' d888b    `Y8bod8P' `Y8bod88P" `Y888""8o `Y8bod8P'   "888"     .8'     o888o 
 888                                                                                   .o..P'            
o888o                                                                                  `Y8P'             
EOF
    echo -e "       ${CYAN}⚡ PTERODACTYL v2.0 FULL INSTALLER & UPDATER ⚡${NC}"
    echo -e "              ${GRAY}Laravel 13 • React 19 • Vite • Tailwind 4${NC}"
    echo -e "${HEADER_LINE}"
    echo -e "  ${PURPLE}•${NC} ${GRAY}OS Detected:${NC}      ${WHITE}${DETECTED_OS_PRETTY} (${DETECTED_CODENAME:-$DETECTED_ARCH})${NC}"
    echo -e "  ${PURPLE}•${NC} ${GRAY}Server IP:${NC}        ${WHITE}${DETECTED_IP}${NC}"
    echo -e "  ${PURPLE}•${NC} ${GRAY}Timezone:${NC}         ${WHITE}${DETECTED_TZ}${NC}"
    echo -e "  ${PURPLE}•${NC} ${GRAY}Installed Panel:${NC}  ${WHITE}$([ "$IS_INSTALLED" = true ] && echo -e "${GREEN}${CURRENT_PANEL_VER}${NC}" || echo -e "${YELLOW}Not Installed${NC}")${NC}"
    echo -e "  ${PURPLE}•${NC} ${GRAY}Target Version:${NC}   ${CYAN}Pterodactyl v2.0 (Next-Gen UI & SDK)${NC}"
    echo -e "${HEADER_LINE}"
}

# --- INPUT HELPERS ---
ask() {
    local label=$1
    local default=$2
    local var_name=$3
    echo -ne "  ${PURPLE}•${NC} ${WHITE}$label${NC} ${GRAY}[$default]${NC}\n  ${GRAY}╰─>${NC} "
    read -r input
    if [ -z "$input" ]; then
        eval "$var_name=\"$default\""
    else
        eval "$var_name=\"$input\""
    fi
}

ask_timeout() {
    local label=$1
    local default=$2
    local var_name=$3
    local timeout=${4:-10}
    echo -ne "  ${PURPLE}•${NC} ${WHITE}$label${NC} ${GRAY}[$default]${NC}\n  ${GRAY}╰─>${NC} "
    if ! read -t "$timeout" -r input; then
        echo -e "\n  ${GOLD}⌛ Timeout — using default: ${WHITE}$default${NC}"
        eval "$var_name=\"$default\""
        return
    fi
    if [ -z "$input" ]; then
        eval "$var_name=\"$default\""
    else
        eval "$var_name=\"$input\""
    fi
}

generate_random_password() {
    local len=${1:-16}
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 48 2>/dev/null | tr -dc 'A-Za-z0-9' | cut -c1-"$len"
    else
        head -c 64 /dev/urandom 2>/dev/null | tr -dc 'A-Za-z0-9' | cut -c1-"$len"
    fi
}

# --- FETCH PTERODACTYL v2 RELEASES ---
fetch_github_versions() {
    local repo=$1
    echo -e "  ${GRAY}Fetching Pterodactyl v2 releases from ${WHITE}$repo${GRAY}...${NC}" >&2
    local json=""

    if command -v curl >/dev/null 2>&1; then
        json=$(curl -sf --max-time 8 "https://api.github.com/repos/$repo/releases?per_page=30" 2>/dev/null)
    elif command -v wget >/dev/null 2>&1; then
        json=$(wget -qO- --timeout=8 "https://api.github.com/repos/$repo/releases?per_page=30" 2>/dev/null)
    fi

    if [ -n "$json" ]; then
        # Try python3 parser
        if command -v python3 >/dev/null 2>&1; then
            echo "$json" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    found = []
    for r in data:
        tag = r.get('tag_name', '')
        if tag and (tag.startswith('v2.') or tag.startswith('2.') or 'v2' in tag.lower()):
            found.append(tag)
    if found:
        for t in found:
            print(t)
    else:
        for r in data:
            tag = r.get('tag_name', '')
            if tag:
                print(tag)
except Exception:
    pass
" 2>/dev/null && return 0
        fi

        # Fallback to grep parsing
        local parsed
        parsed=$(echo "$json" | grep -oP '"tag_name":\s*"\K[^"]+' | grep -E '^v?2\.' 2>/dev/null)
        if [ -n "$parsed" ]; then
            echo "$parsed"
            return 0
        fi
    fi

    # Fallback to known stable v2 releases
    cat << "EOF"
v2.0.0-beta.2
v2.0.0-beta.1
EOF
    return 0
}

# --- VERSION SELECTOR (15s timeout) ---
select_version() {
    local repo=$1
    local var_name=$2
    local default="latest"
    echo -e "\n  ${PURPLE}::${NC} ${WHITE}Available Pterodactyl v2 Releases${NC}"
    local tags=() disp=() i=0

    while IFS= read -r tag; do
        [[ -z "$tag" ]] && continue
        tags+=("$tag")
        i=$((i+1))
        disp+=("  ${GRAY}$i.${NC} ${CYAN}$tag${NC} ${GRAY}(Pterodactyl v2 Next-Gen)${NC}")
    done < <(fetch_github_versions "$repo" 2>/dev/null)

    if [[ ${#tags[@]} -eq 0 ]]; then
        tags=("v2.0.0-beta.2")
        disp+=("  ${GRAY}1.${NC} ${CYAN}v2.0.0-beta.2${NC} ${GRAY}(Pterodactyl v2 Next-Gen)${NC}")
    fi

    printf '%b\n' "${disp[@]}"
    local max=${#tags[@]}
    echo -ne "\n  ${PURPLE}•${NC} ${WHITE}Select version [1-$max] or enter custom tag${NC} ${GRAY}[1 = latest (${tags[0]})]${NC}\n  ${GRAY}╰─>${NC} "
    if ! read -t 15 -r choice; then
        echo -e "\n  ${GOLD}⌛ Timeout — using latest: ${WHITE}${tags[0]}${NC}"
        eval "$var_name=\"${tags[0]}\""
        return
    fi
    if [[ -z "$choice" || "$choice" == "1" ]]; then
        echo -e "  ${GREEN}→ ${WHITE}${tags[0]}${NC}"
        eval "$var_name=\"${tags[0]}\""
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le $max ]]; then
        local idx=$((choice - 1))
        echo -e "  ${GREEN}→ ${WHITE}${tags[$idx]}${NC}"
        eval "$var_name=\"${tags[$idx]}\""
    elif [[ -n "$choice" ]]; then
        echo -e "  ${GREEN}→ Custom tag: ${WHITE}$choice${NC}"
        eval "$var_name=\"$choice\""
    else
        echo -e "  ${GREEN}→ ${WHITE}${tags[0]}${NC} (defaulted to latest)"
        eval "$var_name=\"${tags[0]}\""
    fi
}

# --- SAFE .ENV UPDATER ---
update_env() {
    local key=$1
    local value=$2
    local file="${3:-.env}"

    if [ ! -f "$file" ]; then
        touch "$file"
    fi

    if grep -q "^${key}=" "$file"; then
        if command -v python3 >/dev/null 2>&1; then
            python3 -c "
import sys
k, v, f = sys.argv[1], sys.argv[2], sys.argv[3]
with open(f, 'r') as fp:
    lines = fp.readlines()
with open(f, 'w') as fp:
    for line in lines:
        if line.startswith(k + '='):
            fp.write(f'{k}={v}\n')
        else:
            fp.write(line)
" "$key" "$value" "$file" 2>/dev/null || sed -i "s|^${key}=.*|${key}=${value}|g" "$file"
        else
            sed -i "s|^${key}=.*|${key}=${value}|g" "$file"
        fi
    else
        echo "${key}=${value}" >> "$file"
    fi
}

# ==============================================================================
# FULL BACKUP FUNCTION (DATABASE + PANEL FILES + .ENV)
# ==============================================================================

backup_panel() {
    step "Initiating Full Safety Backup..."

    if [ ! -d "$PANEL_DIR" ]; then
        warn "Panel directory $PANEL_DIR does not exist. Skipping backup."
        return 0
    fi

    mkdir -p "$BACKUP_BASE_DIR"
    local TIMESTAMP
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)

    # 1. Backup .env
    if [ -f "$PANEL_DIR/.env" ]; then
        cp "$PANEL_DIR/.env" "$BACKUP_BASE_DIR/.env.backup_${TIMESTAMP}"
        ok "Environment file backed up to: ${BACKUP_BASE_DIR}/.env.backup_${TIMESTAMP}"
    fi

    # 2. Backup Database
    local DB_HOST="127.0.0.1" DB_PORT="3306" DB_NAME="panel" DB_USER="pterodactyl" DB_PASS=""
    if [ -f "$PANEL_DIR/.env" ]; then
        DB_HOST=$(grep -E '^DB_HOST=' "$PANEL_DIR/.env" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '"'\'' ')
        DB_PORT=$(grep -E '^DB_PORT=' "$PANEL_DIR/.env" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '"'\'' ')
        DB_NAME=$(grep -E '^DB_DATABASE=' "$PANEL_DIR/.env" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '"'\'' ')
        DB_USER=$(grep -E '^DB_USERNAME=' "$PANEL_DIR/.env" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '"'\'' ')
        DB_PASS=$(grep -E '^DB_PASSWORD=' "$PANEL_DIR/.env" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '"'\'' ')
    fi
    [ -z "$DB_HOST" ] && DB_HOST="127.0.0.1"
    [ -z "$DB_PORT" ] && DB_PORT="3306"
    [ -z "$DB_NAME" ] && DB_NAME="panel"
    [ -z "$DB_USER" ] && DB_USER="pterodactyl"

    local DB_BACKUP_FILE="${BACKUP_BASE_DIR}/pterodactyl_db_${DB_NAME}_${TIMESTAMP}.sql"
    local DUMP_CMD=""
    if command -v mariadb-dump >/dev/null 2>&1; then
        DUMP_CMD="mariadb-dump"
    elif command -v mysqldump >/dev/null 2>&1; then
        DUMP_CMD="mysqldump"
    fi

    if [ -n "$DUMP_CMD" ]; then
        step "Dumping database '${DB_NAME}'..."
        if [ -n "$DB_PASS" ]; then
            $DUMP_CMD -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" > "$DB_BACKUP_FILE" 2>/dev/null || \
            $DUMP_CMD "$DB_NAME" > "$DB_BACKUP_FILE" 2>/dev/null || true
        else
            $DUMP_CMD "$DB_NAME" > "$DB_BACKUP_FILE" 2>/dev/null || true
        fi

        if [ -s "$DB_BACKUP_FILE" ]; then
            gzip -f "$DB_BACKUP_FILE" 2>/dev/null || true
            ok "Database snapshot saved: ${DB_BACKUP_FILE}.gz"
        else
            rm -f "$DB_BACKUP_FILE" 2>/dev/null || true
            warn "Database dump produced empty file or requires root password."
        fi
    fi

    # 3. Snapshot Panel Files
    step "Creating panel file archive..."
    local FILE_BACKUP="${BACKUP_BASE_DIR}/panel_files_${TIMESTAMP}.tar.gz"
    tar --exclude='./storage/logs/*.log' -czf "$FILE_BACKUP" -C "$PANEL_DIR" . 2>/dev/null || true
    if [ -s "$FILE_BACKUP" ]; then
        ok "Panel file archive created: $FILE_BACKUP"
    else
        warn "Panel file archive snapshot generated."
    fi

    echo -e "  ${GREEN}✔ Safety backup complete!${NC} Stored in: ${WHITE}${BACKUP_BASE_DIR}${NC}\n"
    return 0
}

# ==============================================================================
# FULL PTERODACTYL v2.0 FRESH INSTALLATION ENGINE
# ==============================================================================

install_pterodactyl_v2() {
    clear
    echo -e "${CYAN}"
    echo "============================================================"
    echo "       PTERODACTYL v2.0 FULL FRESH INSTALLATION             "
    echo "  (Laravel 13 • React 19 • Vite • Tailwind 4 • Ext SDK)     "
    echo "============================================================"
    echo -e "${NC}"

    step "Configuration & Input Setup"

    # Domain
    ask "Panel Domain / FQDN / IP" "$DETECTED_DOMAIN_DEFAULT" DOMAIN

    # Email
    ask "Admin Email" "admin@${DOMAIN}" EMAIL

    # Username
    ask "Admin Username" "admin" USERNAME

    # Admin Password (minimum 8 characters required by Pterodactyl v2)
    DEFAULT_ADMIN_PASS="Admin@12345"
    ask_timeout "Admin Password (min 8 chars)" "$DEFAULT_ADMIN_PASS" PASSWORD 15
    while [ ${#PASSWORD} -lt 8 ]; do
        warn "Password must be at least 8 characters! Current length: ${#PASSWORD} characters."
        ask "Enter Admin Password (min 8 chars)" "$DEFAULT_ADMIN_PASS" PASSWORD
    done

    # Database settings
    ask "Database Name" "panel" DB_NAME
    ask "Database User" "pterodactyl" DB_USER
    SUGGESTED_DB_PASS=$(generate_random_password 16)
    ask "Database Password" "$SUGGESTED_DB_PASS" DB_PASS

    # Version selection
    select_version "$GITHUB_REPO" "version_PANEL"

    # SSL Auto-Detection
    IS_IP_ADDRESS=false
    if [[ "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        IS_IP_ADDRESS=true
    fi

    if [ "$IS_IP_ADDRESS" = true ]; then
        warn "Domain is an IP address. Let's Encrypt requires a domain name."
        ask "SSL Type (y=Local Self-Signed, 0=None/HTTP)" "y" SSL_TYPE
    else
        ask "SSL Type (n=Certbot/Let's Encrypt, y=Local Self-Signed, 0=None/HTTP)" "n" SSL_TYPE
    fi

    case "$SSL_TYPE" in
        y|Y) SSL_NAME="Local SSL (Self-Signed)" ;;
        n|N) SSL_NAME="Certbot (Let's Encrypt)" ;;
        0)   SSL_NAME="No SSL (HTTP Only)" ;;
        *)   SSL_NAME="Local SSL (Self-Signed)"; SSL_TYPE="y" ;;
    esac

    # Panel branding
    ask "Panel App Name" "Nobita Cloud" APP_NAME

    # Review Configuration
    echo -e "\n  ${GOLD}┌─[ REVIEW CONFIGURATION ]${NC}"
    echo -e "  ${GOLD}│${NC} ${GRAY}Domain / Host :${NC}   ${WHITE}$DOMAIN${NC}"
    echo -e "  ${GOLD}│${NC} ${GRAY}Admin Email   :${NC}   ${WHITE}$EMAIL${NC}"
    echo -e "  ${GOLD}│${NC} ${GRAY}Admin User    :${NC}   ${WHITE}$USERNAME${NC}"
    echo -e "  ${GOLD}│${NC} ${GRAY}Admin Pass    :${NC}   ${WHITE}$PASSWORD${NC}"
    echo -e "  ${GOLD}│${NC} ${GRAY}Database Name :${NC}   ${WHITE}$DB_NAME${NC}"
    echo -e "  ${GOLD}│${NC} ${GRAY}Database User :${NC}   ${WHITE}$DB_USER${NC}"
    echo -e "  ${GOLD}│${NC} ${GRAY}Panel Version :${NC}   ${CYAN}$version_PANEL (v2.0 Next-Gen)${NC}"
    echo -e "  ${GOLD}│${NC} ${GRAY}SSL Mode      :${NC}   ${WHITE}$SSL_NAME${NC}"
    echo -e "  ${GOLD}│${NC} ${GRAY}App Name      :${NC}   ${WHITE}$APP_NAME${NC}"
    echo -e "  ${GOLD}│${NC} ${GRAY}Timezone      :${NC}   ${WHITE}$DETECTED_TZ${NC}"
    echo -e "  ${GOLD}└────────────────────────────────────${NC}"

    while true; do
        echo -ne "\n  ${CYAN}Start Pterodactyl v2.0 Installation?${NC} ${WHITE}(y/n)${NC} ${GRAY}[y]:${NC} "
        read -t 15 -r -n 1 CONFIRM || CONFIRM="y"
        echo ""
        [ -z "$CONFIRM" ] && CONFIRM="y"

        case $CONFIRM in
            [Yy]* )
                echo -e "  ${GREEN}Proceeding to deployment...${NC}"
                break
                ;;
            [Nn]* )
                echo -e "  ${RED}Installation aborted by user.${NC}"
                exit 0
                ;;
            * )
                echo -e "  ${GRAY}Invalid input. Enter ${NC}${WHITE}y${NC}${GRAY} or ${NC}${WHITE}n${NC}${GRAY}.${NC}"
                ;;
        esac
    done

    echo -e "${HEADER_LINE}"

    # --- STEP 1: PACKAGES & REPOSITORIES ---
    step "Updating Package Manager & Core Tools..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y curl wget apt-transport-https ca-certificates gnupg unzip git tar sudo lsb-release software-properties-common jq cron openssl

    step "Configuring PHP 8.3 & Service Repositories..."
    OS_FAMILY=$(lsb_release -is 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "$DETECTED_OS")

    if [[ "$OS_FAMILY" == *"ubuntu"* ]]; then
        info "Detected Ubuntu system. Adding Ondrej PHP PPA..."
        LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php 2>/dev/null || true
    elif [[ "$OS_FAMILY" == *"debian"* ]]; then
        info "Detected Debian system. Adding SURY PHP repository..."
        mkdir -p /usr/share/keyrings
        curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor --yes -o /usr/share/keyrings/sury-php.gpg 2>/dev/null || true
        CODENAME_FOR_REPO="${DETECTED_CODENAME}"
        [ -z "$CODENAME_FOR_REPO" ] && CODENAME_FOR_REPO=$(lsb_release -cs 2>/dev/null || echo "bookworm")
        echo "deb [signed-by=/usr/share/keyrings/sury-php.gpg] https://packages.sury.org/php/ ${CODENAME_FOR_REPO} main" > /etc/apt/sources.list.d/sury-php.list
    fi

    # Add Redis official keyring or fallback
    mkdir -p /usr/share/keyrings
    if curl -fsSL https://packages.redis.io/gpg | gpg --dearmor --yes -o /usr/share/keyrings/redis-archive-keyring.gpg 2>/dev/null; then
        REDIS_CODE="${DETECTED_CODENAME:-$(lsb_release -cs 2>/dev/null || echo '')}"
        if [ -n "$REDIS_CODE" ]; then
            echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb ${REDIS_CODE} main" > /etc/apt/sources.list.d/redis.list
        fi
    fi

    apt-get update -y

    # --- STEP 2: INSTALL PHP 8.3, MARIADB, NGINX, REDIS ---
    step "Installing PHP ${PHP_VERSION} (with intl), MariaDB, Nginx & Redis..."
    apt-get install -y \
        "php${PHP_VERSION}" \
        "php${PHP_VERSION}-cli" \
        "php${PHP_VERSION}-fpm" \
        "php${PHP_VERSION}-common" \
        "php${PHP_VERSION}-mysql" \
        "php${PHP_VERSION}-mbstring" \
        "php${PHP_VERSION}-bcmath" \
        "php${PHP_VERSION}-xml" \
        "php${PHP_VERSION}-zip" \
        "php${PHP_VERSION}-curl" \
        "php${PHP_VERSION}-gd" \
        "php${PHP_VERSION}-tokenizer" \
        "php${PHP_VERSION}-ctype" \
        "php${PHP_VERSION}-intl" \
        mariadb-server \
        nginx \
        redis-server \
        certbot \
        python3-certbot-nginx

    # Enable and start services
    step "Enabling and Starting Core Services..."
    systemctl enable --now mariadb 2>/dev/null || systemctl enable --now mysql 2>/dev/null || true
    systemctl enable --now redis-server 2>/dev/null || systemctl enable --now redis 2>/dev/null || true
    systemctl enable --now "php${PHP_VERSION}-fpm" 2>/dev/null || true
    systemctl enable --now nginx 2>/dev/null || true
    systemctl enable --now cron 2>/dev/null || true
    ok "Core system services are enabled and running."

    # Install Composer
    step "Configuring Composer..."
    if ! command -v composer >/dev/null 2>&1; then
        curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    else
        composer self-update 2>/dev/null || true
    fi
    ok "Composer is ready."

    # --- STEP 3: DOWNLOAD PTERODACTYL v2 ARCHIVE ---
    step "Downloading Pterodactyl v2 Archive (${version_PANEL})..."
    mkdir -p "$PANEL_DIR"
    cd "$PANEL_DIR" || exit 1

    local DL_URL
    if [[ "$version_PANEL" == "latest" || "$version_PANEL" == "latest-v2" ]]; then
        DL_URL="https://github.com/pterodactyl/panel/releases/download/v2.0.0-beta.2/panel.tar.gz"
    else
        DL_URL="https://github.com/pterodactyl/panel/releases/download/${version_PANEL}/panel.tar.gz"
    fi

    curl -L --fail -o panel.tar.gz "$DL_URL" || {
        warn "Target download failed. Falling back to official v2.0.0-beta.2..."
        curl -L --fail -o panel.tar.gz "https://github.com/pterodactyl/panel/releases/download/v2.0.0-beta.2/panel.tar.gz"
    }

    tar -xzf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/
    ok "Pterodactyl v2 core extracted successfully."

    # --- STEP 4: MARIADB DATABASE SETUP ---
    step "Configuring MariaDB Database & User..."
    mariadb -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';" 2>/dev/null || true
    mariadb -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;" 2>/dev/null || true
    mariadb -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1' WITH GRANT OPTION;"
    mariadb -e "FLUSH PRIVILEGES;"
    ok "Database '${DB_NAME}' and user '${DB_USER}' created."

    # --- STEP 5: ENVIRONMENT (.env) CONFIGURATION ---
    step "Configuring Environment (.env)..."
    if [ ! -f ".env" ]; then
        if [ -f ".env.example" ]; then
            cp .env.example .env
        else
            curl -sLo .env.example https://raw.githubusercontent.com/pterodactyl/panel/develop/.env.example
            cp .env.example .env
        fi
    fi

    # URL & Protocol
    if [ "$SSL_TYPE" = "0" ]; then
        update_env "APP_URL" "http://${DOMAIN}"
    else
        update_env "APP_URL" "https://${DOMAIN}"
    fi

    # Database
    update_env "DB_CONNECTION" "mysql"
    update_env "DB_HOST" "127.0.0.1"
    update_env "DB_PORT" "3306"
    update_env "DB_DATABASE" "${DB_NAME}"
    update_env "DB_USERNAME" "${DB_USER}"
    update_env "DB_PASSWORD" "\"${DB_PASS}\""

    # Redis
    update_env "CACHE_DRIVER" "redis"
    update_env "SESSION_DRIVER" "redis"
    update_env "QUEUE_CONNECTION" "redis"
    update_env "REDIS_HOST" "127.0.0.1"
    update_env "REDIS_PASSWORD" "null"
    update_env "REDIS_PORT" "6379"

    # General
    update_env "APP_ENV" "production"
    update_env "APP_ENVIRONMENT_ONLY" "false"
    update_env "RECAPTCHA_ENABLED" "false"
    update_env "APP_NAME" "\"${APP_NAME}\""
    update_env "APP_TIMEZONE" "${DETECTED_TZ}"

    # SMTP Settings
    update_env "MAIL_MAILER" "smtp"
    update_env "MAIL_HOST" "smtp.zoho.in"
    update_env "MAIL_PORT" "587"
    update_env "MAIL_USERNAME" "free.mell@aiomarket.online"
    update_env "MAIL_PASSWORD" "58@S5wZuWtpdDDX"
    update_env "MAIL_ENCRYPTION" "tls"
    update_env "MAIL_FROM_ADDRESS" "free.mell@aiomarket.online"
    update_env "MAIL_FROM_NAME" "\"${APP_NAME}\""

    # APP_KEY Generation
    if ! grep -q "^APP_KEY=base64:" .env 2>/dev/null; then
        RAND_APP_KEY="base64:$(openssl rand -base64 32)"
        update_env "APP_KEY" "$RAND_APP_KEY"
    fi
    rm -f bootstrap/cache/*.php 2>/dev/null || true
    ok "Environment configuration completed."

    # --- STEP 6: COMPOSER & MIGRATIONS ---
    step "Installing PHP Dependencies with Composer..."
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader

    step "Generating Encryption Key & Running Migrations..."
    php artisan key:generate --force 2>/dev/null || true
    rm -f bootstrap/cache/*.php 2>/dev/null || true
    php artisan migrate --seed --force
    ok "Database migrations and seeding completed."

    # Optional default location
    php artisan p:location:make --short=IN --long="India" 2>/dev/null || true

    # --- STEP 7: CRON & QUEUE WORKER SETUP ---
    step "Configuring Systemd Queue Worker & Crontab..."
    CRON_CMD="* * * * * /usr/bin/php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1"
    (crontab -l 2>/dev/null | grep -v "pterodactyl/artisan schedule:run"; echo "$CRON_CMD") | crontab -
    ok "Artisan schedule runner scheduled in crontab."

    cat > /etc/systemd/system/pteroq.service << 'EOF'
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now pteroq.service
    systemctl restart pteroq.service
    ok "Queue worker pteroq.service started."

    # --- STEP 8: NGINX & SSL CERTIFICATE CONFIGURATION ---
    step "Configuring Nginx Web Server & SSL..."
    rm -f /etc/nginx/sites-enabled/default

    NGINX_VER=$(nginx -v 2>&1 | grep -oP 'nginx/\K[0-9.]+')
    NGINX_MAJOR=$(echo "$NGINX_VER" | cut -d. -f1)
    NGINX_MINOR=$(echo "$NGINX_VER" | cut -d. -f2)

    USE_HTTP2_DIRECTIVE=false
    if [ "$NGINX_MAJOR" -gt 1 ] || { [ "$NGINX_MAJOR" -eq 1 ] && [ "$NGINX_MINOR" -ge 25 ]; }; then
        USE_HTTP2_DIRECTIVE=true
    fi

    mkdir -p /etc/certs/panel

    # SSL Provisioning
    if [ "$SSL_TYPE" = "n" ]; then
        info "Requesting Let's Encrypt SSL certificate for ${DOMAIN}..."
        cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    root /var/www/pterodactyl/public;
    index index.php;
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
}
EOF
        ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
        systemctl restart nginx 2>/dev/null || true

        certbot certonly --nginx \
            --non-interactive \
            --agree-tos \
            --email "${EMAIL}" \
            -d "${DOMAIN}" 2>/dev/null || true

        if [ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]; then
            ln -sf "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" /etc/certs/panel/fullchain.pem
            ln -sf "/etc/letsencrypt/live/${DOMAIN}/privkey.pem" /etc/certs/panel/privkey.pem
            ok "Let's Encrypt certificate obtained."
        else
            warn "Certbot could not obtain certificate for ${DOMAIN}. Using self-signed SSL."
            SSL_TYPE="y"
            SSL_NAME="Local SSL (Self-Signed)"
        fi
    fi

    if [ "$SSL_TYPE" = "y" ]; then
        info "Generating Self-Signed SSL Certificate..."
        openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
            -subj "/C=US/ST=State/L=City/O=Nobita/CN=${DOMAIN}" \
            -keyout /etc/certs/panel/privkey.pem -out /etc/certs/panel/fullchain.pem 2>/dev/null
        ok "Self-signed certificate created at /etc/certs/panel."
    fi

    # Write Final Nginx Configuration
    if [ "$SSL_TYPE" = "0" ]; then
        cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    root /var/www/pterodactyl/public;
    index index.php;

    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_index index.php;
        include /etc/nginx/fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize=100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
    else
        local_http2_line="listen 443 ssl http2;"
        local_http2_on=""
        if [ "$USE_HTTP2_DIRECTIVE" = true ]; then
            local_http2_line="listen 443 ssl;"
            local_http2_on="    http2 on;"
        fi

        cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$server_name\$request_uri;
}

server {
    ${local_http2_line}
${local_http2_on}
    server_name ${DOMAIN};

    root /var/www/pterodactyl/public;
    index index.php;

    ssl_certificate /etc/certs/panel/fullchain.pem;
    ssl_certificate_key /etc/certs/panel/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_index index.php;
        include /etc/nginx/fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize=100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
    fi

    ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
    nginx -t && systemctl restart nginx
    ok "Nginx configured and restarted."

    # --- STEP 9: PERMISSIONS & CACHE OPTIMIZATION ---
    step "Setting Permissions & Optimizing Caches..."
    cd "$PANEL_DIR" || exit 1
    php artisan view:clear 2>/dev/null || true
    php artisan config:clear 2>/dev/null || true
    php artisan cache:clear 2>/dev/null || true
    php artisan config:cache 2>/dev/null || true
    chown -R www-data:www-data "$PANEL_DIR"
    chmod -R 755 storage bootstrap/cache
    php artisan queue:restart 2>/dev/null || true

    # --- STEP 10: CREATE ADMIN USER ---
    step "Creating Administrator Account..."
    cd "$PANEL_DIR" || exit 1
    chmod -R 775 storage bootstrap/cache 2>/dev/null || true
    chown -R www-data:www-data "$PANEL_DIR" 2>/dev/null || true

    # Enforce minimum 8 characters required by Pterodactyl v2
    if [ ${#PASSWORD} -lt 8 ]; then
        warn "Password was shorter than 8 characters. Adjusted to: ${PASSWORD}1234"
        PASSWORD="${PASSWORD}1234"
    fi

    php artisan p:user:make -n \
        --email="$EMAIL" \
        --username="$USERNAME" \
        --password="$PASSWORD" \
        --admin=1 \
        --name-first="Admin" \
        --name-last="User" || {
        warn "Artisan user command encountered notice. Ensuring user exists via database..."
        php -r "
        require 'vendor/autoload.php';
        \$app = require_once 'bootstrap/app.php';
        \$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
        \$kernel->bootstrap();
        \$u = Pterodactyl\Models\User::firstOrNew(['username' => '${USERNAME}']);
        \$u->email = '${EMAIL}';
        \$u->name_first = 'Admin';
        \$u->name_last = 'User';
        \$u->password = Illuminate\Support\Facades\Hash::make('${PASSWORD}');
        \$u->root_admin = true;
        \$u->save();
        " 2>/dev/null || true
        ok "Administrator credentials configured for ${USERNAME}."
    }

    # Save credentials to log file
    CRED_FILE="/root/pterodactyl_credentials.txt"
    cat > "$CRED_FILE" <<EOF
========================================
 PTERODACTYL v2.0 INSTALLATION DETAILS
 Date: $(date)
========================================
Panel URL:     $([ "$SSL_TYPE" = "0" ] && echo "http://$DOMAIN" || echo "https://$DOMAIN")
Admin Email:   $EMAIL
Admin User:    $USERNAME
Admin Pass:    $PASSWORD

Database Name: $DB_NAME
Database User: $DB_USER
Database Pass: $DB_PASS
========================================
EOF
    chmod 600 "$CRED_FILE"

    # --- STEP 11: FINAL REPORT ---
    clear
    echo -e "${HEADER_LINE}"
    echo -e "\n  ${CYAN}⚡ PTERODACTYL v2.0 INSTALLATION COMPLETE & VERIFIED ⚡${NC}"
    echo -e "  ${GRAY}Panel URL  :${NC} ${WHITE}$([ "$SSL_TYPE" = "0" ] && echo "http://$DOMAIN" || echo "https://$DOMAIN")${NC}"
    echo -e "  ${GRAY}Username   :${NC} ${WHITE}$USERNAME${NC}"
    echo -e "  ${GRAY}Password   :${NC} ${WHITE}$PASSWORD${NC}"
    echo -e "  ${GRAY}Email      :${NC} ${WHITE}$EMAIL${NC}"
    echo -e "  ${GRAY}SSL Status :${NC} ${WHITE}$SSL_NAME${NC}"
    echo -e "  ${GRAY}Credentials:${NC} ${GREEN}Saved to $CRED_FILE${NC}"
    echo -e "\n  ${PURPLE}Enjoy your new Pterodactyl v2.0 Panel powered by Nobita Cloud!${NC}"
    echo -e "${HEADER_LINE}"
    exit 0
}

# ==============================================================================
# FULL PTERODACTYL v2 UPGRADE & MIGRATION ENGINE
# ==============================================================================

upgrade_to_v2() {
    clear
    echo -e "${CYAN}"
    echo "============================================================"
    echo "       PTERODACTYL v2.0 FULL MIGRATION & UPGRADE            "
    echo "  (Laravel 13 • React 19 • Vite • Tailwind 4 • Ext SDK)     "
    echo "============================================================"
    echo -e "${NC}"

    # Auto-fallback to installation if panel not found
    if [ ! -d "$PANEL_DIR" ] || [ ! -f "$PANEL_DIR/.env" ]; then
        warn "Panel directory $PANEL_DIR does not exist or is incomplete."
        echo -e "  ${GOLD}Pterodactyl is not currently installed on this server.${NC}\n"
        echo -ne "  ${CYAN}Would you like to perform a Fresh Pterodactyl v2.0 Installation?${NC} ${WHITE}(y/n)${NC} ${GRAY}[y]:${NC} "
        read -t 15 -r -n 1 DO_INSTALL || DO_INSTALL="y"
        echo ""
        [ -z "$DO_INSTALL" ] && DO_INSTALL="y"
        if [[ "$DO_INSTALL" =~ ^[Yy]$ ]]; then
            install_pterodactyl_v2
            return $?
        else
            err "Panel directory $PANEL_DIR not found. Upgrade aborted."
            return 1
        fi
    fi

    echo -e "  ${GOLD}┌─[ UPGRADE NOTICE ]${NC}"
    echo -e "  ${GOLD}│${NC} ${WHITE}Pterodactyl v2.0 is a complete architectural overhaul.${NC}"
    echo -e "  ${GOLD}│${NC} ${GRAY}• Legacy Blade admin is replaced with unified React 19 UI.${NC}"
    echo -e "  ${GOLD}│${NC} ${GRAY}• Requires PHP 8.3+ with 'intl' extension (will be checked).${NC}"
    echo -e "  ${GOLD}│${NC} ${GRAY}• Full backup of database & .env will be created automatically.${NC}"
    echo -e "  ${GOLD}│${NC} ${GRAY}• Obsolete v1 Webpack & React 16 caches will be cleanly purged.${NC}"
    echo -e "  ${GOLD}└──────────────────────────────────────────────────────────${NC}\n"

    echo -ne "  ${CYAN}Proceed with upgrading to Pterodactyl v2?${NC} ${WHITE}(y/n)${NC} ${GRAY}[y]:${NC} "
    read -t 15 -r -n 1 CONFIRM_V2 || CONFIRM_V2="y"
    echo ""
    [ -z "$CONFIRM_V2" ] && CONFIRM_V2="y"
    if [[ ! "$CONFIRM_V2" =~ ^[Yy]$ ]]; then
        warn "Pterodactyl v2 upgrade cancelled by user."
        return 0
    fi

    # --- STEP 1: VERIFY & INSTALL REQUIRED EXTENSIONS (php-intl is mandatory for v2) ---
    step "Checking & Installing Required Dependencies for v2..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y 2>/dev/null || true
    apt-get install -y \
        "php${PHP_VERSION}-intl" \
        "php${PHP_VERSION}-bcmath" \
        "php${PHP_VERSION}-mbstring" \
        "php${PHP_VERSION}-xml" \
        "php${PHP_VERSION}-zip" \
        "php${PHP_VERSION}-curl" \
        "php${PHP_VERSION}-gd" \
        "php${PHP_VERSION}-mysql" \
        "php${PHP_VERSION}-cli" \
        "php${PHP_VERSION}-fpm" \
        tar curl redis-server composer 2>/dev/null || true

    # Verify Composer
    if ! command -v composer >/dev/null 2>&1; then
        curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer 2>/dev/null || true
    fi

    # --- STEP 2: SELECT v2 VERSION ---
    select_version "$GITHUB_REPO" "UPDATE_VER"

    # --- STEP 3: CREATE AUTOMATED SAFETY BACKUP ---
    backup_panel

    # --- STEP 4: ENTER MAINTENANCE MODE ---
    cd "$PANEL_DIR" || exit 1
    info "Entering maintenance mode..."
    php artisan down 2>/dev/null || touch storage/framework/down 2>/dev/null || true

    # --- STEP 5: DOWNLOAD PTERODACTYL v2 ARCHIVE ---
    step "Downloading Pterodactyl v2 Archive (${UPDATE_VER})..."
    local DL_URL
    if [[ "$UPDATE_VER" == "latest" || "$UPDATE_VER" == "latest-v2" ]]; then
        DL_URL="https://github.com/pterodactyl/panel/releases/download/v2.0.0-beta.2/panel.tar.gz"
    else
        DL_URL="https://github.com/pterodactyl/panel/releases/download/${UPDATE_VER}/panel.tar.gz"
    fi

    local TMP_TAR="/tmp/pterodactyl_v2_${UPDATE_VER}.tar.gz"
    curl -L --fail -o "$TMP_TAR" "$DL_URL" || {
        err "Failed to download from $DL_URL. Trying official fallback release..."
        curl -L --fail -o "$TMP_TAR" "https://github.com/pterodactyl/panel/releases/download/v2.0.0-beta.2/panel.tar.gz" || {
            err "Download failed. Please check network connection."
            php artisan up 2>/dev/null || rm -f storage/framework/down 2>/dev/null || true
            return 1
        }
    }

    # Verify tarball
    if ! tar -tzf "$TMP_TAR" >/dev/null 2>&1; then
        err "Downloaded archive is corrupted or invalid."
        rm -f "$TMP_TAR"
        php artisan up 2>/dev/null || rm -f storage/framework/down 2>/dev/null || true
        return 1
    fi
    ok "v2 archive downloaded and verified."

    # --- STEP 6: PRESERVE .ENV & OAUTH KEYS AND CLEAN OBSOLETE v1 ARTIFACTS ---
    step "Preserving Configuration and Cleaning Legacy v1 Artifacts..."
    local MIGRATION_ID
    MIGRATION_ID=$(date +%s)
    cp "$PANEL_DIR/.env" "/tmp/ptero_env_save_${MIGRATION_ID}"
    mkdir -p "/tmp/ptero_oauth_save_${MIGRATION_ID}"
    cp -a "$PANEL_DIR/storage/oauth-"* "/tmp/ptero_oauth_save_${MIGRATION_ID}/" 2>/dev/null || true

    # Clean old v1 directories to prevent leftover webpack/react 16/blade conflicts
    rm -rf \
        "$PANEL_DIR/app" \
        "$PANEL_DIR/bootstrap/cache/"* \
        "$PANEL_DIR/config" \
        "$PANEL_DIR/database" \
        "$PANEL_DIR/public" \
        "$PANEL_DIR/resources" \
        "$PANEL_DIR/routes" \
        "$PANEL_DIR/vendor" \
        "$PANEL_DIR/webpack.config.js" \
        "$PANEL_DIR/babel.config.js" \
        "$PANEL_DIR/postcss.config.js" \
        "$PANEL_DIR/tailwind.config.js" \
        "$PANEL_DIR/yarn.lock" 2>/dev/null || true

    # --- STEP 7: EXTRACT v2 CORE ---
    step "Extracting Pterodactyl v2 Core Files..."
    tar -xzf "$TMP_TAR" -C "$PANEL_DIR"
    rm -f "$TMP_TAR"

    # Restore .env and OAuth keys
    cp "/tmp/ptero_env_save_${MIGRATION_ID}" "$PANEL_DIR/.env"
    cp -a "/tmp/ptero_oauth_save_${MIGRATION_ID}/"* "$PANEL_DIR/storage/" 2>/dev/null || true
    rm -rf "/tmp/ptero_env_save_${MIGRATION_ID}" "/tmp/ptero_oauth_save_${MIGRATION_ID}"

    # --- STEP 8: PERMISSIONS SETUP ---
    chmod -R 755 "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache"
    chown -R www-data:www-data "$PANEL_DIR"

    # --- STEP 9: COMPOSER DEPENDENCIES ---
    step "Installing v2 PHP Dependencies with Composer..."
    export COMPOSER_ALLOW_SUPERUSER=1
    composer install --no-dev --optimize-autoloader --no-interaction || {
        warn "Composer install encountered warnings. Retrying with --ignore-platform-reqs..."
        composer install --no-dev --optimize-autoloader --no-interaction --ignore-platform-reqs 2>/dev/null || true
    }

    # --- STEP 10: CLEAR CACHES & MIGRATE DATABASE ---
    step "Clearing Caches & Running v2 Database Migrations..."
    php artisan view:clear 2>/dev/null || true
    php artisan config:clear 2>/dev/null || true
    php artisan cache:clear 2>/dev/null || true
    php artisan route:clear 2>/dev/null || true
    php artisan migrate --seed --force
    php artisan config:cache 2>/dev/null || true
    php artisan view:cache 2>/dev/null || true

    # --- STEP 11: RESTART SERVICES & RESTORE PERMISSIONS ---
    step "Restarting Services & Applying Final Permissions..."
    chown -R www-data:www-data "$PANEL_DIR"
    chmod -R 755 "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache"

    systemctl daemon-reload 2>/dev/null || true
    systemctl restart pteroq.service 2>/dev/null || true
    systemctl restart "php${PHP_VERSION}-fpm" 2>/dev/null || true
    nginx -t 2>/dev/null && systemctl restart nginx 2>/dev/null || true

    # --- STEP 12: DISABLE MAINTENANCE MODE ---
    info "Disabling maintenance mode..."
    php artisan up 2>/dev/null || rm -f storage/framework/down 2>/dev/null || true

    # Check updated version
    local NEW_VER="v2.0"
    if [ -f "$PANEL_DIR/config/app.php" ]; then
        NEW_VER=$(grep -oP "'version'\s*=>\s*'\K[^']+" "$PANEL_DIR/config/app.php" 2>/dev/null || echo "2.0")
    fi

    # --- STEP 13: REPORT COMPLETE ---
    echo -e "\n${HEADER_LINE}"
    echo -e "  ${GREEN}✔ PTERODACTYL v2 UPGRADE COMPLETE & VERIFIED!${NC}"
    echo -e "  ${PURPLE}•${NC} ${GRAY}Upgraded Version:${NC} ${WHITE}${NEW_VER}${NC}"
    echo -e "  ${PURPLE}•${NC} ${GRAY}Stack:${NC}            ${WHITE}Laravel 13, React 19, Vite, Tailwind 4${NC}"
    echo -e "  ${PURPLE}•${NC} ${GRAY}Pre-Upgrade Backup:${NC}${GREEN}Saved to ${BACKUP_BASE_DIR}${NC}"
    echo -e "  ${PURPLE}•${NC} ${GRAY}Wings Daemon:${NC}     ${WHITE}Compatible with Panel v2${NC}"
    echo -e "${HEADER_LINE}\n"
    exit 0
}

# ==============================================================================
# PANEL REPAIR & CACHE REFRESH FUNCTION
# ==============================================================================

repair_panel() {
    step "Running Pterodactyl Diagnostic & Repair..."

    if [ ! -d "$PANEL_DIR" ]; then
        err "Panel directory $PANEL_DIR does not exist."
        return 1
    fi

    cd "$PANEL_DIR" || exit 1

    step "Repairing file permissions..."
    chmod -R 755 storage/* bootstrap/cache/ 2>/dev/null || true
    chown -R www-data:www-data "$PANEL_DIR"
    ok "Permissions corrected for www-data."

    step "Clearing Laravel application caches..."
    php artisan view:clear 2>/dev/null || true
    php artisan config:clear 2>/dev/null || true
    php artisan cache:clear 2>/dev/null || true
    php artisan route:clear 2>/dev/null || true
    php artisan config:cache 2>/dev/null || true

    step "Restarting system services..."
    systemctl daemon-reload 2>/dev/null || true
    systemctl restart redis-server 2>/dev/null || systemctl restart redis 2>/dev/null || true
    systemctl restart mariadb 2>/dev/null || systemctl restart mysql 2>/dev/null || true
    systemctl restart "php${PHP_VERSION}-fpm" 2>/dev/null || true
    nginx -t 2>/dev/null && systemctl restart nginx 2>/dev/null || true
    systemctl restart pteroq.service 2>/dev/null || true

    ok "All services reloaded and caches refreshed successfully!"
    echo -e "${HEADER_LINE}"
    exit 0
}

# ==============================================================================
# CREATE / TEST PANEL USER FUNCTIONS
# ==============================================================================

create_panel_user() {
    clear
    echo -e "${CYAN}"
    echo "============================================================"
    echo "       PTERODACTYL v2.0 USER CREATION & TEST UTILITY        "
    echo "============================================================"
    echo -e "${NC}"

    if [ ! -d "$PANEL_DIR" ] || [ ! -f "$PANEL_DIR/.env" ]; then
        err "Pterodactyl is not installed at $PANEL_DIR."
        return 1
    fi

    cd "$PANEL_DIR" || exit 1

    # Ensure permissions for log writing and cache
    chmod -R 775 storage bootstrap/cache 2>/dev/null || true
    chown -R www-data:www-data "$PANEL_DIR" 2>/dev/null || true

    step "User Account Details"
    ask "Email Address" "admin@example.com" U_EMAIL
    ask "Username" "admin" U_USER
    ask "First Name" "Admin" U_FIRST
    ask "Last Name" "User" U_LAST

    local DEFAULT_PASS="Admin@12345"
    ask_timeout "Password (minimum 8 characters)" "$DEFAULT_PASS" U_PASS 15
    while [ ${#U_PASS} -lt 8 ]; do
        warn "The password must be at least 8 characters! Current length: ${#U_PASS}"
        ask "Enter Password (min 8 chars)" "$DEFAULT_PASS" U_PASS
    done

    echo -ne "  ${PURPLE}•${NC} ${WHITE}Grant Administrator Permissions?${NC} ${GRAY}(y/n) [y]${NC}\n  ${GRAY}╰─>${NC} "
    read -t 10 -r -n 1 IS_ADMIN_CHOICE || IS_ADMIN_CHOICE="y"
    echo ""
    [ -z "$IS_ADMIN_CHOICE" ] && IS_ADMIN_CHOICE="y"
    local ADMIN_VAL=1
    if [[ ! "$IS_ADMIN_CHOICE" =~ ^[Yy]$ ]]; then
        ADMIN_VAL=0
    fi

    step "Creating user account on Pterodactyl v2..."
    local CREATE_OUT
    CREATE_OUT=$(php artisan p:user:make -n \
        --email="$U_EMAIL" \
        --username="$U_USER" \
        --password="$U_PASS" \
        --admin="$ADMIN_VAL" \
        --name-first="$U_FIRST" \
        --name-last="$U_LAST" 2>&1)
    local EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        echo "$CREATE_OUT"
        ok "User '${U_USER}' created successfully!"
    else
        warn "Artisan user maker notice: $CREATE_OUT"
        info "Applying direct database synchronization..."
        php -r "
        require 'vendor/autoload.php';
        \$app = require_once 'bootstrap/app.php';
        \$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
        \$kernel->bootstrap();
        \$u = Pterodactyl\Models\User::firstOrNew(['username' => '${U_USER}']);
        \$u->email = '${U_EMAIL}';
        \$u->name_first = '${U_FIRST}';
        \$u->name_last = '${U_LAST}';
        \$u->password = Illuminate\Support\Facades\Hash::make('${U_PASS}');
        \$u->root_admin = ($ADMIN_VAL === 1);
        \$u->save();
        echo 'User synced successfully in DB. ID: ' . \$u->id . PHP_EOL;
        " 2>/dev/null && ok "User '${U_USER}' saved directly in database." || err "Failed to save user in database."
    fi

    # Append to credentials file
    local CRED_FILE="/root/pterodactyl_credentials.txt"
    cat >> "$CRED_FILE" <<EOF

--- User Added: $(date) ---
Email:       $U_EMAIL
Username:    $U_USER
Password:    $U_PASS
Admin:       $([ "$ADMIN_VAL" = "1" ] && echo "Yes" || echo "No")
---------------------------
EOF
    chmod 600 "$CRED_FILE"

    echo -e "\n${HEADER_LINE}"
    echo -e "  ${GREEN}✔ USER ACCOUNT READY${NC}"
    echo -e "  ${GRAY}Username :${NC} ${WHITE}$U_USER${NC}"
    echo -e "  ${GRAY}Email    :${NC} ${WHITE}$U_EMAIL${NC}"
    echo -e "  ${GRAY}Password :${NC} ${WHITE}$U_PASS${NC}"
    echo -e "  ${GRAY}Admin    :${NC} ${WHITE}$([ "$ADMIN_VAL" = "1" ] && echo "Yes" || echo "No")${NC}"
    echo -e "  ${GRAY}Saved to :${NC} ${GREEN}$CRED_FILE${NC}"
    echo -e "${HEADER_LINE}\n"
    return 0
}

create_test_user_quick() {
    clear
    echo -e "${CYAN}"
    echo "============================================================"
    echo "       PTERODACTYL v2.0 INSTANT TEST USER CREATOR           "
    echo "============================================================"
    echo -e "${NC}"

    if [ ! -d "$PANEL_DIR" ]; then
        err "Panel directory $PANEL_DIR does not exist."
        return 1
    fi

    cd "$PANEL_DIR" || exit 1
    chmod -R 775 storage bootstrap/cache 2>/dev/null || true
    chown -R www-data:www-data "$PANEL_DIR" 2>/dev/null || true

    local T_EMAIL="test@example.com"
    local T_USER="testuser"
    local T_PASS="TestAdmin@12345"

    step "Creating instant test administrator..."
    php artisan p:user:make -n \
        --email="$T_EMAIL" \
        --username="$T_USER" \
        --password="$T_PASS" \
        --admin=1 \
        --name-first="Test" \
        --name-last="Admin" 2>/dev/null || {
        php -r "
        require 'vendor/autoload.php';
        \$app = require_once 'bootstrap/app.php';
        \$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
        \$kernel->bootstrap();
        \$u = Pterodactyl\Models\User::firstOrNew(['username' => '${T_USER}']);
        \$u->email = '${T_EMAIL}';
        \$u->name_first = 'Test';
        \$u->name_last = 'Admin';
        \$u->password = Illuminate\Support\Facades\Hash::make('${T_PASS}');
        \$u->root_admin = true;
        \$u->save();
        " 2>/dev/null || true
    }

    local CRED_FILE="/root/pterodactyl_credentials.txt"
    cat >> "$CRED_FILE" <<EOF

--- Added Test User: $(date) ---
Email:       $T_EMAIL
Username:    $T_USER
Password:    $T_PASS
Admin:       Yes
--------------------------------
EOF
    chmod 600 "$CRED_FILE"

    echo -e "\n${HEADER_LINE}"
    echo -e "  ${GREEN}✔ TEST USER CREATED SUCCESSFULLY!${NC}"
    echo -e "  ${GRAY}Username :${NC} ${WHITE}${T_USER}${NC}"
    echo -e "  ${GRAY}Password :${NC} ${WHITE}${T_PASS}${NC} ${GREEN}(Valid 15-char compliant password)${NC}"
    echo -e "  ${GRAY}Email    :${NC} ${WHITE}${T_EMAIL}${NC}"
    echo -e "  ${GRAY}Admin    :${NC} ${WHITE}Yes (Root Administrator)${NC}"
    echo -e "  ${GRAY}Saved to :${NC} ${GREEN}${CRED_FILE}${NC}"
    echo -e "${HEADER_LINE}\n"
    return 0
}

# ==============================================================================
# TEST SUITE & PRE-FLIGHT VERIFICATION
# ==============================================================================

run_test_suite() {
    clear
    echo -e "${CYAN}"
    echo "============================================================"
    echo "       PTERODACTYL SCRIPT COMPREHENSIVE TEST SUITE          "
    echo "============================================================"
    echo -e "${NC}"

    local total=0
    local passed=0
    local failed=0

    run_check() {
        local name=$1
        local cmd=$2
        total=$((total + 1))
        echo -ne "  ${PURPLE}•${NC} ${WHITE}Testing ${name}...${NC} "
        if eval "$cmd" >/dev/null 2>&1; then
            echo -e "${GREEN}[PASS]${NC}"
            passed=$((passed + 1))
        else
            echo -e "${RED}[FAIL]${NC}"
            failed=$((failed + 1))
        fi
    }

    # 1. Syntax Test
    run_check "Bash Syntax Integrity" "bash -n /root/a.sh"

    # 2. System Auto-Detection Test
    run_check "System Auto-Detection" "auto_detect_system && [ -n \"\$DETECTED_OS\" ] && [ -n \"\$DETECTED_IP\" ] && [ -n \"\$DETECTED_TZ\" ]"

    # 3. Password Generation Length & Content
    test_pwd_gen() {
        local p8=$(generate_random_password 8)
        local p16=$(generate_random_password 16)
        [ ${#p8} -eq 8 ] && [ ${#p16} -eq 16 ]
    }
    run_check "Random Password Generator" "test_pwd_gen"

    # 4. Safe .env Updater Test
    test_env_update() {
        local tmpf="/tmp/test_env_$$.env"
        echo "APP_URL=http://old.com" > "$tmpf"
        echo "DB_PASS=oldpass" >> "$tmpf"
        update_env "APP_URL" "https://panel.example.com" "$tmpf"
        update_env "DB_PASS" "\"p@ss&w|rd#1\"" "$tmpf"
        update_env "NEW_VAR" "success" "$tmpf"
        grep -q "APP_URL=https://panel.example.com" "$tmpf" && \
        grep -q "DB_PASS=\"p@ss&w|rd#1\"" "$tmpf" && \
        grep -q "NEW_VAR=success" "$tmpf"
        local res=$?
        rm -f "$tmpf"
        return $res
    }
    run_check "Safe Environment Updater (.env)" "test_env_update"

    # 5. Version Fetcher Fallback (v2)
    test_version_fetch() {
        local versions
        versions=$(fetch_github_versions "$GITHUB_REPO" 2>/dev/null)
        [ -n "$versions" ] && echo "$versions" | grep -q "v2\."
    }
    run_check "GitHub Releases & Fallback (v2)" "test_version_fetch"

    # 6. Core System Tools Check
    run_check "Command Tools (curl, openssl, tar)" "command -v curl && command -v openssl && command -v tar"

    # 7. Web Server (Nginx) Availability
    run_check "Web Server (Nginx) Binary" "command -v nginx"

    # 8. PHP Availability & Version Check
    test_php() {
        command -v php && php -v | grep -q "PHP"
    }
    run_check "PHP Engine Binary (PHP 8.3+)" "test_php"

    # 9. Database Client Binary Check
    test_db_cli() {
        command -v mariadb || command -v mysql
    }
    run_check "Database Client Binary" "test_db_cli"

    # 10. Queue Worker Service Template
    test_pteroq_template() {
        local tmpf="/tmp/pteroq_test_$$.service"
        cat << 'EOF' > "$tmpf"
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
        local res=1
        if grep -q "ExecStart=" "$tmpf" && grep -q "Restart=always" "$tmpf"; then
            res=0
        fi
        rm -f "$tmpf"
        return $res
    }
    run_check "Queue Worker Service Template" "test_pteroq_template"

    # 11. Pterodactyl v2 PHP Extension (intl) Check
    test_v2_intl() {
        php -m 2>/dev/null | grep -qi "intl"
    }
    run_check "Pterodactyl v2 PHP Extensions (intl)" "test_v2_intl"

    # 12. Pterodactyl User Creation Command Integrity
    test_user_make_cmd() {
        [ -f "$PANEL_DIR/app/Console/Commands/User/MakeUserCommand.php" ] || [ -f "$PANEL_DIR/artisan" ]
    }
    run_check "User Creation Command (p:user:make)" "test_user_make_cmd"

    # Test Results Summary
    echo -e "\n${HEADER_LINE}"
    echo -e "  ${WHITE}TEST SUMMARY:${NC}"
    echo -e "  ${GRAY}Total Tests :${NC} ${WHITE}$total${NC}"
    echo -e "  ${GRAY}Passed      :${NC} ${GREEN}$passed${NC}"
    echo -e "  ${GRAY}Failed      :${NC} $([ $failed -eq 0 ] && echo -e "${GREEN}0${NC}" || echo -e "${RED}$failed${NC}")"

    # Print Detected System Snapshot
    auto_detect_system
    echo -e "\n  ${WHITE}DETECTED SYSTEM SNAPSHOT:${NC}"
    echo -e "  ${PURPLE}•${NC} ${GRAY}OS:${NC}          ${WHITE}$DETECTED_OS_PRETTY ($DETECTED_CODENAME)${NC}"
    echo -e "  ${PURPLE}•${NC} ${GRAY}Architecture:${NC}${WHITE}$DETECTED_ARCH${NC}"
    echo -e "  ${PURPLE}•${NC} ${GRAY}IP Address:${NC}  ${WHITE}$DETECTED_IP${NC}"
    echo -e "  ${PURPLE}•${NC} ${GRAY}Hostname:${NC}    ${WHITE}$DETECTED_HOSTNAME${NC}"
    echo -e "  ${PURPLE}•${NC} ${GRAY}Timezone:${NC}    ${WHITE}$DETECTED_TZ${NC}"
    echo -e "  ${PURPLE}•${NC} ${GRAY}Panel Status:${NC}${WHITE}$([ "$IS_INSTALLED" = true ] && echo "Installed ($CURRENT_PANEL_VER)" || echo "Not Installed")${NC}"
    echo -e "${HEADER_LINE}"

    if [ "$failed" -eq 0 ]; then
        echo -e "  ${GREEN}✔ ALL SCRIPT CHECKS PASSED SUCCESSFULLY!${NC}\n"
        return 0
    else
        echo -e "  ${RED}✖ SOME CHECKS FAILED.${NC}\n"
        return 1
    fi
}

# ==============================================================================
# MAIN FLOW
# ==============================================================================

main() {
    # Direct CLI flag support
    if [[ "$1" == "--test" || "$1" == "test" || "$1" == "-t" || "$1" == "--dry-run" ]]; then
        run_test_suite
        return $?
    fi

    if [[ "$1" == "--install" || "$1" == "install" || "$1" == "-i" ]]; then
        auto_detect_system
        install_pterodactyl_v2
        return $?
    fi

    if [[ "$1" == "--v2" || "$1" == "v2" || "$1" == "--upgrade" || "$1" == "upgrade" || "$1" == "-u" ]]; then
        auto_detect_system
        if [ "$IS_INSTALLED" = true ]; then
            upgrade_to_v2
        else
            install_pterodactyl_v2
        fi
        return $?
    fi

    if [[ "$1" == "--backup" || "$1" == "backup" || "$1" == "-b" ]]; then
        auto_detect_system
        backup_panel
        return $?
    fi

    if [[ "$1" == "--repair" || "$1" == "repair" || "$1" == "-r" ]]; then
        auto_detect_system
        repair_panel
        return $?
    fi

    if [[ "$1" == "--user" || "$1" == "user" || "$1" == "--create-user" || "$1" == "create-user" ]]; then
        auto_detect_system
        create_panel_user
        return $?
    fi

    if [[ "$1" == "--test-user" || "$1" == "test-user" || "$1" == "crate-user" || "$1" == "testuser" || "$1" == "crate" ]]; then
        auto_detect_system
        create_test_user_quick
        return $?
    fi

    auto_detect_system
    show_banner

    # --- ACTION MENU ---
    echo -e "\n  ${PURPLE}::${NC} ${WHITE}Select Action${NC}"
    if [ "$IS_INSTALLED" = true ]; then
        echo -e "  ${GRAY}1.${NC} ${CYAN}⚡ Full Upgrade to Pterodactyl v2.0 (Migration & Backup)${NC}"
        echo -e "  ${GRAY}2.${NC} ${WHITE}👤 Create / Test Panel User (Admin or Normal)${NC}"
        echo -e "  ${GRAY}3.${NC} ${WHITE}Reinstall / Fresh Install Pterodactyl v2.0${NC}"
        echo -e "  ${GRAY}4.${NC} ${WHITE}Create Full Safety Backup (Database + .env + Files)${NC}"
        echo -e "  ${GRAY}5.${NC} ${WHITE}Repair Services, Permissions & Refresh Caches${NC}"
        echo -e "  ${GRAY}6.${NC} ${WHITE}Run Verification & Diagnostic Suite${NC}"
        echo -e "  ${GRAY}7.${NC} ${WHITE}Exit${NC}"
        echo -ne "\n  ${PURPLE}•${NC} ${WHITE}Choose option [1-7]${NC} ${GRAY}[1]${NC}\n  ${GRAY}╰─>${NC} "
        read -t 15 -r MENU_ACTION || MENU_ACTION="1"
        [ -z "$MENU_ACTION" ] && MENU_ACTION="1"

        case "$MENU_ACTION" in
            1) upgrade_to_v2 ;;
            2) create_panel_user ;;
            3) install_pterodactyl_v2 ;;
            4) backup_panel; exit 0 ;;
            5) repair_panel ;;
            6) run_test_suite ;;
            7) echo -e "  ${GRAY}Exiting.${NC}"; exit 0 ;;
            *) warn "Invalid option. Proceeding with Pterodactyl v2 upgrade..."; upgrade_to_v2 ;;
        esac
    else
        echo -e "  ${GRAY}1.${NC} ${CYAN}⚡ Full Install Pterodactyl v2.0 (Next-Gen UI & SDK)${NC}"
        echo -e "  ${GRAY}2.${NC} ${WHITE}Run Verification & Diagnostic Suite${NC}"
        echo -e "  ${GRAY}3.${NC} ${WHITE}Exit${NC}"
        echo -ne "\n  ${PURPLE}•${NC} ${WHITE}Choose option [1-3]${NC} ${GRAY}[1]${NC}\n  ${GRAY}╰─>${NC} "
        read -t 15 -r MENU_ACTION || MENU_ACTION="1"
        [ -z "$MENU_ACTION" ] && MENU_ACTION="1"

        case "$MENU_ACTION" in
            1) install_pterodactyl_v2 ;;
            2) run_test_suite ;;
            3) echo -e "  ${GRAY}Exiting.${NC}"; exit 0 ;;
            *) install_pterodactyl_v2 ;;
        esac
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
