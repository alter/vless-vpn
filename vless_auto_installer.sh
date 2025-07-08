#!/bin/bash

# vless_auto_installer.sh
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
VPN_PORT=${VPN_PORT:-}
PANEL_PORT=${PANEL_PORT:-}
PANEL_USER=${PANEL_USER:-admin}
PANEL_PASS=${PANEL_PASS:-$(openssl rand -base64 16)}
DOMAIN=${DOMAIN:-}
EMAIL=${EMAIL:-}
INSTALL_DIR="/opt/vless-manager"

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Install net-tools first
install_nettools() {
    log_info "Checking for net-tools..."
    if ! command -v netstat &> /dev/null; then
        log_info "Installing net-tools..."
        apt-get update -qq
        apt-get install -y -qq net-tools
    else
        log_info "net-tools already installed"
    fi
}

# Check Docker installation
check_docker_installation() {
    log_info "Checking Docker installation..."
    
    local docker_installed=false
    local docker_working=false
    
    # Check if docker command exists
    if command -v docker &> /dev/null; then
        docker_installed=true
        log_info "Docker command found"
        
        # Check if docker daemon is running
        if docker ps &> /dev/null; then
            docker_working=true
            log_info "Docker daemon is running"
        else
            log_error "Docker is installed but not working properly"
            log_error "Error: $(docker ps 2>&1)"
        fi
    else
        log_error "Docker is not installed"
    fi
    
    # If Docker is not installed or not working, provide instructions
    if [[ "$docker_installed" == "false" ]] || [[ "$docker_working" == "false" ]]; then
        echo ""
        echo -e "${RED}=== Docker Installation Required ===${NC}"
        echo ""
        echo "Docker is not installed or not working properly on this system."
        echo "Please install Docker first using the following commands:"
        echo ""
        echo -e "${GREEN}# Install Docker:${NC}"
        echo "curl -fsSL https://get.docker.com | sh"
        echo ""
        echo -e "${GREEN}# Add current user to docker group (optional):${NC}"
        echo "usermod -aG docker \$USER"
        echo ""
        echo -e "${GREEN}# Start and enable Docker service:${NC}"
        echo "systemctl enable docker"
        echo "systemctl start docker"
        echo ""
        echo -e "${GREEN}# Verify Docker installation:${NC}"
        echo "docker ps"
        echo ""
        echo "After installing Docker, please run this script again."
        echo ""
        exit 1
    fi
    
    # Check for docker-compose
    if ! command -v docker-compose &> /dev/null; then
        log_warn "docker-compose not found, will be installed during setup"
    else
        log_info "docker-compose is available"
    fi
    
    log_info "Docker check completed successfully"
}

# Detect available ports
detect_available_vpn_port() {
    # VPN ports in order of preference (HTTPS/SSL standard ports)
    local ports=(443 8443 2096 2087 2083 10443 9443)
    
    for port in "${ports[@]}"; do
        if ! netstat -tuln | grep -q ":$port "; then
            echo $port
            return
        fi
    done
    
    # If all standard ports are taken, find a random available port
    for i in {8000..8999}; do
        if ! netstat -tuln | grep -q ":$i "; then
            echo $i
            return
        fi
    done
    
    echo "8443" # fallback
}

detect_available_panel_port() {
    # Panel ports (prefer 2053 as requested)
    local ports=(2053 3000 8080 8888 9000 9999 7777)
    
    for port in "${ports[@]}"; do
        if ! netstat -tuln | grep -q ":$port "; then
            echo $port
            return
        fi
    done
    
    # Find random port
    for i in {9000..9999}; do
        if ! netstat -tuln | grep -q ":$i "; then
            echo $i
            return
        fi
    done
    
    echo "9000" # fallback
}

# Check for existing installation
check_existing_installation() {
    if [[ -d "$INSTALL_DIR" ]]; then
        log_warn "Previous VLESS installation detected at $INSTALL_DIR"
        echo -e "${YELLOW}Found existing installation:${NC}"
        
        # Show what's currently installed
        if [[ -f "$INSTALL_DIR/configs/server.conf" ]]; then
            echo "Previous configuration:"
            grep -E "(PANEL_PORT|VPN_PORT|INSTALL_DATE)" "$INSTALL_DIR/configs/server.conf" 2>/dev/null || true
        fi
        
        echo ""
        echo "Options:"
        echo "1) Remove and reinstall (recommended)"
        echo "2) Cancel installation"
        echo ""
        read -p "Choose option (1/2): " choice
        
        case $choice in
            1)
                log_info "Removing previous installation..."
                cleanup_previous_installation
                ;;
            2)
                log_info "Installation cancelled by user"
                exit 0
                ;;
            *)
                log_error "Invalid choice. Installation cancelled."
                exit 1
                ;;
        esac
    fi
}

