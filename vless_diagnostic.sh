#!/bin/bash

# vless_diagnostic.sh
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="/opt/vless-manager"
CONFIG_FILE="$INSTALL_DIR/configs/server.conf"

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

check_status() {
    local status=$1
    local message=$2
    
    if [[ $status -eq 0 ]]; then
        echo -e "${GREEN}✓${NC} $message"
    else
        echo -e "${RED}✗${NC} $message"
    fi
}

# Check if VLESS is installed
check_installation() {
    echo "=== 1. Checking VLESS Installation ==="
    
    if [[ ! -d "$INSTALL_DIR" ]]; then
        log_error "VLESS installation not found at $INSTALL_DIR"
        exit 1
    fi
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found at $CONFIG_FILE"
        exit 1
    fi
    
    log_info "VLESS installation found"
    echo ""
}

# Load and display configuration
load_config() {
    echo "=== 2. Loading Configuration ==="
    
    if [[ -f "$CONFIG_FILE" ]]; then
        # Safely load config with proper escaping
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ $key =~ ^#.*$ ]] && continue
            [[ -z $key ]] && continue
            
            # Remove any quotes from value and re-quote safely
            value=$(echo "$value" | sed 's/^"//;s/"$//')
            
            case $key in
                PANEL_PORT) PANEL_PORT="$value" ;;
                VPN_PORT) VPN_PORT="$value" ;;
                PANEL_USER) PANEL_USER="$value" ;;
                PANEL_PASS) PANEL_PASS="$value" ;;
                SERVER_IP) SERVER_IP="$value" ;;
                DOMAIN) DOMAIN="$value" ;;
                EMAIL) EMAIL="$value" ;;
                INSTALL_DATE) INSTALL_DATE="$value" ;;
                INSTALL_METHOD) INSTALL_METHOD="$value" ;;
            esac
        done < "$CONFIG_FILE"
        
        echo "VPN Port: ${VPN_PORT:-Not set}"
        echo "Panel Port: ${PANEL_PORT:-Not set}"
        echo "Panel User: ${PANEL_USER:-Not set}"
        echo "Server IP: ${SERVER_IP:-Not set}"
        echo "Domain: ${DOMAIN:-Not configured}"
        echo "Install Date: ${INSTALL_DATE:-Unknown}"
        echo "Install Method: ${INSTALL_METHOD:-Unknown}"
    else
        log_error "Cannot load configuration"
        exit 1
    fi
    echo ""
}

# Check Docker container status
check_docker_container() {
    echo "=== 3. Checking Docker Container ==="
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found"
        return 1
    fi
    
    # Check if container exists
    if docker ps -a --format "table {{.Names}}" | grep -q "3x-ui"; then
        log_info "3x-ui container found"
        
        # Check if container is running
        if docker ps --format "table {{.Names}}" | grep -q "3x-ui"; then
            log_info "3x-ui container is running"
            
            # Show container details
            echo "Container details:"
            docker ps --filter "name=3x-ui" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
            
        else
            log_error "3x-ui container is not running"
            echo "Container status:"
            docker ps -a --filter "name=3x-ui" --format "table {{.Names}}\t{{.Status}}"
        fi
    else
        log_error "3x-ui container not found"
    fi
    echo ""
}

# Check port mapping
check_port_mapping() {
    echo "=== 4. Checking Port Mapping ==="
    
    if docker ps --filter "name=3x-ui" --format "{{.Names}}" | grep -q "3x-ui"; then
        log_info "Docker port mapping:"
        docker port 3x-ui
        
        echo ""
        log_info "Detailed port information:"
        docker inspect 3x-ui | jq -r '.[] | .NetworkSettings.Ports' 2>/dev/null || echo "jq not available for JSON parsing"
        
        echo ""
        log_info "Ports listening inside container:"
        docker exec 3x-ui netstat -tlnp 2>/dev/null || docker exec 3x-ui ss -tlnp 2>/dev/null || log_warn "Cannot check ports inside container"
        
    else
        log_error "Cannot check port mapping - container not running"
    fi
    echo ""
}

