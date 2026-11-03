#!/bin/bash

# ==============================================================================
#       PTERODACTYL v2.0 CONTROL CENTER (Nobita Edition)
#       Panel v2 Management + Service Control + Safe v2 Updater + User Manager
# ==============================================================================

set -o pipefail

# --- ROOT CHECK ---
if [ "$EUID" -ne 0 ]; then
    echo -e "\033[0;31m[ERROR]\033[0m This script must be run as root! Please use: sudo bash $0"
    exit 1
fi

# --- COLORS & STYLING ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
BOLD='\033[1m'
GOLD='\033[38;5;214m'
NC='\033[0m'
BORDER_LINE="${PURPLE}════════════════════════════════════════════════════════════${NC}"
HEADER_LINE="${GRAY}────────────────────────────────────────────────────────────${NC}"

PANEL_DIR="/var/www/pterodactyl"
PHP_VERSION="8.3"
GITHUB_REPO="pterodactyl/panel"
BACKUP_BASE_DIR="/var/backups/pterodactyl"

# --- UI HELPER FUNCTIONS ---
show_header() {
    clear
    echo -e "$BORDER_LINE"
    echo -e "${PURPLE}║${NC}       ${BOLD}${CYAN}⚡ PTERODACTYL v2.0 CONTROL CENTER ⚡${NC}        ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}         ${GRAY}Laravel 13 • React 19 • Vite • Tailwind 4${NC}          ${PURPLE}║${NC}"
    echo -e "$BORDER_LINE"
    echo -e "${CYAN}  Current Module: ${YELLOW}$1${NC}"
    echo -e "$HEADER_LINE"
    echo ""
}

status_msg() {
    # $1 = Type (OK, ERR, INFO, WAIT, WARN), $2 = Message
    case $1 in
        "OK")   echo -e "  [${GREEN} ✔ ${NC}] $2" ;;
        "ERR")  echo -e "  [${RED} ✘ ${NC}] $2" ;;
        "INFO") echo -e "  [${CYAN} ➜ ${NC}] $2" ;;
        "WAIT") echo -e "  [${YELLOW} ⏳ ${NC}] $2" ;;
        "WARN") echo -e "  [${GOLD} ⚠ ${NC}] $2" ;;
    esac
}

pause() {
    echo ""
    read -r -p "  Press [Enter] to return to main menu..."
}

# --- SYSTEM AUTO-DETECTION ---
detect_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        SYS_OS="${PRETTY_NAME:-$ID}"
        SYS_CODENAME="${VERSION_CODENAME:-}"
    else
        SYS_OS="Linux"
        SYS_CODENAME=""
    fi

    # Detect Server Public IP
    SYS_IP=""
    if command -v curl >/dev/null 2>&1; then
        SYS_IP=$(curl -4s --max-time 2 https://api.ipify.org 2>/dev/null || curl -4s --max-time 2 https://ifconfig.me 2>/dev/null)
    fi
    if [ -z "$SYS_IP" ]; then
        SYS_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    [ -z "$SYS_IP" ] && SYS_IP="127.0.0.1"

    # Detect Panel Status and Version
    PANEL_INSTALLED=false
    PANEL_VER="Not Installed"
    if [ -d "$PANEL_DIR" ] && [ -f "$PANEL_DIR/.env" ]; then
        PANEL_INSTALLED=true
        if [ -f "$PANEL_DIR/config/app.php" ]; then
            PANEL_VER=$(grep -oP "'version'\s*=>\s*'\K[^']+" "$PANEL_DIR/config/app.php" 2>/dev/null || echo "v2.0 Installed")
        else
            PANEL_VER="v2.0 Installed"
        fi
    fi

    # Detect active PHP version
    DETECTED_PHP=$(php -v 2>/dev/null | head -n 1 | awk '{print $2}' | cut -d'.' -f1,2)
    [ -n "$DETECTED_PHP" ] && PHP_VERSION="$DETECTED_PHP"
}

check_service_status() {
    local svc=$1
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo -e "${GREEN}Running${NC}"
    elif service "$svc" status >/dev/null 2>&1; then
        echo -e "${GREEN}Running${NC}"
    elif pgrep -f "$svc" >/dev/null 2>&1; then
        echo -e "${GREEN}Running${NC}"
    else
        echo -e "${RED}Stopped${NC}"
    fi
}