# Clean up previous installation
cleanup_previous_installation() {
    log_info "Cleaning up previous installation..."
    
    # Stop and remove Docker containers
    if [[ -f "$INSTALL_DIR/docker/docker-compose.yml" ]]; then
        cd "$INSTALL_DIR/docker" && docker-compose down 2>/dev/null || true
    fi
    
    # Remove cron jobs
    if command -v crontab &> /dev/null; then
        (crontab -l 2>/dev/null | grep -v "/opt/vless-manager" || true) | crontab - 2>/dev/null || true
    fi
    
    # Clean up iptables rules (remove our custom rules)
    cleanup_iptables_rules
    
    # Remove fail2ban jail
    if [[ -f "/etc/fail2ban/jail.local" ]]; then
        sed -i '/\[3x-ui\]/,/^$/d' /etc/fail2ban/jail.local 2>/dev/null || true
        systemctl reload fail2ban 2>/dev/null || true
    fi
    
    # Remove systemd service
    systemctl disable iptables-restore.service 2>/dev/null || true
    rm -f /etc/systemd/system/iptables-restore.service
    systemctl daemon-reload
    
    # Remove management directory
    rm -rf "$INSTALL_DIR"
    
    log_info "Previous installation cleaned up successfully"
}

# Clean up our iptables rules
cleanup_iptables_rules() {
    log_debug "Cleaning up iptables rules..."
    
    # Remove our specific rules (be careful not to break existing rules)
    # Remove rules we typically add (using -D to delete specific rules)
    
    # Remove duplicate rules by checking and removing multiple times
    for i in {1..5}; do
        iptables -D INPUT -i lo -j ACCEPT 2>/dev/null || true
        iptables -D OUTPUT -o lo -j ACCEPT 2>/dev/null || true
        iptables -D INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
        iptables -D INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || true
        iptables -D INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
        iptables -D INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
    done
    
    # Try to remove common VPN ports we might have added multiple times
    local common_ports=(2053 3000 8080 8443 2096 2087 2083 9000 9999)
    for port in "${common_ports[@]}"; do
        for i in {1..5}; do
            iptables -D INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null || true
        done
    done
    
    # Save current rules
    if command -v iptables-save &> /dev/null; then
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
}

# Detect OS
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        log_error "Cannot detect OS"
        exit 1
    fi
    
    log_info "Detected OS: $OS $VER"
    
    if [[ "$OS" != "ubuntu" ]] && [[ "$OS" != "debian" ]]; then
        log_error "This script only supports Ubuntu/Debian"
        exit 1
    fi
}

# Update system packages (minimal)
update_system() {
    log_info "Installing required packages only..."
    apt-get update -qq
    apt-get install -y -qq \
        curl \
        wget \
        jq \
        iptables \
        iptables-persistent \
        fail2ban \
        net-tools \
        python3 \
        python3-pip \
        openssl \
        certbot
}

# Check Docker installation
check_docker() {
    log_info "Checking Docker installation..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed!"
        log_error "Please install Docker first:"
        log_error "curl -fsSL https://get.docker.com | sh"
        log_error "systemctl enable docker && systemctl start docker"
        exit 1
    fi
    
    if ! systemctl is-active --quiet docker; then
        log_error "Docker service is not running!"
        log_error "Please start Docker: systemctl start docker"
        exit 1
    fi
    
    # Check for docker-compose
    if ! command -v docker-compose &> /dev/null; then
        log_warn "docker-compose not found, installing..."
        # Install docker-compose
        curl -L "https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi
    
    log_info "Docker and docker-compose are ready"
}