# Check firewall rules
check_firewall_rules() {
    echo "=== 5. Checking Firewall Rules ==="
    
    log_info "Checking iptables INPUT rules:"
    echo "Relevant INPUT rules:"
    iptables -L INPUT -v -n | grep -E "(tcp|udp)" | grep -E "(${VPN_PORT:-443}|${PANEL_PORT:-2053}|22|80|443)" || echo "No specific rules found"
    
    echo ""
    log_info "Checking NAT rules (port forwarding):"
    echo "DOCKER chain rules:"
    iptables -t nat -L DOCKER -v -n | grep -E "(${VPN_PORT:-443}|${PANEL_PORT:-2053})" || echo "No DOCKER NAT rules found"
    
    echo ""
    log_info "Checking PREROUTING rules:"
    iptables -t nat -L PREROUTING -v -n | grep -E "(${VPN_PORT:-443}|${PANEL_PORT:-2053})" || echo "No PREROUTING rules found"
    
    echo ""
    log_info "Host ports currently listening:"
    netstat -tlnp | grep -E ":${VPN_PORT:-443}|:${PANEL_PORT:-2053}|:22|:80" || echo "No matching ports found"
    
    echo ""
}

# Check localhost connectivity
check_localhost_connectivity() {
    echo "=== 6. Checking Localhost Connectivity ==="
    
    # Check VPN port
    if [[ -n "$VPN_PORT" ]]; then
        log_info "Testing VPN port ($VPN_PORT) connectivity:"
        
        # TCP connection test
        if timeout 5 bash -c "</dev/tcp/127.0.0.1/$VPN_PORT" 2>/dev/null; then
            check_status 0 "VPN port $VPN_PORT is reachable via TCP"
        else
            check_status 1 "VPN port $VPN_PORT is NOT reachable via TCP"
        fi
        
        # Telnet test
        if command -v telnet &> /dev/null; then
            echo "quit" | timeout 3 telnet 127.0.0.1 $VPN_PORT 2>/dev/null && \
            check_status 0 "VPN port $VPN_PORT responds to telnet" || \
            check_status 1 "VPN port $VPN_PORT does not respond to telnet"
        fi
    fi
    
    echo ""
    
    # Check Panel port
    if [[ -n "$PANEL_PORT" ]]; then
        log_info "Testing Panel port ($PANEL_PORT) connectivity:"
        
        # TCP connection test
        if timeout 5 bash -c "</dev/tcp/127.0.0.1/$PANEL_PORT" 2>/dev/null; then
            check_status 0 "Panel port $PANEL_PORT is reachable via TCP"
        else
            check_status 1 "Panel port $PANEL_PORT is NOT reachable via TCP"
        fi
        
        # HTTP test
        if command -v curl &> /dev/null; then
            echo "Testing HTTP connectivity:"
            
            # Try HTTP
            if timeout 5 curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:$PANEL_PORT 2>/dev/null | grep -q "200\|301\|302\|401\|403"; then
                check_status 0 "Panel HTTP on port $PANEL_PORT responds"
            else
                check_status 1 "Panel HTTP on port $PANEL_PORT does not respond"
            fi
            
            # Try HTTPS
            if timeout 5 curl -k -s -o /dev/null -w "%{http_code}" https://127.0.0.1:$PANEL_PORT 2>/dev/null | grep -q "200\|301\|302\|401\|403"; then
                check_status 0 "Panel HTTPS on port $PANEL_PORT responds"
            else
                check_status 1 "Panel HTTPS on port $PANEL_PORT does not respond"
            fi
        fi
        
        # Telnet test
        if command -v telnet &> /dev/null; then
            echo "quit" | timeout 3 telnet 127.0.0.1 $PANEL_PORT 2>/dev/null && \
            check_status 0 "Panel port $PANEL_PORT responds to telnet" || \
            check_status 1 "Panel port $PANEL_PORT does not respond to telnet"
        fi
    fi
    
    echo ""
}

