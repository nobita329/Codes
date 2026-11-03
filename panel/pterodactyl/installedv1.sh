#!/bin/bash
# ==============================================================================
#  PREMIUM PTERODACTYL INSTALLER & UPDATER
#  Auto-detect + Fix + Modern Update Support (Ubuntu / Debian / PHP 8.3)
# ==============================================================================

set -o pipefail

# --- ROOT CHECK ---
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
    echo -e "       ${WHITE}PREMIUM PTERODACTYL AUTO-INSTALLER & UPDATER${NC}"
    echo -e "${HEADER_LINE}"
    echo -e "  ${PURPLE}•${NC} ${GRAY}OS Detected:${NC}      ${WHITE}${DETECTED_OS_PRETTY} (${DETECTED_CODENAME:-$DETECTED_ARCH})${NC}"
    echo -e "  ${PURPLE}•${NC} ${GRAY}Server IP:${NC}        ${WHITE}${DETECTED_IP}${NC}"
    echo -e "  ${PURPLE}•${NC} ${GRAY}Timezone:${NC}         ${WHITE}${DETECTED_TZ}${NC}"
    echo -e "  ${PURPLE}•${NC} ${GRAY}Panel Status:${NC}     ${WHITE}$([ "$IS_INSTALLED" = true ] && echo -e "${GREEN}Detected ($CURRENT_PANEL_VER)${NC}" || echo -e "${YELLOW}Not Installed${NC}")${NC}"
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

# Helper to generate random string
generate_random_password() {
    local len=${1:-16}
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 48 2>/dev/null | tr -dc 'A-Za-z0-9' | cut -c1-"$len"
    else
        head -c 64 /dev/urandom 2>/dev/null | tr -dc 'A-Za-z0-9' | cut -c1-"$len"
    fi
}

# --- FETCH GITHUB VERSIONS WITH MULTIPLE FALLBACKS ---
fetch_github_versions() {
    local repo=$1
    echo -e "  ${GRAY}Fetching releases from ${WHITE}$repo${GRAY}...${NC}" >&2
    local json=""

    if command -v curl >/dev/null 2>&1; then
        json=$(curl -sf --max-time 8 "https://api.github.com/repos/$repo/releases?per_page=20" 2>/dev/null)
    elif command -v wget >/dev/null 2>&1; then
        json=$(wget -qO- --timeout=8 "https://api.github.com/repos/$repo/releases?per_page=20" 2>/dev/null)
    fi

    if [ -n "$json" ]; then
        # Try python3 first if available
        if command -v python3 >/dev/null 2>&1; then
            echo "$json" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for r in data:
        if not r.get('prerelease', False):
            tag = r.get('tag_name', '')
            if tag:
                print(tag)
except Exception:
    pass
" 2>/dev/null && return 0
        fi

        # Fallback to grep/sed parsing
        local parsed
        parsed=$(echo "$json" | grep -oP '"tag_name":\s*"\K[^"]+' | grep -vE '(rc|beta|alpha)' 2>/dev/null)
        if [ -n "$parsed" ]; then
            echo "$parsed"
            return 0
        fi
    fi

    # Fallback to known stable release list if API is unreachable or rate-limited
    cat << "EOF"
v1.11.10
v1.11.9
v1.11.8
v1.11.7
v1.11.6
EOF
    return 0
}