# Install 3x-ui via Docker
install_3x_ui_docker() {
    log_info "Installing 3x-ui via Docker..."
    
    # Create docker-compose.yml with substituted variables
    mkdir -p $INSTALL_DIR/docker
    
    cat > $INSTALL_DIR/docker/docker-compose.yml << COMPOSE_EOF
version: '3'
services:
  3x-ui:
    image: ghcr.io/mhsanaei/3x-ui:latest
    container_name: 3x-ui
    volumes:
      - $INSTALL_DIR/docker/db/:/etc/x-ui/
      - $INSTALL_DIR/docker/cert/:/root/cert/
      - /etc/letsencrypt/:/etc/letsencrypt/:rw
    environment:
      XRAY_VMESS_AEAD_FORCED: "false"
      XUI_ENABLE_FAIL2BAN: "false"
      # Set panel to use HTTPS if certificates exist
      XUI_CERT_FILE: "/root/cert/server.crt"
      XUI_KEY_FILE: "/root/cert/server.key"
    ports:
      - "${PANEL_PORT}:2053"
      - "${VPN_PORT}:${VPN_PORT}"
    network_mode: bridge
    restart: unless-stopped
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
COMPOSE_EOF
    
    # Debug: show what was created
    log_debug "Created docker-compose.yml with ports: panel=${PANEL_PORT}, vpn=${VPN_PORT}"
    
    # Start container
    cd $INSTALL_DIR/docker
    docker-compose pull
    docker-compose up -d
    
    # Wait for container to start
    log_info "Waiting for 3x-ui to start..."
    sleep 10
    
    # Check if container is running
    if docker-compose ps | grep -q "Up"; then
        log_info "3x-ui Docker container started successfully"
        
        # Set panel username and password
        log_info "Setting panel username and password..."
        docker exec -it 3x-ui /app/x-ui setting -username "$PANEL_USER" -password "$PANEL_PASS"
        
        if [[ $? -eq 0 ]]; then
            log_info "Panel username and password set successfully"
        else
            log_warn "Failed to set panel username and password automatically"
            log_warn "You may need to set it manually with:"
            log_warn "docker exec -it 3x-ui /app/x-ui setting -username $PANEL_USER -password '$PANEL_PASS'"
        fi
    else
        log_error "Failed to start 3x-ui Docker container"
        log_error "Debug info:"
        echo "PANEL_PORT: $PANEL_PORT"
        echo "VPN_PORT: $VPN_PORT"
        echo "Contents of docker-compose.yml:"
        cat docker-compose.yml
        docker-compose logs
        exit 1
    fi
}

# Configure firewall with iptables
setup_firewall() {
    log_info "Configuring iptables firewall..."
    
    # Backup current rules
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.backup.$(date +%Y%m%d_%H%M%S)
    
    # Remove any existing rules we might have added before
    cleanup_iptables_rules
    
    # Add our rules (check if they don't exist first)
    # Allow loopback
    if ! iptables -C INPUT -i lo -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -i lo -j ACCEPT
    fi
    if ! iptables -C OUTPUT -o lo -j ACCEPT 2>/dev/null; then
        iptables -I OUTPUT -o lo -j ACCEPT
    fi
    
    # Allow established connections
    if ! iptables -C INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    fi
    
    # Allow SSH (port 22)
    if ! iptables -C INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -p tcp --dport 22 -j ACCEPT
    fi
    
    # Allow HTTP/HTTPS for certificate validation
    if ! iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -p tcp --dport 80 -j ACCEPT
    fi
    if ! iptables -C INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -p tcp --dport 443 -j ACCEPT
    fi
    
    # Allow panel port
    if ! iptables -C INPUT -p tcp --dport $PANEL_PORT -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -p tcp --dport $PANEL_PORT -j ACCEPT
    fi
    
    # Allow VPN port
    if ! iptables -C INPUT -p tcp --dport $VPN_PORT -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -p tcp --dport $VPN_PORT -j ACCEPT
    fi
    
    # Allow common VPN/proxy ports that might be used for additional configs
    local vpn_ports=(8080 8443 2096 2087 2083)
    for port in "${vpn_ports[@]}"; do
        if [[ "$port" != "$VPN_PORT" ]] && [[ "$port" != "$PANEL_PORT" ]]; then
            if ! iptables -C INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null; then
                iptables -I INPUT -p tcp --dport $port -j ACCEPT
            fi
        fi
    done
    
    # Save rules
    iptables-save > /etc/iptables/rules.v4
    
    # Ensure rules persist after reboot
    cat > /etc/systemd/system/iptables-restore.service << EOF
[Unit]
Description=Restore iptables rules
After=network-pre.target
Wants=network-pre.target
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/iptables/rules.v4
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl enable iptables-restore.service
    
    log_info "Iptables firewall configured successfully"
    log_info "VPN will be accessible on port: $VPN_PORT"
    log_info "Panel will be accessible on port: $PANEL_PORT"
}