# --- FETCH PTERODACTYL v2 RELEASES ---
fetch_github_versions() {
    local repo=$1
    local json=""

    if command -v curl >/dev/null 2>&1; then
        json=$(curl -sf --max-time 8 "https://api.github.com/repos/$repo/releases?per_page=30" 2>/dev/null)
    fi

    if [ -n "$json" ]; then
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

# ==============================================================================
# 1. INSTALL FUNCTION (PTERODACTYL v2)
# ==============================================================================
install_ptero() {
    show_header "PANEL v2 INSTALLATION"

    if [ -f "/root/a.sh" ]; then
        status_msg "INFO" "Executing dedicated Pterodactyl v2 installer (/root/a.sh --install)..."
        sleep 1
        bash /root/a.sh --install
    else
        status_msg "INFO" "Fetching official Nobita Cloud Pterodactyl v2 installer..."
        sleep 1
        bash <(curl -fsSL https://raw.githubusercontent.com/nobita329/Codes/raw/refs/heads/main/panel/pterodactyl/installv2.sh)
    fi

    echo ""
    status_msg "OK" "Installation Sequence Complete."
    pause
}

# ==============================================================================
# 2. USER MANAGEMENT (FIXED >= 8 CHARS FOR PTERODACTYL v2)
# ==============================================================================
create_user() {
    show_header "USER MANAGEMENT (v2 COMPLIANT)"

    if [ ! -d "$PANEL_DIR" ] || [ ! -f "$PANEL_DIR/.env" ]; then
        status_msg "ERR" "Panel directory or .env not found ($PANEL_DIR)."
        status_msg "ERR" "Please install Pterodactyl v2 first."
        pause
        return
    fi

    cd "$PANEL_DIR" || return
    chmod -R 775 storage bootstrap/cache 2>/dev/null || true
    chown -R www-data:www-data "$PANEL_DIR" 2>/dev/null || true

    echo -e "  ${CYAN}[1]${NC} Quick Admin User ${GRAY}(admin / Admin@12345)${NC}"
    echo -e "  ${CYAN}[2]${NC} Custom Admin User ${GRAY}(Interactive Prompts • min 8 chars)${NC}"
    echo -e "  ${CYAN}[3]${NC} Random Admin User ${GRAY}(Auto-generated strong password)${NC}"
    echo -e "  ${CYAN}[4]${NC} Reset Existing User Password ${GRAY}(min 8 chars)${NC}"
    echo -e "  ${GRAY}[0]${NC} Return to Menu"
    echo ""
    read -r -p "  Choose option [1-4]: " choice

    case "$choice" in
        1)
            # Quick admin with valid 8+ character password
            local QUICK_PASS="Admin@12345"
            local QUICK_EMAIL="admin@panel.nobitahost.in"
            local QUICK_USER="admin"

            status_msg "WAIT" "Creating/Updating admin account (${QUICK_USER}:${QUICK_PASS})..."
            
            php artisan p:user:make -n \
                --email="$QUICK_EMAIL" \
                --username="$QUICK_USER" \
                --password="$QUICK_PASS" \
                --admin=1 \
                --name-first="Admin" \
                --name-last="User" 2>/dev/null || {
                # Fallback to direct model creation/update
                php -r "
                require 'vendor/autoload.php';
                \$app = require_once 'bootstrap/app.php';
                \$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
                \$kernel->bootstrap();
                \$u = Pterodactyl\Models\User::firstOrNew(['username' => '${QUICK_USER}']);
                \$u->email = '${QUICK_EMAIL}';
                \$u->name_first = 'Admin';
                \$u->name_last = 'User';
                \$u->password = Illuminate\Support\Facades\Hash::make('${QUICK_PASS}');
                \$u->root_admin = true;
                \$u->save();
                " 2>/dev/null || true
            }

            echo ""
            status_msg "OK" "Administrator account is ready!"
            echo -e "  ${WHITE}Username :${NC} ${GREEN}${QUICK_USER}${NC}"
            echo -e "  ${WHITE}Password :${NC} ${GREEN}${QUICK_PASS}${NC} ${GRAY}(Meets Pterodactyl v2 8+ char rule)${NC}"
            echo -e "  ${WHITE}Email    :${NC} ${WHITE}${QUICK_EMAIL}${NC}"
            ;;

        2)
            status_msg "WAIT" "Launching custom user creation..."
            echo ""
            read -r -p "  Enter Email: " C_EMAIL
            read -r -p "  Enter Username: " C_USER
            read -r -p "  Enter First Name [Admin]: " C_FIRST
            [ -z "$C_FIRST" ] && C_FIRST="Admin"
            read -r -p "  Enter Last Name [User]: " C_LAST
            [ -z "$C_LAST" ] && C_LAST="User"

            while true; do
                read -r -p "  Enter Password (min 8 chars): " C_PASS
                if [ ${#C_PASS} -ge 8 ]; then
                    break
                else
                    echo -e "  ${RED}[FAIL] The password must be at least 8 characters! Current: ${#C_PASS}${NC}"
                fi
            done

            read -r -p "  Make Administrator? (y/n) [y]: " IS_ADM
            local ADM_FLAG=1
            [[ "$IS_ADM" =~ ^[Nn]$ ]] && ADM_FLAG=0

            php artisan p:user:make -n \
                --email="$C_EMAIL" \
                --username="$C_USER" \
                --password="$C_PASS" \
                --admin="$ADM_FLAG" \
                --name-first="$C_FIRST" \
                --name-last="$C_LAST" || {
                php -r "
                require 'vendor/autoload.php';
                \$app = require_once 'bootstrap/app.php';
                \$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
                \$kernel->bootstrap();
                \$u = Pterodactyl\Models\User::firstOrNew(['username' => '${C_USER}']);
                \$u->email = '${C_EMAIL}';
                \$u->name_first = '${C_FIRST}';
                \$u->name_last = '${C_LAST}';
                \$u->password = Illuminate\Support\Facades\Hash::make('${C_PASS}');
                \$u->root_admin = ($ADM_FLAG === 1);
                \$u->save();
                " 2>/dev/null || true
            }
            status_msg "OK" "User '$C_USER' created successfully."
            ;;

        3)
            status_msg "WAIT" "Generating random administrator..."
            RAND_USER="admin_$(openssl rand -hex 2)"
            RAND_PASS="Adm@$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 12)"
            RAND_EMAIL="${RAND_USER}@panel.local"

            php artisan p:user:make -n \
                --email="${RAND_EMAIL}" \
                --username="${RAND_USER}" \
                --password="${RAND_PASS}" \
                --admin=1 \
                --name-first="Admin" \
                --name-last="Auto" || {
                php -r "
                require 'vendor/autoload.php';
                \$app = require_once 'bootstrap/app.php';
                \$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
                \$kernel->bootstrap();
                \$u = Pterodactyl\Models\User::firstOrNew(['username' => '${RAND_USER}']);
                \$u->email = '${RAND_EMAIL}';
                \$u->name_first = 'Admin';
                \$u->name_last = 'Auto';
                \$u->password = Illuminate\Support\Facades\Hash::make('${RAND_PASS}');
                \$u->root_admin = true;
                \$u->save();
                " 2>/dev/null || true
            }

            echo ""
            status_msg "OK" "Random Administrator Created!"
            echo -e "  ${WHITE}Username :${NC} ${GREEN}$RAND_USER${NC}"
            echo -e "  ${WHITE}Password :${NC} ${GREEN}$RAND_PASS${NC}"
            echo -e "  ${WHITE}Email    :${NC} ${WHITE}$RAND_EMAIL${NC}"
            ;;

        4)
            echo ""
            read -r -p "  Enter Username or Email to reset: " TARGET_USER
            while true; do
                read -r -p "  Enter New Password (min 8 chars): " NEW_PW
                if [ ${#NEW_PW} -ge 8 ]; then
                    break
                else
                    echo -e "  ${RED}[FAIL] The password must be at least 8 characters! Current: ${#NEW_PW}${NC}"
                fi
            done

            if [ -n "$TARGET_USER" ] && [ -n "$NEW_PW" ]; then
                php -r "
                require 'vendor/autoload.php';
                \$app = require_once 'bootstrap/app.php';
                \$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
                \$kernel->bootstrap();
                \$u = Pterodactyl\Models\User::where('username', '${TARGET_USER}')->orWhere('email', '${TARGET_USER}')->first();
                if (\$u) {
                    \$u->password = Illuminate\Support\Facades\Hash::make('${NEW_PW}');
                    \$u->save();
                    echo 'SUCCESS';
                } else {
                    echo 'NOT_FOUND';
                }
                " 2>/dev/null | grep -q "SUCCESS" && {
                    status_msg "OK" "Password updated successfully for $TARGET_USER!"
                } || {
                    status_msg "ERR" "User not found or update failed."
                }
            fi
            ;;

        0)
            return
            ;;

        *)
            status_msg "ERR" "Invalid option."
            ;;
    esac

    pause
}

