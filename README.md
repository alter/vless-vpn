# VLESS Server Installation Guide
## Complete Setup with 3x-ui Panel and Reality Protocol

## 🚀 Quick Start Guide

### **One-Line Installation:**
```bash
# Download and run installer
curl -L "https://raw.githubusercontent.com/alter/vless-vpn/refs/heads/main/vless_auto_installer.sh?token=GHSAT0AAAAAADFS2AU7OQVF5IPVB7SEZ2VS2CSUZXQ" | sudo bash
```

### **With Domain Configuration:**
```bash
# Download installer
curl -L -o vless_auto_installer.sh "https://raw.githubusercontent.com/alter/vless-vpn/refs/heads/main/vless_auto_installer.sh?token=GHSAT0AAAAAADFS2AU7OQVF5IPVB7SEZ2VS2CSUZXQ"
chmod +x vless_auto_installer.sh

# Run with domain
sudo DOMAIN=your-domain.com EMAIL=admin@domain.com ./vless_auto_installer.sh
```

### **Quick Diagnostic:**
```bash
# Download and run diagnostic
curl -L "https://raw.githubusercontent.com/alter/vless-vpn/refs/heads/main/vless_diagnostic.sh?token=GHSAT0AAAAAADFS2AU6JBIWAM3LKKROG5C22CSU2VQ" | sudo bash
```

---

## 📋 Table of Contents