# Configure fail2ban
setup_fail2ban() {
    log_info "Configuring fail2ban..."
    
    # Remove existing 3x-ui section if present
    if [[ -f "/etc/fail2ban/jail.local" ]]; then
        sed -i '/\[3x-ui\]/,/^$/d' /etc/fail2ban/jail.local 2>/dev/null || true
    fi
    
    # Create or append to jail.local
    cat >> /etc/fail2ban/jail.local << EOF

[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3

[3x-ui]
enabled = true
port = $PANEL_PORT
filter = 3x-ui
logpath = /opt/vless-manager/logs/access.log
maxretry = 2
bantime = 7200
EOF

    # Create filter if it doesn't exist
    cat > /etc/fail2ban/filter.d/3x-ui.conf << EOF
[Definition]
failregex = ^.*\[.*\] Failed login attempt from <HOST>.*$
ignoreregex =
EOF

    systemctl enable fail2ban
    systemctl restart fail2ban
    
    log_info "Fail2ban configured successfully"
}

# Setup SSL certificates
setup_ssl() {
    if [[ -n "$DOMAIN" ]] && [[ -n "$EMAIL" ]]; then
        log_info "Setting up SSL certificate for $DOMAIN..."
        
        # Stop services that might use port 80
        systemctl stop nginx 2>/dev/null || true
        systemctl stop apache2 2>/dev/null || true
        
        # Get certificate
        certbot certonly --standalone --agree-tos --no-eff-email --email $EMAIL -d $DOMAIN
        
        if [[ $? -eq 0 ]]; then
            log_info "SSL certificate obtained successfully"
        else
            log_warn "Failed to obtain SSL certificate"
        fi
    else
        log_info "Creating self-signed certificate for IP: $SERVER_IP"
        
        # Create certificate directory
        mkdir -p $INSTALL_DIR/docker/cert
        
        # Generate self-signed certificate
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout $INSTALL_DIR/docker/cert/server.key \
            -out $INSTALL_DIR/docker/cert/server.crt \
            -subj "/C=US/ST=State/L=City/O=VLESSOrg/CN=$SERVER_IP" \
            2>/dev/null
        
        if [[ $? -eq 0 ]]; then
            log_info "Self-signed certificate created successfully"
            log_warn "Note: Browsers will show security warnings for self-signed certificates"
        else
            log_error "Failed to create self-signed certificate"
        fi
    fi
}

# Create management directory
create_management_structure() {
    log_info "Creating management structure..."
    
    mkdir -p $INSTALL_DIR/{scripts,configs,logs,backups}
    
    # Create configuration file
    cat > $INSTALL_DIR/configs/server.conf << EOF
# VLESS Server Configuration
PANEL_PORT=$PANEL_PORT
PANEL_USER=$PANEL_USER
PANEL_PASS=$PANEL_PASS
VPN_PORT=$VPN_PORT
DOMAIN=$DOMAIN
EMAIL=$EMAIL
INSTALL_DATE=$(date)
SERVER_IP=$(curl -s -L -4 iprs.fly.dev || curl -s ipinfo.io/ip || echo "unknown")
EOF
}

# Create user management script
create_user_manager() {
    log_info "Creating user management script..."
    
    cat > $INSTALL_DIR/scripts/user_manager.py << 'PYTHON_EOF'
#!/usr/bin/env python3

import json
import requests
import argparse
import uuid
import sys
from datetime import datetime, timedelta

class VLESSUserManager:
    def __init__(self, panel_url, username, password):
        self.base_url = panel_url.rstrip('/')
        self.session = requests.Session()
        self.login(username, password)
    
    def login(self, username, password):
        """Login to 3x-ui panel"""
        login_data = {
            'username': username,
            'password': password
        }
        
        response = self.session.post(f"{self.base_url}/login", data=login_data)
        if response.status_code == 200:
            print("Successfully logged in to panel")
        else:
            print("Failed to login to panel")
            sys.exit(1)
    
    def create_user(self, email, traffic_gb=50, days=30, max_ips=2):
        """Create new VLESS user"""
        user_id = str(uuid.uuid4())
        expiry_time = int((datetime.now() + timedelta(days=days)).timestamp() * 1000)
        traffic_bytes = traffic_gb * 1024 * 1024 * 1024
        
        inbound_data = {
            "up": 0,
            "down": 0,
            "total": traffic_bytes,
            "remark": email,
            "enable": True,
            "expiryTime": expiry_time,
            "clientStats": [],
            "listen": "",
            "port": 443,
            "protocol": "vless",
            "settings": json.dumps({
                "clients": [{
                    "id": user_id,
                    "email": email,
                    "limitIp": max_ips,
                    "totalGB": traffic_bytes,
                    "expiryTime": expiry_time,
                    "enable": True,
                    "tgId": "",
                    "subId": ""
                }],
                "decryption": "none",
                "fallbacks": []
            }),
            "streamSettings": json.dumps({
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": False,
                    "dest": "www.microsoft.com:443",
                    "serverNames": ["www.microsoft.com"],
                    "privateKey": self.generate_reality_keys()[0],
                    "shortIds": ["", "0123456789abcdef"]
                }
            }),
            "sniffing": json.dumps({
                "enabled": True,
                "destOverride": ["http", "tls"]
            })
        }
        
        response = self.session.post(f"{self.base_url}/panel/api/inbounds/add", json=inbound_data)
        
        if response.status_code == 200:
            print(f"User {email} created successfully")
            return {
                "email": email,
                "uuid": user_id,
                "traffic_gb": traffic_gb,
                "expires": datetime.fromtimestamp(expiry_time/1000).strftime('%Y-%m-%d'),
                "max_ips": max_ips
            }
        else:
            print(f"Failed to create user {email}: {response.text}")
            return None
    
    def generate_reality_keys(self):
        """Generate Reality protocol keys"""
        # This is a simplified version - in real implementation use proper key generation
        import secrets
        private_key = secrets.token_hex(32)
        public_key = secrets.token_hex(32)
        return private_key, public_key
    
    def list_users(self):
        """List all users"""
        response = self.session.get(f"{self.base_url}/panel/api/inbounds/list")
        
        if response.status_code == 200:
            data = response.json()
            users = []
            for inbound in data.get('obj', []):
                settings = json.loads(inbound.get('settings', '{}'))
                for client in settings.get('clients', []):
                    users.append({
                        'email': client.get('email', 'N/A'),
                        'uuid': client.get('id', 'N/A'),
                        'enable': client.get('enable', False),
                        'traffic_used': inbound.get('up', 0) + inbound.get('down', 0),
                        'traffic_total': inbound.get('total', 0)
                    })
            return users
        else:
            print(f"Failed to get users: {response.text}")
            return []
    
    def delete_user(self, email):
        """Delete user by email"""
        # Implementation depends on 3x-ui API
        print(f"Delete user functionality for {email} - implement based on 3x-ui API")

def main():
    parser = argparse.ArgumentParser(description='VLESS User Manager')
    parser.add_argument('--panel-url', required=True, help='Panel URL (e.g., https://domain.com:2053)')
    parser.add_argument('--username', required=True, help='Panel username')
    parser.add_argument('--password', required=True, help='Panel password')
    
    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    
    # Create user command
    create_parser = subparsers.add_parser('create', help='Create new user')
    create_parser.add_argument('--email', required=True, help='User email')
    create_parser.add_argument('--traffic', type=int, default=50, help='Traffic limit in GB')
    create_parser.add_argument('--days', type=int, default=30, help='Validity in days')
    create_parser.add_argument('--max-ips', type=int, default=2, help='Max simultaneous IPs')
    
    # List users command
    list_parser = subparsers.add_parser('list', help='List all users')
    
    # Delete user command
    delete_parser = subparsers.add_parser('delete', help='Delete user')
    delete_parser.add_argument('--email', required=True, help='User email to delete')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return
    
    manager = VLESSUserManager(args.panel_url, args.username, args.password)
    
    if args.command == 'create':
        result = manager.create_user(args.email, args.traffic, args.days, args.max_ips)
        if result:
            print(json.dumps(result, indent=2))
    
    elif args.command == 'list':
        users = manager.list_users()
        for user in users:
            print(json.dumps(user, indent=2))
            print("-" * 40)
    
    elif args.command == 'delete':
        manager.delete_user(args.email)

if __name__ == '__main__':
    main()
PYTHON_EOF

    chmod +x $INSTALL_DIR/scripts/user_manager.py
}

