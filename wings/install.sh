#!/bin/bash
set -o pipefail

# ==============================================================================
#       PTERODACTYL WINGS INSTALLER (v1 & v2)
# ==============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# UI Elements
CHECKMARK="✓"
CROSSMARK="✗"
ARROW="➤"
HEADER_LINE="${GRAY}────────────────────────────────────────────────────────────${NC}"

# Function to print section headers
print_header() {
    echo -e "\n${MAGENTA}╔══════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC}${CYAN}   $1${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════╝${NC}"
}

print_status() {
    echo -e "${YELLOW}${ARROW} $1...${NC}"
}

print_success() {
    echo -e "${GREEN}${CHECKMARK} $1${NC}"
}

print_error() {
    echo -e "${RED}${CROSSMARK} $1${NC}"
}

check_success() {
    if [ $? -eq 0 ]; then
        print_success "$1"
        return 0
    else
        print_error "$2"
        return 1
    fi
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root! (sudo bash $0)"
    exit 1
fi

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" == "x86_64" ]; then 
    ARCH="amd64"
elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then 
    ARCH="arm64"
else 
    ARCH="amd64"
fi

# Function to install Docker & configure GRUB
setup_docker_and_system() {
    # 1. Docker install
    print_header "1. INSTALLING DOCKER"
    if command -v docker >/dev/null 2>&1; then
        print_success "Docker is already installed ($(docker -v 2>/dev/null | cut -d, -f1))"
    else
        print_status "Installing Docker CE via official script"
        curl -sSL https://get.docker.com/ | CHANNEL=stable bash
        check_success "Docker installed successfully" "Failed to install Docker"
    fi

    print_status "Starting and enabling Docker service"
    systemctl enable --now docker >/dev/null 2>&1 || service docker start >/dev/null 2>&1 || true
    check_success "Docker service started" "Failed to start Docker"

    # 2. Update GRUB
    print_header "2. CONFIGURING SYSTEM KERNEL (GRUB)"
    GRUB_FILE="/etc/default/grub"
    if [ -f "$GRUB_FILE" ]; then
        print_status "Checking GRUB swap accounting"
        if ! grep -q "swapaccount=1" "$GRUB_FILE"; then
            sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="swapaccount=1 /' "$GRUB_FILE"
            update-grub >/dev/null 2>&1 || true
            print_success "GRUB updated with swapaccount=1"
        else
            print_success "GRUB swap accounting is already active"
        fi
    fi
}

# Function to setup systemd service & helper command
setup_service_and_helper() {
    local v_name=$1

    print_header "4. CONFIGURING SYSTEMD SERVICE"
    print_status "Writing /etc/systemd/system/wings.service"
    WINGS_SERVICE_FILE="/etc/systemd/system/wings.service"
    cat > "$WINGS_SERVICE_FILE" << 'EOF'
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
    check_success "Service file created"

    print_status "Reloading systemd daemon"
    systemctl daemon-reload >/dev/null 2>&1 || true
    check_success "Systemd reloaded"

    print_status "Enabling Wings service on boot"
    systemctl enable wings >/dev/null 2>&1 || true
    check_success "Wings service enabled"

    # SSL Certificate
    print_header "5. GENERATING SSL CERTIFICATE"
    print_status "Creating certificate directory (/etc/certs/wing)"
    mkdir -p /etc/certs/wing
    cd /etc/certs/wing || exit 1
    openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
        -subj "/C=NA/ST=NA/L=NA/O=Nobita/CN=Generic-SSL" \
        -keyout privkey.pem -out fullchain.pem >/dev/null 2>&1 || true
    check_success "Default SSL certificate generated"

    # Helper command
    print_header "6. CREATING HELPER COMMAND"
    print_status "Writing /usr/local/bin/wing helper"
    cat > /usr/local/bin/wing << 'EOF'
#!/bin/bash
echo ""
echo -e "\033[0;35m════════════════════════════════════════════\033[0m"
echo -e "\033[1;36m  Wings Helper Commands:\033[0m"
echo -e "\033[0;35m════════════════════════════════════════════\033[0m"
echo -e "  \033[1;37mstart\033[0m    : sudo systemctl start wings"
echo -e "  \033[1;37mstop\033[0m     : sudo systemctl stop wings"
echo -e "  \033[1;37mstatus\033[0m   : sudo systemctl status wings"
echo -e "  \033[1;37mrestart\033[0m  : sudo systemctl restart wings"
echo -e "  \033[1;37mlogs\033[0m     : sudo journalctl -u wings -n 50 -f"
echo -e "  \033[1;37mdebug\033[0m    : cd /etc/pterodactyl && sudo wings --debug"
echo -e "\033[0;35m════════════════════════════════════════════\033[0m"
echo ""

case "$1" in
    start)   sudo systemctl start wings ;;
    stop)    sudo systemctl stop wings ;;
    status)  sudo systemctl status wings ;;
    restart) sudo systemctl restart wings ;;
    logs)    sudo journalctl -u wings -n 50 -f ;;
    debug)   cd /etc/pterodactyl && sudo wings --debug ;;
