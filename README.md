# VLESS VPN - Easy Setup in 2 Minutes

## 🚀 Quick Install (Copy & Paste)

### Step 1: Install VPN Server
```bash
curl -L "https://raw.githubusercontent.com/alter/vless-vpn/main/vless_auto_installer.sh" | sudo bash
```

### Step 2: Get Your Password
After installation, run this command:
```bash
cat /opt/vless-manager/configs/server.conf
```

Write down these details:
- **PANEL_PORT** - port for web panel (usually 2053)
- **PANEL_USER** - username (usually admin)
- **PANEL_PASS** - password
- **VPN_PORT** - port for VPN (usually 443)

### Step 3: Open Web Panel
1. Open your browser
2. Go to: `https://YOUR_IP:PANEL_PORT`
   
   Example: `https://185.123.45.67:2053`
   
3. Browser will say "not secure" - click "Proceed anyway"
4. Login with username and password from the file above

---

## 📱 Create VPN for Your Phone

### In the Web Panel:

1. **Click "Inbounds"** → **"Add Inbound"** (blue + button)

2. **Fill in these fields:**
   - **Remark:** `MyVPN`
   - **Protocol:** select `vless`
   - **Port:** enter port from VPN_PORT (usually `443`)
   
3. **In Clients section:**
   - **Email:** `myphone@vpn.com` (any email)
   - **Limit IP:** `2` (how many devices at once)
   - **Expiry Time:** pick date 10 years from now
   
4. **In Stream Settings section:**
   - **Network:** select `tcp`
   - **Security:** select `reality`
   
5. **In Reality Settings section:**
   - **Click "Generate" button** (IMPORTANT!)
   - **Dest:** enter `www.microsoft.com:443`
   - **Server Names:** enter `www.microsoft.com`
   
6. **Click "Submit"** (save)

### Get QR Code for Phone:

1. Find your `MyVPN` in the Inbounds list
2. Click the **QR code** icon 📱
3. Scan with your phone

---

## 📲 Phone Apps

### iPhone:
Download **Hiddify** from App Store

### Android:
Download **Hiddify** from Google Play

### How to Connect:
1. Open the app
2. Tap "+" or "Add"
3. Scan QR code from panel
4. Tap "Connect"

---

## 🆘 If Something Doesn't Work

### View Logs:
```bash
cd /opt/vless-manager/docker && docker-compose logs
```

### Restart VPN:
```bash
cd /opt/vless-manager/docker && docker-compose restart
```

### Check Status:
```bash
/opt/vless-manager/scripts/info.sh
```

### Find Your IP Address:
```bash
curl -L -4 iprs.fly.dev
```

---

## ❓ Common Questions

**Q: What's the panel address?**
A: Check the file `/opt/vless-manager/configs/server.conf`

**Q: Forgot password?**
A: Run this command:
```bash
cat /opt/vless-manager/configs/server.conf | grep PANEL_PASS
```

**Q: Which port for VPN?**
A: Use VPN_PORT from config (usually 443)

**Q: Browser says "not secure"?**
A: That's normal, just click "Proceed anyway"

---

## 📝 Command Cheatsheet

```bash
# Show config with password
cat /opt/vless-manager/configs/server.conf

# Show server info
/opt/vless-manager/scripts/info.sh

# View logs
cd /opt/vless-manager/docker && docker-compose logs

# Restart
cd /opt/vless-manager/docker && docker-compose restart

# Get your IP
curl -L -4 iprs.fly.dev
```

---

## 🎯 Important to Remember:

1. **Save the password** after installation
2. **Port for VPN** is VPN_PORT (usually 443)
3. **Always click "Generate"** in Reality settings
4. **Expiry date** - set 10 years ahead, don't leave empty

---

That's it! Your VPN is ready to use 🎉