# Create monitoring script
create_monitoring_script() {
    log_info "Creating monitoring script..."
    
    cat > $INSTALL_DIR/scripts/monitor.sh << 'EOF'
#!/bin/bash

# monitor.sh
INSTALL_DIR="/opt/vless-manager"
LOG_FILE="$INSTALL_DIR/logs/monitor.log"

log_metric() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $LOG_FILE
}

# System metrics
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
MEMORY_USAGE=$(free | grep Mem | awk '{printf("%.1f", $3/$2 * 100.0)}')
DISK_USAGE=$(df -h / | awk 'NR==2{printf "%s", $5}' | sed 's/%//')

log_metric "CPU: ${CPU_USAGE}%, Memory: ${MEMORY_USAGE}%, Disk: ${DISK_USAGE}%"

# Network connections
CONNECTIONS=$(netstat -tn | grep :443 | wc -l)
log_metric "Active connections: $CONNECTIONS"

# 3x-ui service status
if docker-compose -f $INSTALL_DIR/docker/docker-compose.yml ps | grep -q "Up"; then
    log_metric "3x-ui service: Running (Docker)"
else
    log_metric "3x-ui service: Stopped (Docker)"
    cd $INSTALL_DIR/docker && docker-compose up -d
fi

# Check disk space
if [[ $DISK_USAGE -gt 80 ]]; then
    log_metric "WARNING: Disk usage above 80%"
fi

