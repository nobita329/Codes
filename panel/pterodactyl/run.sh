#!/bin/bash

# ==============================================================================
#       PTERODACTYL CONTROL CENTER v3.0 (Fixed & Updated)
#       Auto-Detection + Panel Management + Service Control + Safe Updater
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

# --- UI HELPER FUNCTIONS ---
show_header() {
    clear
    echo -e "$BORDER_LINE"
    echo -e "${PURPLE}║${NC}         ${BOLD}${WHITE}PTERODACTYL SERVER MANAGEMENT SYSTEM${NC}             ${PURPLE}║${NC}"
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
            PANEL_VER=$(grep -oP "'version'\s*=>\s*'\K[^']+" "$PANEL_DIR/config/app.php" 2>/dev/null || echo "Installed")
        else
            PANEL_VER="Installed"
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
    elif pgrep -f "$svc" >/dev/null 2>&1; then
        echo -e "${GREEN}Running${NC}"
    else
        echo -e "${RED}Stopped${NC}"
    fi
}

# --- FETCH GITHUB RELEASES ---
fetch_github_versions() {
    local repo=$1
    local json=""

    if command -v curl >/dev/null 2>&1; then
        json=$(curl -sf --max-time 8 "https://api.github.com/repos/$repo/releases?per_page=15" 2>/dev/null)
    fi

    if [ -n "$json" ]; then
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

        local parsed
        parsed=$(echo "$json" | grep -oP '"tag_name":\s*"\K[^"]+' | grep -vE '(rc|beta|alpha)' 2>/dev/null)
        if [ -n "$parsed" ]; then
            echo "$parsed"
            return 0
        fi
    fi

    # Fallback to known stable release tags
    cat << "EOF"
v1.15.2
v1.15.1
v1.15.0
v1.14.1
v1.11.10
EOF
    return 0
}

