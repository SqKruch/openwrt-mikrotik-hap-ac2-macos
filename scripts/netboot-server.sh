#!/bin/bash
# Netboot server for installing OpenWrt on a MikroTik hAP ac2 — from macOS.
# DHCP/BOOTP via dnsmasq + TFTP via the macOS built-in tftpd (the combo that works).
# Run with: sudo bash scripts/netboot-server.sh   — keep this window open.
set -u

# ---- EDIT THESE ----
IFACE="en10"                                   # your USB/Thunderbolt Ethernet interface
INITRAMFS="$HOME/owrt/openwrt-initramfs-kernel.bin"  # path to the *initramfs-kernel.bin*
SERVER_IP="192.168.77.1"                       # Mac side; kept off 192.168.1.x on purpose
# --------------------

DNSMASQ="$(command -v dnsmasq || echo /opt/homebrew/sbin/dnsmasq)"
IMG_NAME="$(basename "$INITRAMFS")"
TFTPBOOT="/private/tftpboot"
LOG="/tmp/dnsmasq-netboot.log"

[ -f "$INITRAMFS" ] || { echo "ERROR: initramfs not found: $INITRAMFS"; exit 1; }
[ -x "$DNSMASQ" ]   || { echo "ERROR: dnsmasq not found — run: brew install dnsmasq"; exit 1; }

echo "[*] stopping any previous dnsmasq/tcpdump"
pkill -9 -f dnsmasq 2>/dev/null; sleep 1

echo "[*] $IFACE -> $SERVER_IP/24"
ipconfig set "$IFACE" MANUAL "$SERVER_IP" 255.255.255.0
for i in 1 2 3 4 5 6 7 8; do [ "$(ipconfig getifaddr "$IFACE" 2>/dev/null)" = "$SERVER_IP" ] && break; sleep 1; done
echo "[*] $IFACE is now: $(ipconfig getifaddr "$IFACE" 2>/dev/null)"

echo "[*] placing image in $TFTPBOOT (served by macOS tftpd)"
mkdir -p "$TFTPBOOT"; cp -f "$INITRAMFS" "$TFTPBOOT/"; chmod 644 "$TFTPBOOT/$IMG_NAME"

echo "[*] enabling macOS tftpd"
launchctl enable system/com.apple.tftpd 2>/dev/null
launchctl bootstrap system /System/Library/LaunchDaemons/tftp.plist 2>/dev/null
launchctl load -w /System/Library/LaunchDaemons/tftp.plist 2>/dev/null
sleep 1
echo "[*] UDP/69 listeners (expect '*.69'):"
netstat -an -p udp 2>/dev/null | grep '\.69 ' | head

: > "$LOG"; chmod 666 "$LOG"
echo "[*] starting dnsmasq (DHCP/BOOTP only; TFTP handled by macOS tftpd)."
echo "    Log: $LOG   — leave this window open, then power-cycle the router."
echo "------------------------------------------------------------------"
exec "$DNSMASQ" --conf-file=/dev/null --keep-in-foreground --user=root -p0 \
  --interface="$IFACE" --bind-dynamic \
  --dhcp-authoritative --no-ping \
  --dhcp-range=192.168.77.100,192.168.77.200 \
  --bootp-dynamic \
  --dhcp-boot="$IMG_NAME",,"$SERVER_IP" \
  --log-dhcp --log-facility="$LOG"