# Check memory usage
MEMORY_USAGE_NUM=$(echo $MEMORY_USAGE | cut -d. -f1)
if [[ $MEMORY_USAGE_NUM -gt 90 ]]; then
    log_metric "WARNING: Memory usage above 90%"
fi
EOF

    chmod +x $INSTALL_DIR/scripts/monitor.sh
    
    # Add to crontab
    (crontab -l 2>/dev/null; echo "*/5 * * * * $INSTALL_DIR/scripts/monitor.sh") | crontab -
}

# Create backup script
create_backup_script() {
    log_info "Creating backup script..."
    
    cat > $INSTALL_DIR/scripts/backup.sh << 'BACKUP_EOF'
#!/bin/bash

INSTALL_DIR="/opt/vless-manager"
BACKUP_DIR="$INSTALL_DIR/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/backup_$DATE.tar.gz"

# Create backup directory
mkdir -p $BACKUP_DIR

# Backup 3x-ui database and configs
tar -czf $BACKUP_FILE \
    $INSTALL_DIR/docker/ \
    $INSTALL_DIR/configs/ 2>/dev/null

echo "Backup created: $BACKUP_FILE"

# Keep only last 7 backups
ls -t $BACKUP_DIR/backup_*.tar.gz | tail -n +8 | xargs -r rm

# Log backup
echo "$(date '+%Y-%m-%d %H:%M:%S') - Backup created: $BACKUP_FILE" >> $INSTALL_DIR/logs/backup.log
BACKUP_EOF

    chmod +x $INSTALL_DIR/scripts/backup.sh
    
    # Remove existing cron job and add new one
    (crontab -l 2>/dev/null | grep -v "$INSTALL_DIR/scripts/backup.sh" || true; echo "0 2 * * * $INSTALL_DIR/scripts/backup.sh") | crontab -
}

# Create system info script
create_info_script() {
    log_info "Creating system info script..."
    
    cat > $INSTALL_DIR/scripts/info.sh << 'INFO_EOF'
#!/bin/bash

INSTALL_DIR="/opt/vless-manager"
source $INSTALL_DIR/configs/server.conf

echo "=== VLESS Server Information ==="
echo "Server IP: $SERVER_IP"
echo "VPN Port: $VPN_PORT"
echo "Panel URL: https://$SERVER_IP:$PANEL_PORT"
echo "Panel User: $PANEL_USER"
echo "Panel Password: $PANEL_PASS"
echo "Domain: ${DOMAIN:-Not configured}"
echo "Installation Date: $INSTALL_DATE"
echo "Installation Method: Docker"
echo ""

echo "=== System Status ==="
echo "OS: $(lsb_release -d | cut -f2)"
echo "Uptime: $(uptime -p)"
echo "CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}')"
echo "Memory Usage: $(free -h | grep Mem | awk '{printf("%.1f%%", $3/$2 * 100.0)}')"
echo "Disk Usage: $(df -h / | awk 'NR==2{print $5}')"
echo ""

echo "=== Services Status ==="
if docker-compose -f $INSTALL_DIR/docker/docker-compose.yml ps | grep -q "Up"; then
    echo "3x-ui: Running (Docker)"
else
    echo "3x-ui: Stopped (Docker)"
fi
systemctl is-active --quiet iptables-restore && echo "Firewall: Active" || echo "Firewall: Inactive"
systemctl is-active --quiet fail2ban && echo "Fail2ban: Active" || echo "Fail2ban: Inactive"
echo ""

echo "=== Network Connections ==="
echo "Active connections on VPN port ($VPN_PORT): $(netstat -tn | grep :$VPN_PORT | wc -l)"
echo "Active connections on panel port ($PANEL_PORT): $(netstat -tn | grep :$PANEL_PORT | wc -l)"
echo "All listening ports: $(netstat -tuln | grep LISTEN | awk '{print $4}' | cut -d: -f2 | sort -n | uniq | tr '\n' ' ')"
echo ""

echo "=== Recent Logs ==="
echo "Last 5 lines from monitor log:"
tail -n 5 $INSTALL_DIR/logs/monitor.log 2>/dev/null || echo "No monitor logs found"
INFO_EOF

    chmod +x $INSTALL_DIR/scripts/info.sh
}

