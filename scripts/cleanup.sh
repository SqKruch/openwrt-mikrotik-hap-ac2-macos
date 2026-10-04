#!/bin/bash
# Undo the macOS netboot setup after OpenWrt is installed.
# Run with: sudo bash scripts/cleanup.sh
set -u

# ---- EDIT IF NEEDED ----
IFACE="en10"
# ------------------------

echo "[*] stopping dnsmasq"; pkill -9 -f dnsmasq 2>/dev/null
echo "[*] stopping tcpdump"; pkill -9 tcpdump 2>/dev/null
echo "[*] disabling macOS tftpd"
launchctl bootout system /System/Library/LaunchDaemons/tftp.plist 2>/dev/null \
  || launchctl unload -w /System/Library/LaunchDaemons/tftp.plist 2>/dev/null
echo "[*] removing temporary image from /private/tftpboot"
rm -f /private/tftpboot/openwrt-*.bin 2>/dev/null
echo "[*] $IFACE -> DHCP (will get an address from OpenWrt)"
ipconfig set "$IFACE" DHCP
echo "[OK] Done. Connect to a LAN port and open your router's LuCI in a browser."