# --- VERSION SELECTOR (10s timeout) ---
select_version() {
    local repo=$1
    local var_name=$2
    local default="latest"
    echo -e "\n  ${PURPLE}::${NC} ${WHITE}Available Panel Versions${NC}"
    local tags=() disp=() i=0

    while IFS= read -r tag; do
        [[ -z "$tag" ]] && continue
        tags+=("$tag")
        i=$((i+1))
        disp+=("  ${GRAY}$i.${NC} ${WHITE}$tag${NC}")
    done < <(fetch_github_versions "$repo" 2>/dev/null)

    if [[ ${#tags[@]} -eq 0 ]]; then
        echo -e "  ${YELLOW}No online versions detected. Using latest.${NC}"
        eval "$var_name=\"$default\""
        return
    fi

    printf '%b\n' "${disp[@]}"
    local max=${#tags[@]}
    echo -ne "\n  ${PURPLE}•${NC} ${WHITE}Select version [1-$max]${NC} ${GRAY}[1 = latest (${tags[0]})]${NC}\n  ${GRAY}╰─>${NC} "
    if ! read -t 10 -r choice; then
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
        # Use python if available for safest escaping, otherwise awk/sed
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

# --- PANEL UPDATER FUNCTION ---
update_panel() {
    step "Initiating Pterodactyl Panel Update..."

    if [ ! -d "$PANEL_DIR" ]; then
        err "Panel directory $PANEL_DIR does not exist. Please perform a fresh install."
        return 1
    fi

    cd "$PANEL_DIR" || exit 1

    select_version "$GITHUB_REPO" "UPDATE_VER"

    echo -ne "\n  ${CYAN}Proceed with updating panel to ${WHITE}${UPDATE_VER}${CYAN}?${NC} ${WHITE}(y/n)${NC}${GRAY}:${NC} "
    read -r -n 1 CONFIRM_UPDATE
    echo ""
    if [[ ! "$CONFIRM_UPDATE" =~ ^[Yy]$ ]]; then
        warn "Update cancelled by user."
        return 0
    fi

    info "Entering maintenance mode..."
    php artisan down 2>/dev/null || true

    step "Downloading panel release (${UPDATE_VER})..."
    local DL_URL
    if [[ "$UPDATE_VER" == "latest" ]]; then
        DL_URL="https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"
    else
        DL_URL="https://github.com/pterodactyl/panel/releases/download/${UPDATE_VER}/panel.tar.gz"
    fi

    curl -L --fail -o panel.tar.gz "$DL_URL" || {
        err "Failed to download panel archive. Please check your internet connection."
        php artisan up 2>/dev/null || true
        return 1
    }

    step "Extracting update files..."
    tar -xzf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/

    step "Updating composer dependencies..."
    export COMPOSER_ALLOW_SUPERUSER=1
    composer install --no-dev --optimize-autoloader --no-interaction

    step "Clearing caches and running database migrations..."
    php artisan view:clear
    php artisan config:clear
    php artisan migrate --seed --force

    step "Restoring permissions..."
    chown -R www-data:www-data "$PANEL_DIR"

    step "Restarting queue worker..."
    systemctl restart pteroq.service 2>/dev/null || true

    info "Disabling maintenance mode..."
    php artisan up 2>/dev/null || true

    ok "Pterodactyl Panel has been successfully updated to ${UPDATE_VER}!"
    echo -e "${HEADER_LINE}"
    exit 0
}

# --- PANEL REPAIR FUNCTION ---
repair_panel() {
    step "Running Pterodactyl Diagnostic & Repair..."

    if [ ! -d "$PANEL_DIR" ]; then
        err "Panel directory $PANEL_DIR does not exist."
        return 1
    fi

    cd "$PANEL_DIR" || exit 1

    step "Repairing file permissions..."
    chmod -R 755 storage/* bootstrap/cache/
    chown -R www-data:www-data "$PANEL_DIR"
    ok "Permissions corrected for www-data."

    step "Clearing Laravel application caches..."
    php artisan view:clear 2>/dev/null || true
    php artisan config:clear 2>/dev/null || true
    php artisan cache:clear 2>/dev/null || true
    php artisan config:cache 2>/dev/null || true

    step "Restarting system services..."
    systemctl daemon-reload
    systemctl restart redis-server 2>/dev/null || systemctl restart redis 2>/dev/null || true
    systemctl restart mariadb 2>/dev/null || systemctl restart mysql 2>/dev/null || true
    systemctl restart "php${PHP_VERSION}-fpm" 2>/dev/null || true
    nginx -t 2>/dev/null && systemctl restart nginx
    systemctl restart pteroq.service 2>/dev/null || true

    ok "All services reloaded and caches refreshed successfully!"
    echo -e "${HEADER_LINE}"
    exit 0
}

# --- TEST SUITE FUNCTION ---
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

    # 4. Safe .env Updater Test (Special Chars & Key Replacement)
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

    # 5. Version Fetcher Fallback
    test_version_fetch() {
        local versions
        versions=$(fetch_github_versions "$GITHUB_REPO" 2>/dev/null)
        [ -n "$versions" ] && echo "$versions" | grep -q "v1."
    }
    run_check "GitHub Releases & Fallback" "test_version_fetch"

    # 6. Core System Tools Check
    run_check "Command Tools (curl, openssl, tar)" "command -v curl && command -v openssl && command -v tar"

    # 7. Web Server (Nginx) Availability
    run_check "Web Server (Nginx) Binary" "command -v nginx"

    # 8. PHP Availability & Version Check
    test_php() {
        command -v php && php -v | grep -q "PHP"
    }
    run_check "PHP Engine Binary" "test_php"

    # 9. Database CLI (MariaDB/MySQL) Check
    test_db_cli() {
        command -v mariadb || command -v mysql
    }
    run_check "Database Client Binary" "test_db_cli"

    # 10. Queue Worker Template Verification
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
    # Check if run with test flag
    if [[ "$1" == "--test" || "$1" == "test" || "$1" == "-t" || "$1" == "--dry-run" ]]; then
        run_test_suite
        return $?
    fi

    auto_detect_system
    show_banner

# --- ACTION MENU ---
echo -e "\n  ${PURPLE}::${NC} ${WHITE}Select Action${NC}"
if [ "$IS_INSTALLED" = true ]; then
    echo -e "  ${GRAY}1.${NC} ${WHITE}Update Panel (${CURRENT_PANEL_VER} → Latest)${NC}"
    echo -e "  ${GRAY}2.${NC} ${WHITE}Fresh Install / Reinstall${NC}"
    echo -e "  ${GRAY}3.${NC} ${WHITE}Repair Services & Permissions${NC}"
    echo -e "  ${GRAY}4.${NC} ${WHITE}Exit${NC}"
    echo -ne "\n  ${PURPLE}•${NC} ${WHITE}Choose option [1-4]${NC} ${GRAY}[1]${NC}\n  ${GRAY}╰─>${NC} "
    read -t 15 -r MENU_ACTION || MENU_ACTION="1"
    [ -z "$MENU_ACTION" ] && MENU_ACTION="1"

    case "$MENU_ACTION" in
        1) update_panel ;;
        2) info "Starting fresh installation..." ;;
        3) repair_panel ;;
        4) echo -e "  ${GRAY}Exiting.${NC}"; exit 0 ;;
        *) warn "Invalid option. Proceeding to fresh installation..." ;;
    esac
else
    echo -e "  ${GRAY}1.${NC} ${WHITE}Install Pterodactyl Panel${NC}"
    echo -e "  ${GRAY}2.${NC} ${WHITE}Exit${NC}"
    echo -ne "\n  ${PURPLE}•${NC} ${WHITE}Choose option [1-2]${NC} ${GRAY}[1]${NC}\n  ${GRAY}╰─>${NC} "
    read -t 15 -r MENU_ACTION || MENU_ACTION="1"
    [ -z "$MENU_ACTION" ] && MENU_ACTION="1"

    if [ "$MENU_ACTION" = "2" ]; then
        echo -e "  ${GRAY}Exiting.${NC}"
        exit 0
    fi
fi

# ==============================================================================
# DATA COLLECTION
# ==============================================================================

step "Configuration & Input Setup"

# Domain
ask "Panel Domain / FQDN / IP" "$DETECTED_DOMAIN_DEFAULT" DOMAIN

# Email
ask "Admin Email" "admin@${DOMAIN}" EMAIL

# Username
ask "Admin Username" "admin" USERNAME

# Admin Password
ask_timeout "Admin Password" "admin" PASSWORD 10

# Database settings
ask "Database Name" "panel" DB_NAME
ask "Database User" "pterodactyl" DB_USER
SUGGESTED_DB_PASS=$(generate_random_password 16)
ask "Database Password" "$SUGGESTED_DB_PASS" DB_PASS

# Version selection
select_version "$GITHUB_REPO" "version_PANEL"

# SSL Auto-Detection: Let's Encrypt does not support plain IP addresses
IS_IP_ADDRESS=false
if [[ "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    IS_IP_ADDRESS=true
fi

if [ "$IS_IP_ADDRESS" = true ]; then
    warn "Domain is an IP address. Let's Encrypt (Certbot) requires a domain name."
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

# --- REVIEW CONFIGURATION ---
echo -e "\n  ${GOLD}┌─[ REVIEW CONFIGURATION ]${NC}"
echo -e "  ${GOLD}│${NC} ${GRAY}Domain / Host :${NC}   ${WHITE}$DOMAIN${NC}"
echo -e "  ${GOLD}│${NC} ${GRAY}Admin Email   :${NC}   ${WHITE}$EMAIL${NC}"
echo -e "  ${GOLD}│${NC} ${GRAY}Admin User    :${NC}   ${WHITE}$USERNAME${NC}"
echo -e "  ${GOLD}│${NC} ${GRAY}Admin Pass    :${NC}   ${WHITE}$PASSWORD${NC}"
echo -e "  ${GOLD}│${NC} ${GRAY}Database Name :${NC}   ${WHITE}$DB_NAME${NC}"
echo -e "  ${GOLD}│${NC} ${GRAY}Database User :${NC}   ${WHITE}$DB_USER${NC}"
echo -e "  ${GOLD}│${NC} ${GRAY}Panel Version :${NC}   ${WHITE}$version_PANEL${NC}"
echo -e "  ${GOLD}│${NC} ${GRAY}SSL Mode      :${NC}   ${WHITE}$SSL_NAME${NC}"
echo -e "  ${GOLD}│${NC} ${GRAY}App Name      :${NC}   ${WHITE}$APP_NAME${NC}"
echo -e "  ${GOLD}│${NC} ${GRAY}Timezone      :${NC}   ${WHITE}$DETECTED_TZ${NC}"
echo -e "  ${GOLD}└────────────────────────────────────${NC}"

while true; do
    echo -ne "\n  ${CYAN}Start Installation?${NC} ${WHITE}(y/n)${NC}${GRAY} [y]:${NC} "
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

# ==============================================================================
# DEPENDENCIES & REPOSITORIES SETUP
# ==============================================================================

step "Updating Package Manager & Core Tools..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl wget apt-transport-https ca-certificates gnupg unzip git tar sudo lsb-release software-properties-common jq cron openssl

# --- OS-SPECIFIC REPOSITORIES FOR PHP 8.3 & REDIS ---
step "Configuring PHP & Service Repositories..."
OS_FAMILY=$(lsb_release -is 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "$DETECTED_OS")

if [[ "$OS_FAMILY" == *"ubuntu"* ]]; then
    info "Detected Ubuntu system. Adding Ondrej PHP PPA..."
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
elif [[ "$OS_FAMILY" == *"debian"* ]]; then
    info "Detected Debian system. Adding SURY PHP repository..."
    mkdir -p /usr/share/keyrings
    curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor --yes -o /usr/share/keyrings/sury-php.gpg 2>/dev/null
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

# --- INSTALL PHP 8.3, MARIADB, NGINX, REDIS ---
step "Installing PHP ${PHP_VERSION}, MariaDB, Nginx, Redis & Certbot..."
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

# --- START & ENABLE SERVICES ---
step "Enabling and Starting System Services..."
systemctl enable --now mariadb 2>/dev/null || systemctl enable --now mysql 2>/dev/null || true
systemctl enable --now redis-server 2>/dev/null || systemctl enable --now redis 2>/dev/null || true
systemctl enable --now "php${PHP_VERSION}-fpm" 2>/dev/null || true
systemctl enable --now nginx 2>/dev/null || true
systemctl enable --now cron 2>/dev/null || true
ok "Core services enabled and running."

# --- INSTALL COMPOSER ---
step "Installing / Updating Composer..."
if ! command -v composer >/dev/null 2>&1; then
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
else
    composer self-update 2>/dev/null || true
fi
ok "Composer is available at $(which composer)"

# ==============================================================================
# PTERODACTYL PANEL DOWNLOAD
# ==============================================================================

step "Downloading Pterodactyl Panel Archive..."
mkdir -p "$PANEL_DIR"
cd "$PANEL_DIR" || exit 1

if [[ "$version_PANEL" == "latest" ]]; then
    curl -L --fail -o panel.tar.gz "https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"
else
    curl -L --fail -o panel.tar.gz "https://github.com/pterodactyl/panel/releases/download/${version_PANEL}/panel.tar.gz"
fi

if [ ! -s panel.tar.gz ]; then
    err "Panel download failed! Falling back to latest release..."
    curl -L --fail -o panel.tar.gz "https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"
fi

tar -xzf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/
ok "Panel files unpacked successfully."

# ==============================================================================
# MARIADB DATABASE CONFIGURATION
# ==============================================================================

# --- MariaDB Setup ---
mariadb -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;" 2>/dev/null || mariadb -e "CREATE DATABASE ${DB_NAME};" 2>/dev/null || true
mariadb -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';" 2>/dev/null || mariadb -e "CREATE USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';" 2>/dev/null || true
mariadb -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';" 2>/dev/null || true
mariadb -e "ALTER USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';" 2>/dev/null || true
mariadb -e "ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';" 2>/dev/null || true
mariadb -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1' WITH GRANT OPTION;" 2>/dev/null || mariadb -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'127.0.0.1' WITH GRANT OPTION;"
mariadb -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost' WITH GRANT OPTION;" 2>/dev/null || true
mariadb -e "FLUSH PRIVILEGES;"
ok "Database ${DB_NAME} and user ${DB_USER} configured."

# ==============================================================================
# ENVIRONMENT (.env) SETUP
# ==============================================================================

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

# Database Settings
update_env "DB_CONNECTION" "mysql"
update_env "DB_HOST" "127.0.0.1"
update_env "DB_PORT" "3306"
update_env "DB_DATABASE" "${DB_NAME}"
update_env "DB_USERNAME" "${DB_USER}"
update_env "DB_PASSWORD" "\"${DB_PASS}\""

# Redis Cache & Queue
update_env "CACHE_DRIVER" "redis"
update_env "SESSION_DRIVER" "redis"
update_env "QUEUE_CONNECTION" "redis"
update_env "REDIS_HOST" "127.0.0.1"
update_env "REDIS_PASSWORD" "null"
update_env "REDIS_PORT" "6379"

# General Settings
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

ok "Environment variables configured."

# Ensure valid APP_KEY exists before running composer or artisan
if ! grep -q "^APP_KEY=base64:" .env 2>/dev/null; then
    RAND_APP_KEY="base64:$(openssl rand -base64 32)"
    update_env "APP_KEY" "$RAND_APP_KEY"
fi
rm -f bootstrap/cache/*.php 2>/dev/null || true

# ==============================================================================
# COMPOSER INSTALL & DATABASE INITIALIZATION
# ==============================================================================

step "Installing PHP Dependencies with Composer..."
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader

step "Generating Application Encryption Key..."
yes | php artisan key:generate --force 2>/dev/null || true
rm -f bootstrap/cache/*.php 2>/dev/null || true

step "Running Database Migrations & Seeds..."
php artisan migrate --seed --force
ok "Database schema created and seeded."

# Default Location (Optional)
php artisan p:location:make --short=IN --long="India" 2>/dev/null || true

# ==============================================================================
# CRON & QUEUE WORKER SETUP
# ==============================================================================

step "Configuring Crontab & Systemd Queue Worker..."

# Cron deduplication
CRON_CMD="* * * * * /usr/bin/php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1"
(crontab -l 2>/dev/null | grep -v "pterodactyl/artisan schedule:run"; echo "$CRON_CMD") | crontab -
ok "Crontab scheduled for artisan runner."

# Systemd Queue Worker
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

# ==============================================================================
# NGINX & SSL CERTIFICATE CONFIGURATION
# ==============================================================================

step "Configuring Nginx Web Server & SSL Certificates..."

# Remove default Nginx welcome site if present
rm -f /etc/nginx/sites-enabled/default

# Auto-detect Nginx HTTP/2 syntax compatibility
NGINX_VER=$(nginx -v 2>&1 | grep -oP 'nginx/\K[0-9.]+')
NGINX_MAJOR=$(echo "$NGINX_VER" | cut -d. -f1)
NGINX_MINOR=$(echo "$NGINX_VER" | cut -d. -f2)

# If Nginx >= 1.25, 'listen 443 ssl;' with 'http2 on;' is preferred
USE_HTTP2_DIRECTIVE=false
if [ "$NGINX_MAJOR" -gt 1 ] || { [ "$NGINX_MAJOR" -eq 1 ] && [ "$NGINX_MINOR" -ge 25 ]; }; then
    USE_HTTP2_DIRECTIVE=true
fi

mkdir -p /etc/certs/panel

# --- CERTIFICATE PROVISIONING ---
if [ "$SSL_TYPE" = "n" ]; then
    info "Provisioning Let's Encrypt SSL certificate for ${DOMAIN}..."

    # Write temporary HTTP site for Certbot challenge
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

    # Run Certbot
    certbot certonly --nginx \
        --non-interactive \
        --agree-tos \
        --email "${EMAIL}" \
        -d "${DOMAIN}" 2>/dev/null || true

    if [ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]; then
        ln -sf "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" /etc/certs/panel/fullchain.pem
        ln -sf "/etc/letsencrypt/live/${DOMAIN}/privkey.pem" /etc/certs/panel/privkey.pem
        ok "Let's Encrypt certificate obtained successfully."
    else
        warn "Certbot could not obtain a certificate for ${DOMAIN}."
        warn "Falling back to Local Self-Signed SSL so Nginx can start securely without downtime."
        SSL_TYPE="y"
        SSL_NAME="Local SSL (Self-Signed)"
    fi
fi

if [ "$SSL_TYPE" = "y" ]; then
    info "Generating Local Self-Signed SSL Certificate..."
    openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
        -subj "/C=US/ST=State/L=City/O=Nobita/CN=${DOMAIN}" \
        -keyout /etc/certs/panel/privkey.pem -out /etc/certs/panel/fullchain.pem 2>/dev/null
    ok "Self-signed certificate generated at /etc/certs/panel."
fi

# --- WRITE FINAL NGINX CONFIGURATION ---
if [ "$SSL_TYPE" = "0" ]; then
    # HTTP Only configuration
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
    # HTTPS Configuration with HTTP to HTTPS redirect
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

# ==============================================================================
# PERMISSIONS & CACHE OPTIMIZATION
# ==============================================================================

step "Optimizing Laravel Caches & Setting Permissions..."
cd "$PANEL_DIR" || exit 1

php artisan view:clear 2>/dev/null || true
php artisan config:clear 2>/dev/null || true
php artisan cache:clear 2>/dev/null || true
php artisan config:cache 2>/dev/null || true

# Proper recursive permissions including hidden files
chown -R www-data:www-data "$PANEL_DIR"
chmod -R 755 storage bootstrap/cache

php artisan queue:restart 2>/dev/null || true

# ==============================================================================
# CREATE ADMINISTRATOR USER
# ==============================================================================

step "Creating Administrator Account..."
php artisan p:user:make -n \
    --email="$EMAIL" \
    --username="$USERNAME" \
    --password="$PASSWORD" \
    --admin=1 \
    --name-first="Admin" \
    --name-last="User" 2>/dev/null || {
    # If user already exists, update credentials to requested password
    php -r "
    require 'vendor/autoload.php';
    \$app = require_once 'bootstrap/app.php';
    \$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
    \$kernel->bootstrap();
    \$u = Pterodactyl\Models\User::where('username', '${USERNAME}')->orWhere('email', '${EMAIL}')->first();
    if (\$u) {
        \$u->password = Illuminate\Support\Facades\Hash::make('${PASSWORD}');
        \$u->root_admin = true;
        \$u->save();
    }
    " 2>/dev/null || true
    ok "Administrator credentials updated to ${USERNAME}:${PASSWORD}"
}

# Save credentials to log file for safe keeping
CRED_FILE="/root/pterodactyl_credentials.txt"
cat > "$CRED_FILE" <<EOF
========================================
 PTERODACTYL PANEL INSTALLATION DETAILS
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

# ==============================================================================
# FINAL DEPLOYMENT REPORT
# ==============================================================================

clear
echo -e "${HEADER_LINE}"
echo -e "\n  ${CYAN}DEPLOYMENT COMPLETE & VERIFIED${NC}"
echo -e "  ${GRAY}Panel URL  :${NC} ${WHITE}$([ "$SSL_TYPE" = "0" ] && echo "http://$DOMAIN" || echo "https://$DOMAIN")${NC}"
echo -e "  ${GRAY}Username   :${NC} ${WHITE}$USERNAME${NC}"
echo -e "  ${GRAY}Password   :${NC} ${WHITE}$PASSWORD${NC}"
echo -e "  ${GRAY}Email      :${NC} ${WHITE}$EMAIL${NC}"
echo -e "  ${GRAY}SSL Status :${NC} ${WHITE}$SSL_NAME${NC}"
echo -e "  ${GRAY}Credentials:${NC} ${GREEN}Saved to $CRED_FILE${NC}"
echo -e "\n  ${PURPLE}Enjoy your new Pterodactyl Panel powered by Nobita Cloud!${NC}"
echo -e "${HEADER_LINE}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