# Create uninstall script
create_uninstall_script() {
    log_info "Creating uninstall script..."
    
    cat > $INSTALL_DIR/scripts/uninstall.sh << 'UNINSTALL_EOF'
#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

INSTALL_DIR="/opt/vless-manager"

echo -e "${RED}WARNING: This will completely remove VLESS server and all data!${NC}"
echo "This will remove:"
echo "- Docker containers and data"
echo "- All configuration files"
echo "- Cron jobs"
echo "- Iptables rules added by installer"
echo "- Fail2ban configuration"
echo ""
read -p "Are you sure? (type 'yes' to confirm): " confirmation

if [[ "$confirmation" != "yes" ]]; then
    echo "Uninstallation cancelled"
    exit 0
fi

echo -e "${YELLOW}Uninstalling VLESS server...${NC}"

# Stop and remove Docker containers
if [[ -f "$INSTALL_DIR/docker/docker-compose.yml" ]]; then
    echo "Stopping Docker containers..."
    cd "$INSTALL_DIR/docker" && docker-compose down 2>/dev/null || true
fi

# Remove cron jobs
echo "Removing cron jobs..."
if command -v crontab &> /dev/null; then
    (crontab -l 2>/dev/null | grep -v "/opt/vless-manager" || true) | crontab - 2>/dev/null || true
fi

# Clean up iptables rules
echo "Cleaning up iptables rules..."
cleanup_iptables() {
    # Remove rules we typically add (ignore errors)
    iptables -D INPUT -i lo -j ACCEPT 2>/dev/null || true
    iptables -D OUTPUT -o lo -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
    
    # Try to remove common VPN ports
    local common_ports=(2053 3000 8080 8443 2096 2087 2083 9000 9999)
    for port in "${common_ports[@]}"; do
        iptables -D INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null || true
    done
    
    # Save current rules
    if command -v iptables-save &> /dev/null; then
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
}
cleanup_iptables

# Remove fail2ban jail
echo "Removing fail2ban configuration..."
if [[ -f "/etc/fail2ban/jail.local" ]]; then
    sed -i '/\[3x-ui\]/,/^$/d' /etc/fail2ban/jail.local 2>/dev/null || true
    systemctl reload fail2ban 2>/dev/null || true
fi

# Remove systemd service
echo "Removing systemd service..."
systemctl disable iptables-restore.service 2>/dev/null || true
rm -f /etc/systemd/system/iptables-restore.service
systemctl daemon-reload 2>/dev/null || true

# Remove management files
echo "Removing management files..."
rm -rf /opt/vless-manager

# Clean up any leftover Docker images (optional)
read -p "Remove Docker images? (y/n): " remove_images
if [[ "$remove_images" == "y" ]]; then
    docker rmi ghcr.io/mhsanaei/3x-ui:latest 2>/dev/null || true
fi

echo -e "${GREEN}VLESS server uninstalled successfully${NC}"
echo "Note: Docker itself was not removed"
echo "Note: Some iptables rules may still exist if they were present before installation"
UNINSTALL_EOF

    chmod +x $INSTALL_DIR/scripts/uninstall.sh
}