# ==============================================================================
# 3. PTERODACTYL v2 FULL UPDATE & MIGRATION ENGINE
# ==============================================================================
update_panel() {
    show_header "PTERODACTYL v2 FULL UPDATE"

    if [ ! -d "$PANEL_DIR" ] || [ ! -f "$PANEL_DIR/.env" ]; then
        status_msg "ERR" "Panel not found in $PANEL_DIR"
        pause
        return
    fi

    echo -e "  ${WHITE}Fetching Pterodactyl v2 releases from GitHub...${NC}"
    local tags=() i=0
    while IFS= read -r tag; do
        [[ -z "$tag" ]] && continue
        tags+=("$tag")
        i=$((i+1))
        echo -e "  ${GRAY}$i.${NC} ${CYAN}$tag${NC} ${GRAY}(Pterodactyl v2 Next-Gen)${NC}"
    done < <(fetch_github_versions "$GITHUB_REPO" 2>/dev/null)

    local max=${#tags[@]}
    local default_tag="v2.0.0-beta.2"
    [ $max -gt 0 ] && default_tag="${tags[0]}"

    echo ""
    echo -ne "  ${CYAN}Select version [1-$max] or type custom tag${NC} ${GRAY}[1 = latest ($default_tag)]${NC}: "
    read -r -t 15 choice || choice="1"
    [ -z "$choice" ] && choice="1"

    local SELECTED_TAG="$default_tag"
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$max" ]; then
        SELECTED_TAG="${tags[$((choice - 1))]}"
    elif [[ -n "$choice" && "$choice" != "1" ]]; then
        SELECTED_TAG="$choice"
    fi

    echo ""
    echo -ne "  ${CYAN}Upgrade panel to Pterodactyl ${WHITE}${SELECTED_TAG}${CYAN}?${NC} ${WHITE}(y/n)${NC} [y]: "
    read -r -t 10 CONFIRM_UPDATE || CONFIRM_UPDATE="y"
    [ -z "$CONFIRM_UPDATE" ] && CONFIRM_UPDATE="y"

    if [[ ! "$CONFIRM_UPDATE" =~ ^[Yy]$ ]]; then
        status_msg "INFO" "Update cancelled by user."
        pause
        return
    fi

    # Ensure php-intl and dependencies
    status_msg "WAIT" "Checking PHP 8.3 & required v2 extensions (intl, bcmath)..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y 2>/dev/null || true
    apt-get install -y "php${PHP_VERSION}-intl" "php${PHP_VERSION}-bcmath" "php${PHP_VERSION}-mbstring" "php${PHP_VERSION}-xml" "php${PHP_VERSION}-zip" "php${PHP_VERSION}-curl" "php${PHP_VERSION}-gd" "php${PHP_VERSION}-mysql" redis-server tar curl composer 2>/dev/null || true

    # Create safety backup
    status_msg "WAIT" "Creating safety backup before v2 upgrade..."
    mkdir -p "$BACKUP_BASE_DIR"
    local TS
    TS=$(date +%Y%m%d_%H%M%S)
    cp "$PANEL_DIR/.env" "$BACKUP_BASE_DIR/.env.pre-v2_${TS}" 2>/dev/null || true
    tar --exclude='./storage/logs/*.log' -czf "$BACKUP_BASE_DIR/panel_files_${TS}.tar.gz" -C "$PANEL_DIR" . 2>/dev/null || true
    status_msg "OK" "Pre-upgrade backup saved to $BACKUP_BASE_DIR"

    cd "$PANEL_DIR" || return

    status_msg "WAIT" "Entering maintenance mode..."
    php artisan down 2>/dev/null || touch storage/framework/down 2>/dev/null || true

    status_msg "WAIT" "Downloading Pterodactyl v2 release (${SELECTED_TAG})..."
    local DL_URL="https://github.com/pterodactyl/panel/releases/download/${SELECTED_TAG}/panel.tar.gz"
    local TMP_TAR="/tmp/pterodactyl_v2_${SELECTED_TAG}.tar.gz"

    curl -L --fail -o "$TMP_TAR" "$DL_URL" || {
        status_msg "WARN" "Download failed for $DL_URL. Falling back to v2.0.0-beta.2..."
        curl -L --fail -o "$TMP_TAR" "https://github.com/pterodactyl/panel/releases/download/v2.0.0-beta.2/panel.tar.gz" || {
            status_msg "ERR" "Failed to download Pterodactyl v2 archive."
            php artisan up 2>/dev/null || rm -f storage/framework/down 2>/dev/null || true
            pause
            return
        }
    }

    # Verify tar archive
    if ! tar -tzf "$TMP_TAR" >/dev/null 2>&1; then
        status_msg "ERR" "Downloaded archive is corrupted."
        rm -f "$TMP_TAR"
        php artisan up 2>/dev/null || true
        pause
        return
    fi

    status_msg "WAIT" "Preserving .env and clearing obsolete v1 Webpack/React 16 artifacts..."
    local M_ID
    M_ID=$(date +%s)
    cp "$PANEL_DIR/.env" "/tmp/env_${M_ID}"
    mkdir -p "/tmp/oauth_${M_ID}"
    cp -a "$PANEL_DIR/storage/oauth-"* "/tmp/oauth_${M_ID}/" 2>/dev/null || true

    # Clean old v1 directories
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

    status_msg "WAIT" "Extracting Pterodactyl v2 core files..."
    tar -xzf "$TMP_TAR" -C "$PANEL_DIR"
    rm -f "$TMP_TAR"

    # Restore .env and OAuth
    cp "/tmp/env_${M_ID}" "$PANEL_DIR/.env"
    cp -a "/tmp/oauth_${M_ID}/"* "$PANEL_DIR/storage/" 2>/dev/null || true
    rm -rf "/tmp/env_${M_ID}" "/tmp/oauth_${M_ID}"

    status_msg "WAIT" "Setting file permissions..."
    chmod -R 775 storage bootstrap/cache
    chown -R www-data:www-data "$PANEL_DIR"

    status_msg "WAIT" "Updating composer dependencies..."
    export COMPOSER_ALLOW_SUPERUSER=1
    composer install --no-dev --optimize-autoloader --no-interaction || {
        status_msg "WARN" "Retrying composer with platform flag..."
        composer install --no-dev --optimize-autoloader --no-interaction --ignore-platform-reqs 2>/dev/null || true
    }

    status_msg "WAIT" "Running database migrations & purging caches..."
    php artisan view:clear 2>/dev/null || true
    php artisan config:clear 2>/dev/null || true
    php artisan cache:clear 2>/dev/null || true
    php artisan route:clear 2>/dev/null || true
    php artisan migrate --seed --force
    php artisan config:cache 2>/dev/null || true
    php artisan view:cache 2>/dev/null || true

    status_msg "WAIT" "Restarting queue workers & system services..."
    systemctl daemon-reload 2>/dev/null || true
    systemctl restart pteroq.service 2>/dev/null || true
    systemctl restart "php${PHP_VERSION}-fpm" 2>/dev/null || true
    nginx -t 2>/dev/null && systemctl restart nginx 2>/dev/null || true

    status_msg "WAIT" "Disabling maintenance mode..."
    php artisan up 2>/dev/null || rm -f storage/framework/down 2>/dev/null || true

    echo ""
    status_msg "OK" "Panel Successfully Upgraded to Pterodactyl v2 (${SELECTED_TAG})!"
    pause
}

# ==============================================================================
# 4. DOMAIN & SSL CONFIGURATION
# ==============================================================================
domain_ssl_menu() {
    show_header "DOMAIN & SSL CONFIGURATION"

    echo -e "  ${CYAN}[1]${NC} Re-run SSL Setup (Local Self-Signed or Certbot)"
    echo -e "  ${CYAN}[2]${NC} Change Panel Domain / APP_URL"
    echo -e "  ${CYAN}[3]${NC} Run Remote SSL Script (Nobita Cloud)"
    echo -e "  ${GRAY}[0]${NC} Return to Menu"
    echo ""
    read -r -p "  Choose option [1-3]: " ssl_choice

    case "$ssl_choice" in
        1)
            read -r -p "  Enter Panel Domain (e.g. panel.example.com): " CUSTOM_DOMAIN
            if [ -n "$CUSTOM_DOMAIN" ]; then
                status_msg "WAIT" "Configuring SSL for $CUSTOM_DOMAIN..."
                mkdir -p /etc/certs/panel
                openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
                    -subj "/C=US/ST=State/L=City/O=Nobita/CN=${CUSTOM_DOMAIN}" \
                    -keyout /etc/certs/panel/privkey.pem -out /etc/certs/panel/fullchain.pem 2>/dev/null
                nginx -t && systemctl restart nginx
                status_msg "OK" "SSL Certificate updated and Nginx reloaded."
            fi
            ;;
        2)
            read -r -p "  Enter new Panel Domain: " NEW_DOM
            if [ -n "$NEW_DOM" ] && [ -f "$PANEL_DIR/.env" ]; then
                sed -i "s|^APP_URL=.*|APP_URL=https://${NEW_DOM}|g" "$PANEL_DIR/.env"
                sed -i "s|server_name .*;|server_name ${NEW_DOM};|g" /etc/nginx/sites-available/pterodactyl.conf 2>/dev/null || true
                nginx -t && systemctl restart nginx
                cd "$PANEL_DIR" && php artisan config:clear && php artisan config:cache 2>/dev/null || true
                status_msg "OK" "APP_URL updated to https://${NEW_DOM}."
            fi
            ;;
        3)
            bash <(curl -fsSL https://raw.githubusercontent.com/nobita329/Nobita-Cloud/refs/heads/main/panel/pterodactyl/ssl.sh)
            ;;
        *)
            return
            ;;
    esac
    pause
}