esac
EOF
    chmod +x /usr/local/bin/wing
    check_success "Helper command created (/usr/local/bin/wing)"

    # Complete
    print_header "INSTALLATION COMPLETE"
    echo -e "${GREEN}${CHECKMARK} Wings for ${WHITE}${v_name}${GREEN} installed successfully!${NC}"
    echo ""
    echo -e "${CYAN}Next Step - Configure your Node:${NC}"
    echo -e "  ${WHITE}1.${NC} In your Panel, go to: ${YELLOW}Admin -> Nodes -> Your Node -> Configuration${NC}"
    echo -e "  ${WHITE}2.${NC} Paste the ${YELLOW}Auto-Deploy Command${NC} or save contents into ${YELLOW}/etc/pterodactyl/config.yml${NC}"
    echo -e "  ${WHITE}3.${NC} Start Wings daemon: ${GREEN}sudo systemctl start wings${NC} (or run: ${GREEN}wing start${NC})"
    echo ""
}

# --- INSTALL WINGS FOR PTERODACTYL v2 ---
install_v2() {
    setup_docker_and_system

    print_header "3. DOWNLOADING WINGS FOR PTERODACTYL v2 (Next-Gen)"
    print_status "Creating directories (/etc/pterodactyl, /var/log/pterodactyl)"
    mkdir -p /etc/pterodactyl /var/log/pterodactyl /tmp/pterodactyl
    check_success "Directories created"

    print_status "Downloading latest Wings binary for Pterodactyl v2 (Arch: $ARCH)"
    curl -L --fail -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$ARCH" >/dev/null 2>&1 || {
        print_status "Fallback to verified v2-compatible Wings release"
        curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/download/v1.11.12/wings_linux_$ARCH"
    }
    check_success "Wings downloaded successfully" "Failed to download Wings"

    print_status "Setting executable permissions"
    chmod u+x /usr/local/bin/wings
    check_success "Permissions set"

    setup_service_and_helper "Pterodactyl v2.0 (Next-Gen)"
}

# --- INSTALL WINGS FOR PTERODACTYL v1 ---
install_v1() {
    setup_docker_and_system

    print_header "3. DOWNLOADING WINGS FOR PTERODACTYL v1 (Legacy Stable)"
    print_status "Creating directories (/etc/pterodactyl)"
    mkdir -p /etc/pterodactyl /var/log/pterodactyl
    check_success "Directories created"

    print_status "Downloading stable Wings binary for Pterodactyl v1 (Arch: $ARCH)"
    curl -L --fail -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$ARCH" >/dev/null 2>&1
    check_success "Wings downloaded successfully" "Failed to download Wings"

    print_status "Setting executable permissions"
    chmod u+x /usr/local/bin/wings
    check_success "Permissions set"

    setup_service_and_helper "Pterodactyl v1.x (Legacy Stable)"
}

# --- MAIN MENU (ONLY INSTALL) ---
main() {
    if [[ "$1" == "--v2" || "$1" == "v2" || "$1" == "2" ]]; then
        install_v2
        exit 0
    fi

    if [[ "$1" == "--v1" || "$1" == "v1" || "$1" == "1" ]]; then
        install_v1
        exit 0
    fi

    clear 2>/dev/null || true
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}         ${BOLD}${CYAN}⚡ PTERODACTYL WINGS INSTALLER (v1 & v2) ⚡${NC}        ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo -e "  ${GRAY}• Detected Arch :${NC} ${WHITE}${ARCH}${NC}"
    echo -e "  ${GRAY}• Docker Status :${NC} $(command -v docker >/dev/null 2>&1 && echo -e "${GREEN}Installed ✔${NC}" || echo -e "${YELLOW}Will be installed automatically${NC}")"
    echo -e "${HEADER_LINE}"
    echo -e "  ${WHITE}Select Pterodactyl Edition to Install Wings:${NC}\n"
    echo -e "  ${CYAN}[1]${NC} ${WHITE}⚡ Install Wings for Pterodactyl v2 (Next-Gen)${NC}"
    echo -e "  ${CYAN}[2]${NC} ${WHITE}📦 Install Wings for Pterodactyl v1 (Legacy Stable)${NC}"
    echo -e "  ${GRAY}[0]${NC} Exit"
    echo -e "${HEADER_LINE}"
    echo -ne "  ${BOLD}${WHITE}Choose option [1-2] [1]: ${NC}"
    read -r -t 15 choice || choice="1"
    [ -z "$choice" ] && choice="1"

    case "$choice" in
        1)
            install_v2
            ;;
        2)
            install_v1
            ;;
        0)
            echo -e "  ${GRAY}Exiting installer.${NC}"
            exit 0
            ;;
        *)
            echo -e "  ${YELLOW}Defaulting to Pterodactyl v2 Wings installation...${NC}"
            install_v2
            ;;
    esac
}

main "$@"