# Main installation function
main() {
    clear
    echo -e "${GREEN}"
    echo "================================================================="
    echo "           VLESS Auto-Installer with 3x-ui Panel"
    echo "================================================================="
    echo -e "${NC}"
    
    # Pre-installation checks
    check_root
    install_nettools
    check_docker_installation
    
    # Detect available ports
    if [[ -z "$VPN_PORT" ]]; then
        VPN_PORT=$(detect_available_vpn_port)
        log_info "Auto-detected VPN port: $VPN_PORT"
    fi
    
    if [[ -z "$PANEL_PORT" ]]; then
        PANEL_PORT=$(detect_available_panel_port)
        log_info "Auto-detected panel port: $PANEL_PORT"
    fi
    
    # Collect configuration
    if [[ -z "$DOMAIN" ]]; then
        read -p "Enter domain name (optional, press Enter to skip): " DOMAIN
    fi
    
    if [[ -n "$DOMAIN" ]] && [[ -z "$EMAIL" ]]; then
        read -p "Enter email for SSL certificate: " EMAIL
    fi
    
    echo -e "\n${YELLOW}Configuration:${NC}"
    echo "VPN Port: $VPN_PORT"
    echo "Panel Port: $PANEL_PORT"
    echo "Panel User: $PANEL_USER"
    echo "Panel Password: $PANEL_PASS"
    echo "Domain: ${DOMAIN:-Not configured}"
    echo "Email: ${EMAIL:-Not configured}"
    echo "Installation Method: Docker"
    
    # Show current occupied ports
    echo -e "\n${BLUE}Currently occupied ports:${NC}"
    netstat -tuln | grep LISTEN | awk '{print $4}' | cut -d: -f2 | sort -n | uniq | head -10
    
    read -p "Continue with installation? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo "Installation cancelled"
        exit 0
    fi
    
    # Start installation
    detect_os
    check_existing_installation
    check_docker
    update_system
    
    # Get server IP early for SSL certificate
    SERVER_IP=$(curl -s -L -4 iprs.fly.dev || curl -s ipinfo.io/ip || hostname -I | awk '{print $1}')
    
    # Main installation steps
    create_management_structure
    install_3x_ui_docker
    setup_firewall
    setup_fail2ban
    setup_ssl
    
    # Create management scripts
    create_user_manager
    create_monitoring_script
    create_backup_script
    create_info_script
    create_uninstall_script
    
    # Final configuration
    log_info "Installation completed successfully!"
    
    echo -e "\n${GREEN}=== Installation Summary ===${NC}"
    SERVER_IP=$(curl -s -L -4 iprs.fly.dev || curl -s ipinfo.io/ip || hostname -I | awk '{print $1}')
    echo "VPN Port: $VPN_PORT (configure VLESS clients to connect here)"
    echo "Panel URL: https://$SERVER_IP:$PANEL_PORT"
    echo "Username: $PANEL_USER"
    echo "Password: $PANEL_PASS"
    echo "Installation: Docker"
    echo ""
    echo -e "${GREEN}=== Quick Access Links ===${NC}"
    echo "Web Panel: https://$SERVER_IP:$PANEL_PORT"
    echo ""
    echo -e "${GREEN}=== Configuration & Logs ===${NC}"
    echo "View saved configuration:"
    echo "  cat $INSTALL_DIR/configs/server.conf"
    echo ""
    echo "View Docker logs:"
    echo "  cd $INSTALL_DIR/docker && docker-compose logs"
    echo "  cd $INSTALL_DIR/docker && docker-compose logs -f    # Follow logs in real-time"
    echo ""
    echo "View monitoring logs:"
    echo "  cat $INSTALL_DIR/logs/monitor.log"
    echo ""
    echo "Management scripts location: $INSTALL_DIR/scripts/"
    echo "Configuration files: $INSTALL_DIR/configs/"
    echo "Docker files: $INSTALL_DIR/docker/"
    echo "Logs directory: $INSTALL_DIR/logs/"
    echo "Backups directory: $INSTALL_DIR/backups/"
    echo ""
    echo -e "${YELLOW}Available management commands:${NC}"
    echo "  $INSTALL_DIR/scripts/info.sh              - Show server information"
    echo "  $INSTALL_DIR/scripts/user_manager.py      - Manage users (create/list/delete)"
    echo "  $INSTALL_DIR/scripts/monitor.sh           - Run monitoring check"
    echo "  $INSTALL_DIR/scripts/backup.sh            - Create backup"
    echo "  $INSTALL_DIR/scripts/uninstall.sh         - Uninstall everything"
    echo ""
    echo -e "${GREEN}Example user creation:${NC}"
    echo "  python3 $INSTALL_DIR/scripts/user_manager.py --panel-url https://$SERVER_IP:$PANEL_PORT --username $PANEL_USER --password $PANEL_PASS create --email user@example.com --traffic 100 --days 30"
    echo ""
    echo -e "${BLUE}Docker management commands:${NC}"
    echo "  cd $INSTALL_DIR/docker && docker-compose logs     - View logs"
    echo "  cd $INSTALL_DIR/docker && docker-compose restart  - Restart service"
    echo "  cd $INSTALL_DIR/docker && docker-compose down     - Stop service"
    echo "  cd $INSTALL_DIR/docker && docker-compose up -d    - Start service"
    echo ""
    echo -e "${BLUE}SSL Certificate:${NC}"
    if [[ -n "$DOMAIN" ]]; then
        echo "  Let's Encrypt certificate for domain: $DOMAIN"
    else
        echo "  Self-signed certificate for IP: $SERVER_IP"
        echo "  Location: $INSTALL_DIR/docker/cert/"
        echo "  Note: Browsers will show security warnings"
    fi
    echo ""
    echo -e "${BLUE}Don't forget to:${NC}"
    echo "1. Change default panel password"
    echo "2. Configure VLESS users to connect on port $VPN_PORT"
    if [[ -z "$DOMAIN" ]]; then
        echo "3. Accept browser security warning for self-signed certificate"
        echo "4. Test user creation and client connection"
        echo "5. Check that ports $VPN_PORT and $PANEL_PORT are accessible from outside"
    else
        echo "3. Configure domain DNS if using domain"
        echo "4. Test user creation and client connection"
        echo "5. Check that ports $VPN_PORT and $PANEL_PORT are accessible from outside"
    fi
    
    # Save installation info
    echo "Installation completed at $(date)" >> $INSTALL_DIR/logs/install.log
    echo "VPN Port: $VPN_PORT" >> $INSTALL_DIR/logs/install.log
    echo "Panel Port: $PANEL_PORT" >> $INSTALL_DIR/logs/install.log
    echo "Installation Method: Docker" >> $INSTALL_DIR/logs/install.log
}

# Run main function
main "$@"