# ==============================================================================
# 5. SERVICE MANAGEMENT & REPAIR
# ==============================================================================
service_control() {
    show_header "SERVICE CONTROL & REPAIR"

    echo -e "  ${CYAN}[1]${NC} Restart All Services (Nginx, MariaDB, PHP-FPM, Redis, Queue)"
    echo -e "  ${CYAN}[2]${NC} Fix Permissions (chown www-data & chmod 775 storage)"
    echo -e "  ${CYAN}[3]${NC} Clear & Rebuild All Laravel v2 Caches"
    echo -e "  ${CYAN}[4]${NC} View System Logs"
    echo -e "  ${GRAY}[0]${NC} Return to Menu"
    echo ""
    read -r -p "  Choose option [1-4]: " s_choice

    case "$s_choice" in
        1)
            status_msg "WAIT" "Restarting services..."
            systemctl daemon-reload 2>/dev/null || true
            systemctl restart redis-server 2>/dev/null || systemctl restart redis 2>/dev/null || true
            systemctl restart mariadb 2>/dev/null || systemctl restart mysql 2>/dev/null || true
            systemctl restart "php${PHP_VERSION}-fpm" 2>/dev/null || true
            nginx -t 2>/dev/null && systemctl restart nginx 2>/dev/null || true
            systemctl restart pteroq.service 2>/dev/null || true
            status_msg "OK" "All services restarted."
            ;;
        2)
            status_msg "WAIT" "Repairing file permissions..."
            chmod -R 775 "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache" 2>/dev/null || true
            chown -R www-data:www-data "$PANEL_DIR" 2>/dev/null || true
            status_msg "OK" "Ownership set to www-data:www-data and storage chmod 775."
            ;;
        3)
            status_msg "WAIT" "Clearing and optimizing v2 caches..."
            cd "$PANEL_DIR" || return
            php artisan view:clear 2>/dev/null || true
            php artisan config:clear 2>/dev/null || true
            php artisan cache:clear 2>/dev/null || true
            php artisan route:clear 2>/dev/null || true
            php artisan config:cache 2>/dev/null || true
            php artisan queue:restart 2>/dev/null || true
            status_msg "OK" "Pterodactyl v2 caches refreshed."
            ;;
        4)
            echo ""
            tail -n 25 "$PANEL_DIR/storage/logs/laravel-"*.log 2>/dev/null || status_msg "INFO" "No logs found."
            ;;
        *)
            return
            ;;
    esac
    pause
}