1. [System Requirements](#system-requirements)
2. [Installation](#installation)
3. [Post-Installation Setup](#post-installation-setup)
4. [Creating Inbounds](#creating-inbounds)
5. [Creating Clients](#creating-clients)
6. [Diagnostics](#diagnostics)
7. [Client Configuration](#client-configuration)
8. [Troubleshooting](#troubleshooting)
9. [Maintenance](#maintenance)

---

## 🔧 System Requirements

### **Minimum Requirements:**
- **OS:** Ubuntu 22.04+ or Debian 11+
- **RAM:** 1GB (2GB recommended)
- **Storage:** 10GB available space
- **Network:** External IP address
- **Ports:** 443, 2053 (or alternative ports)

### **Prerequisites:**
- Root access to the server
- Docker installed and running
- Basic firewall configuration

### **Check Docker Installation:**
```bash
docker --version
docker-compose --version

# If not installed:
curl -fsSL https://get.docker.com | sh
systemctl enable docker && systemctl start docker
```

---

## 🚀 Installation

### **1. Download Installation Script**
```bash
# Download the auto-installer
curl -O "https://raw.githubusercontent.com/alter/vless-vpn/refs/heads/main/vless_auto_installer.sh?token=GHSAT0AAAAAADFS2AU7OQVF5IPVB7SEZ2VS2CSUZXQ"
mv "vless_auto_installer.sh?token=GHSAT0AAAAAADFS2AU7OQVF5IPVB7SEZ2VS2CSUZXQ" vless_auto_installer.sh
chmod +x vless_auto_installer.sh

# Or using short command:
curl -L -o vless_auto_installer.sh "https://raw.githubusercontent.com/alter/vless-vpn/refs/heads/main/vless_auto_installer.sh?token=GHSAT0AAAAAADFS2AU7OQVF5IPVB7SEZ2VS2CSUZXQ"
chmod +x vless_auto_installer.sh
```

### **2. Download Diagnostic Script (Optional)**
```bash
# Download diagnostic script
curl -L -o vless_diagnostic.sh "https://raw.githubusercontent.com/alter/vless-vpn/refs/heads/main/vless_diagnostic.sh?token=GHSAT0AAAAAADFS2AU6JBIWAM3LKKROG5C22CSU2VQ"
chmod +x vless_diagnostic.sh
```

### **2. Run Installation**
```bash
# Basic installation (auto-detects ports)
sudo ./vless_auto_installer.sh

# With custom configuration
sudo DOMAIN=your-domain.com EMAIL=admin@domain.com ./vless_auto_installer.sh
```

### **3. Installation Process**
The installer will:
- ✅ Detect available ports (prioritizes 443 for VPN, 2053 for panel)
- ✅ Check for existing installations
- ✅ Install 3x-ui via Docker
- ✅ Configure firewall rules
- ✅ Create SSL certificates (self-signed if no domain)
- ✅ Set up management scripts

### **4. Installation Output**
```
=== Installation Summary ===
VPN Port: 443 (configure VLESS clients to connect here)
Panel URL: https://YOUR_IP:2053
Username: admin
Password: GENERATED_PASSWORD
Installation: Docker
```

**⚠️ Important:** Save the generated password immediately!

---

## ⚙️ Post-Installation Setup

### **1. Access the Web Panel**
```
URL: http://YOUR_SERVER_IP:2053
Username: admin
Password: admin123 (if reset) or generated password
```

### **2. Change Default Credentials**
1. Login to panel
2. **Panel Settings** → **Panel Configuration**
3. Change **Username** and **Password**
4. **Save** settings

### **3. Configure Access Logging**
1. **Panel Settings** → **Xray Configs**
2. Add logging configuration:
```json
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  }
}
```

---

## 🔗 Creating Inbounds

### **What is an Inbound?**
An inbound defines a listening port and protocol configuration. Each inbound can contain multiple clients (users).

### **1. Create New Inbound via Web Panel**

1. **Open Panel** → **Inbounds** → **Add Inbound**

2. **Basic Settings:**
   - **Remark:** `Main VLESS Server`
   - **Protocol:** `vless`
   - **Listen IP:** Leave empty (0.0.0.0)
   - **Port:** `443`
   - **Total GB:** `0` (unlimited)
   - **Expiry Time:** Leave empty (no expiration)

3. **Client Configuration:**
   - **Email:** `first.user@example.com`
   - **UUID:** Auto-generated
   - **Flow:** `xtls-rprx-vision`
   - **Limit IP:** `2` (simultaneous connections)
   - **Total GB:** `0` (unlimited traffic)
   - **Expiry Time:** Set to 10 years from now (e.g., `2035-06-18`)

4. **Stream Settings:**
   - **Network:** `tcp`
   - **Security:** `reality`

5. **🔑 Reality Settings (CRITICAL):**
   - **Dest:** `www.microsoft.com:443`
   - **Server Names:** `["www.microsoft.com"]`
   - **Private Key:** Click **"Generate"** button ⚠️
   - **Short IDs:** `["", "0123456789abcdef"]`

6. **Sniffing:**
   - **Enabled:** ✅
   - **Dest Override:** `["http", "tls"]`

### **2. Create Inbound via Command Line**
```bash
python3 /opt/vless-manager/scripts/user_manager.py \
  --panel-url http://YOUR_IP:2053 \
  --username admin \
  --password YOUR_PASSWORD \
  create \
  --email user@example.com \
  --traffic 0 \
  --days 3650 \
  --max-ips 2
```

**Parameters:**
- `--traffic 0` = Unlimited traffic
- `--days 3650` = 10 years validity
- `--max-ips 2` = 2 simultaneous devices

---

## 👥 Creating Clients

### **Method 1: Add Client to Existing Inbound**

1. **Inbounds** → Find your inbound → **View**
2. **Clients** section → **Add Client**
3. **Client Settings:**
   - **Email:** `newuser@example.com`
   - **UUID:** Auto-generated
   - **Enable:** ✅
   - **Limit IP:** `2`
   - **Total GB:** `0` (unlimited)
   - **Expiry Time:** `2035-06-18` (10 years)
   - **Telegram ID:** (optional)
   - **Subscription ID:** (optional)

### **Method 2: Command Line Client Creation**
```bash
# Create new client in existing inbound
python3 /opt/vless-manager/scripts/user_manager.py \
  --panel-url http://YOUR_IP:2053 \
  --username admin \
  --password YOUR_PASSWORD \
  create \
  --email client2@example.com \
  --traffic 0 \
  --days 3650 \
  --max-ips 3
```

### **Client Configuration Export**
After creating a client:
1. **Find the client** in the inbounds list
2. **Copy configuration:**
   - 📱 **QR Code** - for mobile apps
   - 🔗 **Copy Link** - vless:// URL
   - 📋 **Subscription** - for auto-update

---

## 🔍 Diagnostics

### **Run Diagnostic Script**
```bash
# If downloaded separately
sudo ./vless_diagnostic.sh

# Or if installed via auto-installer
sudo /opt/vless-manager/scripts/vless_diagnostic.sh

# Download and run directly
curl -L -o vless_diagnostic.sh "https://raw.githubusercontent.com/alter/vless-vpn/refs/heads/main/vless_diagnostic.sh?token=GHSAT0AAAAAADFS2AU6JBIWAM3LKKROG5C22CSU2VQ"
chmod +x vless_diagnostic.sh
sudo ./vless_diagnostic.sh
```

### **Manual Diagnostics**
```bash
# Check Docker container status
docker ps | grep 3x-ui

# View container logs
docker logs 3x-ui --tail 20

# Check port mapping
docker port 3x-ui

# Test local connectivity
curl -v http://127.0.0.1:2053

# Check active connections
netstat -an | grep :443 | grep ESTABLISHED

# Monitor real-time logs
docker logs 3x-ui --follow
```

### **Common Diagnostic Outputs**

**✅ Healthy System:**
```
✓ Panel port 2053 is reachable via TCP
✓ Panel HTTP on port 2053 responds  
✓ VPN port 443 is externally reachable
✓ External HTTP access works
```

**❌ Common Issues:**
```
✗ Panel HTTPS on port 2053 does not respond (normal for HTTP-only setup)
✗ VPN port 443 is NOT externally reachable (firewall issue)
```

---

## 📱 Client Configuration

### **Recommended Clients**

**macOS:**
- **Streisand** (recommended for macOS)
- **ClashX Pro** 
- **V2rayU** (native client)
- **Hiddify** (cross-platform)

**Android:**
- **Hiddify** (recommended for Android)
- **v2rayNG**

**Windows:**
- **v2rayN**
- **Hiddify**

**iOS:**
- **Hiddify**
- **Streisand** (if available)

### **Configuration Process**

1. **Get configuration** from web panel (QR code or vless:// link)
2. **Import into client:**
   - Scan QR code, or
   - Paste vless:// URL, or
   - Add subscription URL
3. **Connect** and verify IP change

### **Sample Configuration URL**
```
vless://uuid@server:443?security=reality&sni=www.microsoft.com&fp=chrome&type=tcp&flow=xtls-rprx-vision#user@example.com
```

---

## 🚨 Troubleshooting

### **Installation Issues**

**Problem:** Port conflicts
```bash
# Check occupied ports
netstat -tuln | grep -E ':(443|2053)'

# Use alternative ports
VPN_PORT=8443 PANEL_PORT=3000 ./vless_auto_installer.sh
```

**Problem:** Docker not found
```bash
# Install Docker
curl -fsSL https://get.docker.com | sh
systemctl enable docker && systemctl start docker
```

### **Connection Issues**

**Problem:** Can't access panel
```bash
# Check if container is running
docker ps | grep 3x-ui

# Restart container
cd /opt/vless-manager/docker && docker-compose restart

# Check firewall
iptables -L INPUT -v -n | grep 2053
```

**Problem:** VPN connects but no internet
```bash
# Check NAT rules
iptables -t nat -L POSTROUTING -v -n | grep MASQUERADE

# Fix NAT rules
./fix_nat_rules.sh
```

**Problem:** "Invalid privateKey" error
1. **Edit inbound** in panel
2. **Reality Settings** → **Generate** new keys
3. **Save** configuration

### **Reality Protocol Issues**

**Problem:** Connection fails with Reality
- Ensure **Dest** is `www.microsoft.com:443`
- **Server Names** must be `["www.microsoft.com"]`
- **Private/Public keys** must be freshly generated
- Client must support **Reality** protocol

### **Client Expiration Issues**

**Problem:** "Ended" status in panel
1. **Edit client**
2. **Expiry Time** → Set to `2035-06-18`
3. **Save**

---

## 🔧 Maintenance

### **Regular Tasks**

**Weekly:**
```bash
# Check system status
/opt/vless-manager/scripts/info.sh

# View recent connections
docker logs 3x-ui | grep "accepted" | tail -10
```

**Monthly:**
```bash
# Create backup
/opt/vless-manager/scripts/backup.sh

# Check disk space
df -h /

# Update system packages
apt update && apt upgrade
```

### **Management Scripts**

**Available scripts:**
```bash
/opt/vless-manager/scripts/info.sh              # Server information
/opt/vless-manager/scripts/user_manager.py      # User management
/opt/vless-manager/scripts/monitor.sh           # System monitoring
/opt/vless-manager/scripts/backup.sh            # Create backup
/opt/vless-manager/scripts/uninstall.sh         # Remove everything
/opt/vless-manager/scripts/vless_diagnostic.sh  # Full diagnostics
```

### **Docker Management**
```bash
cd /opt/vless-manager/docker

# View logs
docker-compose logs -f

# Restart service
docker-compose restart

# Stop service
docker-compose down

# Start service
docker-compose up -d

# Update image
docker-compose pull && docker-compose up -d
```

### **Backup and Restore**

**Create backup:**
```bash
/opt/vless-manager/scripts/backup.sh
```

**Restore from backup:**
```bash
# Stop service
cd /opt/vless-manager/docker && docker-compose down

# Extract backup
tar -xzf /opt/vless-manager/backups/backup_YYYYMMDD_HHMMSS.tar.gz -C /

# Start service
docker-compose up -d
```

---

## 📋 Important Notes

### **🔑 Critical Security Points:**
1. **Always generate new Reality keys** - never reuse
2. **Set client expiry to 10 years** (not 0 which means immediate expiry)
3. **Use strong passwords** for panel access
4. **Limit IP connections** per client (2-3 devices)
5. **Monitor logs** for suspicious activity

### **🔧 Best Practices:**
1. **Use port 443** for VPN (looks like normal HTTPS)
2. **Use Reality protocol** for best obfuscation
3. **Set traffic to 0** for unlimited bandwidth
4. **Regular backups** of configuration
5. **Monitor server resources** (CPU, RAM, disk)

### **📱 Client Recommendations:**
- **macOS:** Streisand (primary choice) or ClashX Pro
- **Android:** Hiddify (best for Android)
- **Windows:** v2rayN or Hiddify  
- **iOS:** Hiddify
- **Router:** HomeProxy on OpenWrt

---

## 📞 Support Commands

### **Quick Diagnostics:**
```bash
# One-line health check
curl -s http://localhost:2053 > /dev/null && echo "Panel OK" || echo "Panel FAIL"

# Check VPN port
nc -zv localhost 443 && echo "VPN port OK" || echo "VPN port FAIL"

# Container status
docker ps | grep 3x-ui && echo "Container running" || echo "Container stopped"
```

### **Emergency Recovery:**
```bash
# Reset panel password
docker exec 3x-ui /app/x-ui setting -username admin -password admin123

# Restart everything
cd /opt/vless-manager/docker && docker-compose restart

# Full reinstall (if needed)
/opt/vless-manager/scripts/uninstall.sh
./vless_auto_installer.sh
```

---

**🎉 Congratulations! You now have a fully functional VLESS server with Reality protocol obfuscation.**

For additional support or updates, check the project repository or run the diagnostic script for detailed system analysis.