# ==============================================================================
# 1. INSTALL FUNCTION
# ==============================================================================
install_ptero() {
    show_header "PANEL INSTALLATION"

    if [ -f "/root/a.sh" ]; then
        status_msg "INFO" "Executing local installer (/root/a.sh)..."
        sleep 1
        bash /root/a.sh
    else
        status_msg "INFO" "Local installer not found. Fetching online installation script..."
        sleep 1
        bash <(curl -fsSL https://github.com/nobita329/Codes/raw/refs/heads/main/panel/pterodactyl/installedv1.sh)
    fi

    echo ""
    status_msg "OK" "Installation Sequence Complete."
    pause
}

# ==============================================================================
# 2. USER MANAGEMENT
# ==============================================================================
create_user() {
    show_header "USER MANAGEMENT"

    if [ ! -d "$PANEL_DIR" ] || [ ! -f "$PANEL_DIR/.env" ]; then
        status_msg "ERR" "Panel directory or .env not found ($PANEL_DIR)."
        status_msg "ERR" "Please install the panel first."
        pause
        return
    fi

    echo -e "  ${CYAN}[1]${NC} Quick Admin User ${GRAY}(admin / admin)${NC}"
    echo -e "  ${CYAN}[2]${NC} Custom Admin User ${GRAY}(Interactive Prompts)${NC}"
    echo -e "  ${CYAN}[3]${NC} Random Admin User ${GRAY}(Auto-generated)${NC}"
    echo -e "  ${CYAN}[4]${NC} Reset Existing User Password"
    echo -e "  ${GRAY}[0]${NC} Return to Menu"
    echo ""
    read -r -p "  Choose option [1-4]: " choice

    cd "$PANEL_DIR" || return

    case "$choice" in
        1)
            # Quick admin with username "admin" and password "admin"
            status_msg "WAIT" "Creating/Updating admin account (admin:admin)..."
            
            php artisan p:user:make -n \
                --email="admin@panel.nobitahost.in" \
                --username="admin" \
                --password="admin" \
                --admin=1 \
                --name-first="Admin" \
                --name-last="User" 2>/dev/null || {
                # If user already exists, update password directly
                php -r "
                require 'vendor/autoload.php';
                \$app = require_once 'bootstrap/app.php';
                \$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
                \$kernel->bootstrap();
                \$u = Pterodactyl\Models\User::where('username', 'admin')->orWhere('email', 'admin@panel.nobitahost.in')->first();
                if (\$u) {
                    \$u->password = Illuminate\Support\Facades\Hash::make('admin');
                    \$u->root_admin = true;
                    \$u->save();
                }
                " 2>/dev/null || true
            }

            echo ""
            status_msg "OK" "Admin user is ready!"
            echo -e "  ${WHITE}Username :${NC} admin"
            echo -e "  ${WHITE}Password :${NC} admin"
            echo -e "  ${WHITE}Email    :${NC} admin@panel.nobitahost.in"
            ;;

        2)
            status_msg "WAIT" "Launching manual user creation..."
            echo ""
            php artisan p:user:make
            ;;

        3)
            status_msg "WAIT" "Generating random administrator..."
            RAND_USER="admin_$(openssl rand -hex 2)"
            RAND_PASS="Adm@$(openssl rand -base64 8 | tr -dc 'a-zA-Z0-9')"
            RAND_EMAIL="${RAND_USER}@panel.local"

            php artisan p:user:make -n \
                --email="${RAND_EMAIL}" \
                --username="${RAND_USER}" \
                --password="${RAND_PASS}" \
                --admin=1 \
                --name-first="Admin" \
                --name-last="Auto"

            echo ""
            status_msg "OK" "Random Administrator Created!"
            echo -e "  ${WHITE}Username :${NC} $RAND_USER"
            echo -e "  ${WHITE}Password :${NC} $RAND_PASS"
            echo -e "  ${WHITE}Email    :${NC} $RAND_EMAIL"
            ;;

        4)
            echo ""
            read -r -p "  Enter Username or Email to reset: " TARGET_USER
            read -r -p "  Enter New Password: " NEW_PW
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
# 3. SAFE PANEL UPDATE FUNCTION (Preserves .env & Data)
# ==============================================================================
update_panel() {
    show_header "SYSTEM UPDATE"

    if [ ! -d "$PANEL_DIR" ] || [ ! -f "$PANEL_DIR/.env" ]; then
        status_msg "ERR" "Panel not found in $PANEL_DIR"
        pause
        return
    fi

    echo -e "  ${WHITE}Fetching available releases from GitHub...${NC}"
    local tags=() i=0
    while IFS= read -r tag; do
        [[ -z "$tag" ]] && continue
        tags+=("$tag")
        i=$((i+1))
        echo -e "  ${GRAY}$i.${NC} ${WHITE}$tag${NC}"
    done < <(fetch_github_versions "$GITHUB_REPO" 2>/dev/null)

    local max=${#tags[@]}
    local default_tag="latest"
    [ $max -gt 0 ] && default_tag="${tags[0]}"

    echo ""
    echo -ne "  ${CYAN}Select version [1-$max]${NC} ${GRAY}[1 = latest ($default_tag)]${NC}: "
    read -r -t 15 choice || choice="1"
    [ -z "$choice" ] && choice="1"

    local SELECTED_TAG="$default_tag"
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$max" ]; then
        SELECTED_TAG="${tags[$((choice - 1))]}"
    fi

    echo ""
    echo -ne "  ${CYAN}Upgrade panel to ${WHITE}${SELECTED_TAG}${CYAN}?${NC} ${WHITE}(y/n)${NC} [y]: "
    read -r -t 10 CONFIRM_UPDATE || CONFIRM_UPDATE="y"
    [ -z "$CONFIRM_UPDATE" ] && CONFIRM_UPDATE="y"

    if [[ ! "$CONFIRM_UPDATE" =~ ^[Yy]$ ]]; then
        status_msg "INFO" "Update cancelled by user."
        pause
        return
    fi

    cd "$PANEL_DIR" || return

    status_msg "WAIT" "Entering maintenance mode..."
    php artisan down 2>/dev/null || true

    status_msg "WAIT" "Downloading panel release (${SELECTED_TAG})..."
    local DL_URL="https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"
    if [ "$SELECTED_TAG" != "latest" ]; then
        DL_URL="https://github.com/pterodactyl/panel/releases/download/${SELECTED_TAG}/panel.tar.gz"
    fi

    curl -L --fail -o panel.tar.gz "$DL_URL" || {
        status_msg "ERR" "Download failed! Aborting update."
        php artisan up 2>/dev/null || true
        pause
        return
    }

    status_msg "WAIT" "Extracting update archive..."
    # Safe extract without wiping .env
    tar -xzf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/

    status_msg "WAIT" "Updating composer dependencies..."
    export COMPOSER_ALLOW_SUPERUSER=1
    composer install --no-dev --optimize-autoloader --no-interaction

    status_msg "WAIT" "Clearing application caches & running database migrations..."
    php artisan view:clear
    php artisan config:clear
    php artisan migrate --seed --force

    status_msg "WAIT" "Setting permissions..."
    chown -R www-data:www-data "$PANEL_DIR"

    status_msg "WAIT" "Restarting queue workers..."
    systemctl restart pteroq.service 2>/dev/null || php artisan queue:restart 2>/dev/null || true

    status_msg "WAIT" "Disabling maintenance mode..."
    php artisan up 2>/dev/null || true

    echo ""
    status_msg "OK" "Panel Updated Successfully to ${SELECTED_TAG}!"
    pause
}

# ==============================================================================
# 4. DOMAIN & SSL CONFIGURATION
# ==============================================================================
domain_ssl_menu() {
    show_header "DOMAIN & SSL CONFIGURATION"

    echo -e "  ${CYAN}[1]${NC} Re-run SSL Setup (Local Self-Signed or Certbot)"
    echo -e "  ${CYAN}[2]${NC} Change Panel Domain / APP_URL"
    echo -e "  ${CYAN}[3]${NC} Run Remote SSL Script (GitHub)"
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
                cd "$PANEL_DIR" && php artisan config:clear && php artisan config:cache
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
    echo -e "  ${CYAN}[2]${NC} Fix Permissions (chown www-data & chmod 755)"
    echo -e "  ${CYAN}[3]${NC} Clear & Rebuild All Laravel Caches"
    echo -e "  ${CYAN}[4]${NC} View System Logs"
    echo -e "  ${GRAY}[0]${NC} Return to Menu"
    echo ""
    read -r -p "  Choose option [1-4]: " s_choice

    case "$s_choice" in
        1)
            status_msg "WAIT" "Restarting services..."
            systemctl daemon-reload
            systemctl restart redis-server 2>/dev/null || systemctl restart redis 2>/dev/null || true
            systemctl restart mariadb 2>/dev/null || systemctl restart mysql 2>/dev/null || true
            systemctl restart "php${PHP_VERSION}-fpm" 2>/dev/null || true
            nginx -t 2>/dev/null && systemctl restart nginx 2>/dev/null || true
            systemctl restart pteroq.service 2>/dev/null || true
            status_msg "OK" "All services restarted."
            ;;
        2)
            status_msg "WAIT" "Repairing file permissions..."
            chmod -R 755 "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache"
            chown -R www-data:www-data "$PANEL_DIR"
            status_msg "OK" "Ownership set to www-data:www-data and storage chmod 755."
            ;;
        3)
            status_msg "WAIT" "Clearing and optimizing caches..."
            cd "$PANEL_DIR" || return
            php artisan view:clear
            php artisan config:clear
            php artisan cache:clear
            php artisan config:cache
            php artisan queue:restart
            status_msg "OK" "Laravel caches refreshed."
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
    systemctl daemon-reload

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
    echo -e "       ${BOLD}${WHITE}PTERODACTYL CONTROL CENTER v3.0${NC}"
    echo -e "${CYAN} ┌───────────────────────────────────────────────────────────┐${NC}"

    # System & Panel Status
    if [ "$PANEL_INSTALLED" = true ]; then
        echo -e "${CYAN} │${NC} ${WHITE}PANEL STATUS:${NC} ${GREEN}INSTALLED ✔ (${PANEL_VER})${NC}"
    else
        echo -e "${CYAN} │${NC} ${WHITE}PANEL STATUS:${NC} ${RED}NOT INSTALLED ✘${NC}"
    fi
    echo -e "${CYAN} │${NC} ${GRAY}OS:${NC} ${WHITE}${SYS_OS}${NC}  ${GRAY}| IP:${NC} ${WHITE}${SYS_IP}${NC}"
    echo -e "${CYAN} │${NC} ${GRAY}Nginx:${NC} $(check_service_status nginx) ${GRAY}| MariaDB:${NC} $(check_service_status mariadb) ${GRAY}| PHP:${NC} $(check_service_status "php${PHP_VERSION}-fpm") ${GRAY}| Queue:${NC} $(check_service_status pteroq)"

    echo -e "${CYAN} ├───────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN} │${NC}                                                           ${CYAN}│${NC}"
    echo -e "${CYAN} │${NC}  ${GREEN}[1]${NC} Install Panel   ${GRAY}:: (Run Full Installer)${NC}            ${CYAN}│${NC}"
    echo -e "${CYAN} │${NC}  ${GREEN}[2]${NC} User Manager    ${GRAY}:: (admin:admin / Custom User)${NC}     ${CYAN}│${NC}"
    echo -e "${CYAN} │${NC}  ${YELLOW}[3]${NC} Update Panel    ${GRAY}:: (Safe Release Upgrade)${NC}          ${CYAN}│${NC}"
    echo -e "${CYAN} │${NC}  ${CYAN}[4]${NC} Domain & SSL    ${GRAY}:: (Change Domain / Reissue SSL)${NC}   ${CYAN}│${NC}"
    echo -e "${CYAN} │${NC}  ${CYAN}[5]${NC} Service Control ${GRAY}:: (Restart / Fix Permissions)${NC}    ${CYAN}│${NC}"
    echo -e "${CYAN} │${NC}  ${BLUE}[6]${NC} phpMyAdmin      ${GRAY}:: (Install / Setup DB Tool)${NC}       ${CYAN}│${NC}"
    echo -e "${CYAN} │${NC}  ${GOLD}[7]${NC} Credentials     ${GRAY}:: (View Admin/DB Passwords)${NC}       ${CYAN}│${NC}"
    echo -e "${CYAN} │${NC}  ${RED}[8]${NC} Uninstall Panel ${GRAY}:: (Remove Panel & Database)${NC}       ${CYAN}│${NC}"
    echo -e "${CYAN} │${NC}                                                           ${CYAN}│${NC}"
    echo -e "${CYAN} │${NC}  ${WHITE}[0] Exit System${NC}                                         ${CYAN}│${NC}"
    echo -e "${CYAN} └───────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -ne "${BOLD}${WHITE}  root@ptero:~# ${NC}"
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