# Check external connectivity
check_external_connectivity() {
    echo "=== 7. Checking External Connectivity ==="
    
    if [[ -n "$SERVER_IP" ]]; then
        log_info "Testing external connectivity to $SERVER_IP:"
        
        # Check VPN port
        if [[ -n "$VPN_PORT" ]]; then
            echo "Testing VPN port $VPN_PORT:"
            if timeout 5 bash -c "</dev/tcp/$SERVER_IP/$VPN_PORT" 2>/dev/null; then
                check_status 0 "VPN port $VPN_PORT is externally reachable"
            else
                check_status 1 "VPN port $VPN_PORT is NOT externally reachable"
            fi
        fi
        
        # Check Panel port
        if [[ -n "$PANEL_PORT" ]]; then
            echo "Testing Panel port $PANEL_PORT:"
            if timeout 5 bash -c "</dev/tcp/$SERVER_IP/$PANEL_PORT" 2>/dev/null; then
                check_status 0 "Panel port $PANEL_PORT is externally reachable"
            else
                check_status 1 "Panel port $PANEL_PORT is NOT externally reachable"
            fi
            
            # HTTP/HTTPS test from external IP
            if command -v curl &> /dev/null; then
                echo "Testing external HTTP/HTTPS:"
                
                # Try HTTP
                if timeout 10 curl -s -o /dev/null -w "%{http_code}" http://$SERVER_IP:$PANEL_PORT 2>/dev/null | grep -q "200\|301\|302\|401\|403"; then
                    check_status 0 "External HTTP access to $SERVER_IP:$PANEL_PORT works"
                else
                    check_status 1 "External HTTP access to $SERVER_IP:$PANEL_PORT failed"
                fi
                
                # Try HTTPS
                if timeout 10 curl -k -s -o /dev/null -w "%{http_code}" https://$SERVER_IP:$PANEL_PORT 2>/dev/null | grep -q "200\|301\|302\|401\|403"; then
                    check_status 0 "External HTTPS access to $SERVER_IP:$PANEL_PORT works"
                else
                    check_status 1 "External HTTPS access to $SERVER_IP:$PANEL_PORT failed"
                fi
            fi
        fi
    else
        log_warn "Server IP not configured, skipping external connectivity tests"
    fi
    
    echo ""
}

# Check Docker logs
check_docker_logs() {
    echo "=== 8. Checking Docker Logs ==="
    
    if docker ps --filter "name=3x-ui" --format "{{.Names}}" | grep -q "3x-ui"; then
        log_info "Last 20 lines of 3x-ui container logs:"
        docker logs --tail 20 3x-ui
    else
        log_error "Cannot check logs - container not running"
    fi
    
    echo ""
}

# Generate summary and recommendations
generate_summary() {
    echo "=== 9. Summary and Recommendations ==="
    
    log_info "Quick access information:"
    if [[ -n "$SERVER_IP" && -n "$PANEL_PORT" ]]; then
        echo "Panel URL: http://$SERVER_IP:$PANEL_PORT"
        echo "Panel URL (HTTPS): https://$SERVER_IP:$PANEL_PORT"
        echo "Username: ${PANEL_USER:-admin}"
        echo "VPN Port: ${VPN_PORT:-443}"
    fi
    
    echo ""
    log_info "Diagnostic commands for troubleshooting:"
    echo "1. Restart container: cd $INSTALL_DIR/docker && docker-compose restart"
    echo "2. View logs: cd $INSTALL_DIR/docker && docker-compose logs -f"
    echo "3. Check container status: docker ps -a | grep 3x-ui"
    echo "4. Check port mapping: docker port 3x-ui"
    echo "5. Test local connectivity: curl -v http://127.0.0.1:${PANEL_PORT:-2053}"
    echo "6. Check firewall: iptables -L INPUT -v -n | grep ${PANEL_PORT:-2053}"
    
    echo ""
    log_info "Common issues and solutions:"
    echo "- If ports not reachable: Check firewall rules and Docker port mapping"
    echo "- If HTTP works but HTTPS doesn't: Check SSL certificate configuration"
    echo "- If localhost works but external doesn't: Check iptables FORWARD rules"
    echo "- If nothing works: Check if container is running and restart if needed"
}

# Main function
main() {
    clear
    echo -e "${GREEN}"
    echo "================================================================="
    echo "              VLESS Server Diagnostic Tool"
    echo "================================================================="
    echo -e "${NC}"
    
    check_installation
    load_config
    check_docker_container
    check_port_mapping
    check_firewall_rules
    check_localhost_connectivity
    check_external_connectivity
    check_docker_logs
    generate_summary
    
    echo -e "${GREEN}Diagnostic complete!${NC}"
}

# Run main function
main "$@"
