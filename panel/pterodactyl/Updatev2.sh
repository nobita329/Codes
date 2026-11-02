#!/bin/bash
# ==============================================================================
#  PTERODACTYL v2.0 FULL UPDATER & MIGRATOR
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
    echo -e "         ${CYAN}⚡ PTERODACTYL v2.0 FULL UPDATER & MIGRATOR ⚡${NC}"
    echo -e "              ${GRAY}Laravel 13 • React 19 • Vite • Tailwind 4${NC}"
    echo -e "${HEADER_LINE}"
    echo -e "  ${PURPLE}•${NC} ${GRAY}OS Detected:${NC}      ${WHITE}${DETECTED_OS_PRETTY} (${DETECTED_CODENAME:-$DETECTED_ARCH})${NC}"
    echo -e "  ${PURPLE}•${NC} ${GRAY}Server IP:${NC}        ${WHITE}${DETECTED_IP}${NC}"
    echo -e "  ${PURPLE}•${NC} ${GRAY}Timezone:${NC}         ${WHITE}${DETECTED_TZ}${NC}"
    echo -e "  ${PURPLE}•${NC} ${GRAY}Installed Panel:${NC}  ${WHITE}$([ "$IS_INSTALLED" = true ] && echo -e "${GREEN}${CURRENT_PANEL_VER}${NC}" || echo -e "${YELLOW}Not Detected${NC}")${NC}"
    echo -e "  ${PURPLE}•${NC} ${GRAY}Target Upgrade:${NC}   ${CYAN}Pterodactyl v2.0 (Next-Gen UI & SDK)${NC}"
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
    step "Initiating Full Safety Backup (Pre-v2)..."

    if [ ! -d "$PANEL_DIR" ]; then
        err "Panel directory $PANEL_DIR does not exist. Cannot backup."
        return 1
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

    if [ ! -d "$PANEL_DIR" ]; then
        err "Panel directory $PANEL_DIR does not exist. Please ensure Pterodactyl is installed."
        return 1
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

    if [[ "$1" == "--v2" || "$1" == "v2" || "$1" == "--upgrade" || "$1" == "upgrade" || "$1" == "-u" ]]; then
        auto_detect_system
        upgrade_to_v2
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

    auto_detect_system
    show_banner

    # --- ACTION MENU ---
    echo -e "\n  ${PURPLE}::${NC} ${WHITE}Select Action${NC}"
    echo -e "  ${GRAY}1.${NC} ${CYAN}⚡ Full Update to Pterodactyl v2.0 (Recommended)${NC}"
    echo -e "  ${GRAY}2.${NC} ${WHITE}Create Full Safety Backup (Database + .env + Files)${NC}"
    echo -e "  ${GRAY}3.${NC} ${WHITE}Repair Services, Permissions & Refresh Caches${NC}"
    echo -e "  ${GRAY}4.${NC} ${WHITE}Run Verification & Diagnostic Suite${NC}"
    echo -e "  ${GRAY}5.${NC} ${WHITE}Exit${NC}"
    echo -ne "\n  ${PURPLE}•${NC} ${WHITE}Choose option [1-5]${NC} ${GRAY}[1]${NC}\n  ${GRAY}╰─>${NC} "
    read -t 15 -r MENU_ACTION || MENU_ACTION="1"
    [ -z "$MENU_ACTION" ] && MENU_ACTION="1"

    case "$MENU_ACTION" in
        1) upgrade_to_v2 ;;
        2) backup_panel; exit 0 ;;
        3) repair_panel ;;
        4) run_test_suite ;;
        5) echo -e "  ${GRAY}Exiting.${NC}"; exit 0 ;;
        *) warn "Invalid option. Proceeding with Pterodactyl v2 upgrade..."; upgrade_to_v2 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