# ==============================================================================
# 6. PHPMYADMIN
# ==============================================================================
phpmyadmin_menu() {
    show_header "PHPMYADMIN SETUP"
    status_msg "INFO" "Launching phpMyAdmin installer..."
    sleep 1
    bash <(curl -fsSL https://raw.githubusercontent.com/nobita329/Nobita-Cloud/refs/heads/main/panel/pterodactyl/phpMyAdmin.sh)
    pause
}

# ==============================================================================
# 7. VIEW CREDENTIALS
# ==============================================================================
view_credentials() {
    show_header "SAVED CREDENTIALS"
    if [ -f "/root/pterodactyl_credentials.txt" ]; then
        cat /root/pterodactyl_credentials.txt
    elif [ -f "$PANEL_DIR/.env" ]; then
        echo -e "  ${WHITE}Database Details from .env:${NC}"
        grep -E '^(DB_HOST|DB_DATABASE|DB_USERNAME|DB_PASSWORD|APP_URL)=' "$PANEL_DIR/.env"
    else
        status_msg "WARN" "No credentials file found."
    fi
    pause
}

# ==============================================================================
# 8. PANEL UNINSTALL
# ==============================================================================
uninstall_logic() {
    status_msg "WAIT" "Stopping Panel services..."
    systemctl stop pteroq.service 2>/dev/null || true
    systemctl disable pteroq.service 2>/dev/null || true
    rm -f /etc/systemd/system/pteroq.service
    systemctl daemon-reload 2>/dev/null || true

    status_msg "WAIT" "Removing cronjobs..."
    (crontab -l 2>/dev/null | grep -v 'pterodactyl/artisan schedule:run') | crontab - 2>/dev/null || true

    # Auto-detect DB credentials
    ENV_FILE="$PANEL_DIR/.env"
    DB_NAME="panel"
    DB_USER="pterodactyl"

    if [ -f "$ENV_FILE" ]; then
        DB_NAME=$(grep '^DB_DATABASE=' "$ENV_FILE" | cut -d'=' -f2- | tr -d '"')
        DB_USER=$(grep '^DB_USERNAME=' "$ENV_FILE" | cut -d'=' -f2- | tr -d '"')
        [ -z "$DB_NAME" ] && DB_NAME="panel"
        [ -z "$DB_USER" ] && DB_USER="pterodactyl"
    fi

    status_msg "WAIT" "Deleting panel files..."
    rm -rf "$PANEL_DIR"

    status_msg "WAIT" "Dropping database and user ($DB_NAME / $DB_USER)..."
    mariadb -e "DROP DATABASE IF EXISTS \`$DB_NAME\`;" 2>/dev/null || mysql -e "DROP DATABASE IF EXISTS \`$DB_NAME\`;" 2>/dev/null || true
    mariadb -e "DROP USER IF EXISTS '$DB_USER'@'127.0.0.1'; DROP USER IF EXISTS '$DB_USER'@'localhost';" 2>/dev/null || true
    mariadb -e "FLUSH PRIVILEGES;" 2>/dev/null || true

    status_msg "WAIT" "Cleaning Nginx configs..."
    rm -f /etc/nginx/sites-enabled/pterodactyl.conf
    rm -f /etc/nginx/sites-available/pterodactyl.conf
    nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null || true

    status_msg "WAIT" "Removing SSL certificates..."
    rm -rf /etc/certs/panel

    status_msg "OK" "Cleanup completed."
}

uninstall_ptero() {
    show_header "UNINSTALLATION"

    echo -e "${RED}WARNING:${NC} This will permanently remove the Pterodactyl Panel."
    echo ""
    echo "The following will be removed:"
    echo "  • Panel files ($PANEL_DIR)"
    echo "  • Database (auto-detected from .env)"
    echo "  • Database user (auto-detected from .env)"
    echo "  • Nginx configuration"
    echo "  • Cron jobs"
    echo "  • pteroq service"
    echo "  • SSL certificates"
    echo ""
    echo "Wings will NOT be removed."
    echo ""

    read -r -p "Are you sure you want to continue? (y/N): " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        status_msg "INFO" "Uninstallation cancelled."
        pause
        return
    fi

    echo ""
    uninstall_logic
    echo ""

    status_msg "OK" "Pterodactyl Panel has been successfully uninstalled."
    pause
}

# ==============================================================================
# MAIN MENU LOOP
# ==============================================================================
while true; do
    detect_system
    clear

    # Banner
    echo -e "${PURPLE}  ____  _                     _            _         _ ${NC}"
    echo -e "${PURPLE} |  _ \| |_ ___ _ __ ___   __| | __ _  ___| |_ _   _| |${NC}"
    echo -e "${PURPLE} | |_) | __/ _ \ '__/ _ \ / _\` |/ _\` |/ __| __| | | | |${NC}"
    echo -e "${PURPLE} |  __/| ||  __/ | | (_) | (_| | (_| | (__| |_| |_| | |${NC}"
    echo -e "${PURPLE} |_|    \__\___|_|  \___/ \__,_|\__,_|\___|\__|\__, |_|${NC}"
    echo -e "${PURPLE}                                               |___/   ${NC}"
    echo -e "       ${BOLD}${CYAN}⚡ PTERODACTYL v2.0 CONTROL CENTER ⚡${NC}"
    echo -e "${CYAN} ┌───────────────────────────────────────────────────────────┐${NC}"

    # System & Panel Status
    if [ "$PANEL_INSTALLED" = true ]; then
        echo -e "${CYAN} │${NC} ${WHITE}PANEL STATUS:${NC} ${GREEN}PTERODACTYL v2.0 INSTALLED ✔ (${PANEL_VER})${NC}"
    else
        echo -e "${CYAN} │${NC} ${WHITE}PANEL STATUS:${NC} ${RED}NOT INSTALLED ✘${NC}"
    fi
    echo -e "${CYAN} │${NC} ${GRAY}OS:${NC} ${WHITE}${SYS_OS}${NC}  ${GRAY}| IP:${NC} ${WHITE}${SYS_IP}${NC}"
    echo -e "${CYAN} │${NC} ${GRAY}Nginx:${NC} $(check_service_status nginx) ${GRAY}| MariaDB:${NC} $(check_service_status mariadb) ${GRAY}| PHP:${NC} $(check_service_status "php${PHP_VERSION}-fpm") ${GRAY}| Queue:${NC} $(check_service_status pteroq)"

    echo -e "${CYAN} ├───────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN} │${NC}                                                           ${CYAN}│${NC}"
    echo -e "${CYAN} │${NC}  ${GREEN}[1]${NC} Install v2      ${GRAY}:: (Full Fresh Pterodactyl v2.0 Install)${NC} ${CYAN}│${NC}"
    echo -e "${CYAN} │${NC}  ${GREEN}[2]${NC} User Manager    ${GRAY}:: (Create Admin / min 8 chars password)${NC} ${CYAN}│${NC}"
    echo -e "${CYAN} │${NC}  ${YELLOW}[3]${NC} Update to v2    ${GRAY}:: (Full v2.0 Safe Migration & Backup)${NC}   ${CYAN}│${NC}"
    echo -e "${CYAN} │${NC}  ${CYAN}[4]${NC} Domain & SSL    ${GRAY}:: (Change Domain / Reissue SSL)${NC}         ${CYAN}│${NC}"
    echo -e "${CYAN} │${NC}  ${CYAN}[5]${NC} Service Control ${GRAY}:: (Restart / Fix 775 Permissions)${NC}      ${CYAN}│${NC}"
    echo -e "${CYAN} │${NC}  ${BLUE}[6]${NC} phpMyAdmin      ${GRAY}:: (Install / Setup DB Tool)${NC}             ${CYAN}│${NC}"
    echo -e "${CYAN} │${NC}  ${GOLD}[7]${NC} Credentials     ${GRAY}:: (View Admin/DB Passwords)${NC}             ${CYAN}│${NC}"
    echo -e "${CYAN} │${NC}  ${RED}[8]${NC} Uninstall Panel ${GRAY}:: (Remove Panel & Database)${NC}             ${CYAN}│${NC}"
    echo -e "${CYAN} │${NC}                                                           ${CYAN}│${NC}"
    echo -e "${CYAN} │${NC}  ${WHITE}[0] Exit System${NC}                                               ${CYAN}│${NC}"
    echo -e "${CYAN} └───────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -ne "${BOLD}${WHITE}  root@ptero-v2:~# ${NC}"
    read -r choice

    case "$choice" in
        1) install_ptero ;;
        2) create_user ;;
        3) update_panel ;;
        4) domain_ssl_menu ;;
        5) service_control ;;
        6) phpmyadmin_menu ;;
        7) view_credentials ;;
        8) uninstall_ptero ;;
        0) clear; exit 0 ;;
        *) echo -e "${RED}  Invalid option selected...${NC}"; sleep 1 ;;
    esac
done
