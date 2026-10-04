# Install OpenWrt on a MikroTik hAP ac² — from macOS

Flash **OpenWrt** onto a **MikroTik hAP ac²** (`RBD52G-5HacD2HnD`, ipq40xx) using **only a Mac** — no Linux VM, no Windows, no MikroTik Netinstall.

> 🇷🇺 Русская версия: [README.ru.md](README.ru.md)

## Why this guide exists

The OpenWrt device page for the hAP ac2 is gone, and almost every other guide assumes a Linux PC running `dnsmasq`. On macOS the usual "`dnsmasq` does both DHCP and TFTP" approach **looks like it works but silently fails to deliver the image**, in two subtle ways:

1. **dnsmasq's TFTP server doesn't bind the interface IP.** With `--bind-interfaces` it ends up listening only on loopback/IPv6, so the router's TFTP request to `192.168.77.1:69` gets an **ICMP "port 69 unreachable"**. (Fix: `--bind-dynamic`.)
2. **TFTP block‑size negotiation breaks.** Even once it answers, dnsmasq's TFTP aborts the transfer with **`error 4 Illegal TFTP Operation`** partway through.

The combination that **actually works on macOS**:

> **`dnsmasq` for DHCP/BOOTP only + the macOS built‑in `tftpd` for the TFTP transfer.**

macOS's native `tftpd` listens on a wildcard socket (no bind problem) and honors the router's requested block size, so the image transfers completely.

---

## What you need

- MikroTik **hAP ac²** (`RBD52G-5HacD2HnD`). This guide is written for RouterOS 6.49.x on the device, but the method is firmware‑agnostic.
- A **Mac** with **Homebrew**.
- A **USB/Thunderbolt Ethernet adapter** + an Ethernet cable. (The whole process is wired.)
- ~15 minutes.

⚠️ **This replaces RouterOS entirely.** Until you run `sysupgrade`, OpenWrt only runs from RAM, so any power‑cycle brings RouterOS back — nothing is lost until the final flash. It is reversible later via MikroTik Netinstall (see the end).

Throughout, replace **`en10`** with your adapter's interface name (find it with `ifconfig` / System Settings → Network; it's the one that goes *active* when you plug the cable into the router).

---

## Step 1 — Download the OpenWrt images

Pick the current release from <https://downloads.openwrt.org/releases/> → `targets/ipq40xx/mikrotik/`. You need **two** files:

| Purpose | File |
|---|---|
| Netboot (runs in RAM) | `openwrt-<ver>-ipq40xx-mikrotik-mikrotik_hap-ac2-initramfs-kernel.bin` |
| Permanent (flashed) | `openwrt-<ver>-ipq40xx-mikrotik-mikrotik_hap-ac2-squashfs-sysupgrade.bin` |

```sh
mkdir -p ~/owrt && cd ~/owrt
VER=24.10.0   # <-- set to the version you downloaded
curl -fLO https://downloads.openwrt.org/releases/$VER/targets/ipq40xx/mikrotik/openwrt-$VER-ipq40xx-mikrotik-mikrotik_hap-ac2-initramfs-kernel.bin
curl -fLO https://downloads.openwrt.org/releases/$VER/targets/ipq40xx/mikrotik/openwrt-$VER-ipq40xx-mikrotik-mikrotik_hap-ac2-squashfs-sysupgrade.bin
# verify against the sha256sums file in the same directory:
shasum -a 256 *.bin
```

## Step 2 — Install dnsmasq

```sh
brew install dnsmasq
```

## Step 3 — Start the netboot server

Edit the variables at the top of [`scripts/netboot-server.sh`](scripts/netboot-server.sh) (`IFACE`, `INITRAMFS`) and run it **with sudo**. It sets a static IP on your adapter, puts the initramfs where macOS `tftpd` serves it, starts macOS `tftpd`, and runs `dnsmasq` for DHCP/BOOTP in the foreground:

```sh
sudo bash scripts/netboot-server.sh
```

Leave this window **open** (dnsmasq runs in the foreground). It should print that `tftpd` is listening on `*.69`.

> The script uses: `dnsmasq … --bind-dynamic --no-ping --bootp-dynamic --dhcp-boot=<initramfs>,,192.168.77.1` **without** `--enable-tftp`; the macOS `tftpd` serves the file instead. This is the key difference from Linux guides.

## Step 4 — Put the router into netboot mode

Two options:

**A. From RouterOS (reliable), over the LAN side:** connect to the router normally (e.g. `192.168.88.1`, Winbox/SSH) and set:
```
/system routerboard settings set boot-device=try-ethernet-once-then-nand boot-protocol=bootp
```
`bootp` matters — MikroTik changed DHCP netboot behavior after RouterOS 6.46.6; **BOOTP is the reliable mode**.

**B. Reset‑button "Etherboot":** power off, hold **Reset**, apply power while holding, keep holding ~15–20 s until it enters net‑boot, release.

## Step 5 — Boot OpenWrt over the network

1. Connect the Mac's Ethernet cable to the router's **`ether1`** (the WAN port — netboot only happens there).
2. With the netboot server running (Step 3), **power‑cycle the router** (unplug power, ~5 s, plug back).
3. Watch the server window / `sudo tcpdump -i en10 'port 69 or port 67'`. You should see BOOTP → a TFTP transfer of the initramfs.
4. After ~30–60 s the router is running **OpenWrt in RAM**. You can confirm it from the dnsmasq log: it re‑requests DHCP with hostname **`OpenWrt`**.

⚠️ **Do not power‑cycle again** until after Step 6 — OpenWrt is only in RAM.

## Step 6 — Access OpenWrt and flash it permanently

OpenWrt's LAN is `192.168.1.1` on the **LAN ports (ether2‑5)**, not on `ether1`.

1. **Move the cable from `ether1` to a LAN port (`ether2`‑`ether5`).**
2. Reach OpenWrt. OpenWrt's default LAN IP (`192.168.1.1`) collides with many home networks, so the safest way is **IPv6 link‑local** (no IPv4 conflict):
   ```sh
   ping6 -c3 ff02::1%en10          # discover neighbors
   ndp -an | grep en10            # find the router's fe80::… address
   ssh root@'fe80::XXXX:XXXX:XXXX:XXXX%en10'   # OpenWrt initramfs: root, no password (just Enter)
   ```
   (Or, if `192.168.1.x` is free on your network: `sudo ipconfig set en10 MANUAL 192.168.1.2 255.255.255.0` and use `192.168.1.1`.)
3. Copy the **sysupgrade** image to the router and flash. `scp` may not work (OpenWrt initramfs often lacks an SFTP server) — piping over SSH is the most reliable:
   ```sh
   LL='fe80::XXXX:XXXX:XXXX:XXXX%en10'
   cat ~/owrt/openwrt-*-squashfs-sysupgrade.bin | ssh root@"$LL" 'cat > /tmp/sysupgrade.bin'
   ssh root@"$LL" 'sha256sum /tmp/sysupgrade.bin'    # compare with the downloaded sum
   ssh root@"$LL" 'sysupgrade -n /tmp/sysupgrade.bin'
   ```
   The SSH session drops with a "Connection failed" message — **that's normal** (`sysupgrade` kills all sessions, then flashes). ⚠️ **Do not cut power while it flashes** (~1–3 min); it reboots itself.
4. After it reboots it's running **permanent OpenWrt from flash**. Verify (overlay should be on flash, not tmpfs):
   ```sh
   ssh root@"$LL" 'mount | grep overlay'
   # expect:  /dev/mtdblock8 on /overlay type jffs2 …   and   overlayfs:/overlay on /
   ```

## Step 7 — First‑boot basics & clean up

On the router (via the link‑local SSH):
```sh
passwd root                                   # set a password (enables LuCI/SSH login)
uci set network.lan.ipaddr='192.168.9.1'      # optional: move LAN off 192.168.1.1 to avoid home-net clashes
uci commit network && /etc/init.d/network restart
```
On the Mac, stop the netboot server and restore networking — see [`scripts/cleanup.sh`](scripts/cleanup.sh):
```sh
sudo bash scripts/cleanup.sh
```
Then browse to **http://192.168.9.1** (or whatever LAN IP you set), log in as `root`. LuCI is included in release images. Wi‑Fi radios exist but are disabled by default — enable them in LuCI (Network → Wireless).

---

## Why dnsmasq's own TFTP fails on macOS (diagnosis notes)

If you prefer to debug it yourself, these are the exact symptoms and how to see them:

- **Nothing transfers, dnsmasq log is silent about TFTP.** dnsmasq's `--dumpfile` only logs DHCP, so run a *real* capture: `sudo tcpdump -i en10 -w /tmp/cap.pcap` during the attempt.
- In the capture you'll see the router send `TFTP RRQ …` to `192.168.77.1:69` and the Mac reply **`ICMP udp port 69 unreachable`** → nothing is listening there. `netstat -an -p udp | grep '\.69 '` shows dnsmasq's TFTP bound only to `127.0.0.1`/IPv6, **not** the adapter IP. Caused by `--bind-interfaces`; `--bind-dynamic` fixes the binding.
- After that fix the transfer starts but dies with **`error 4 Illegal TFTP Operation`** around block ~900. `--tftp-no-blocksize` helps a little but still fails. The reliable fix is to let **macOS `tftpd`** do the transfer (it honors the router's `blksize 1452` and completes).

Other gotchas:
- Use **BOOTP**, not DHCP, for netboot on RouterOS > 6.46.6.
- The macOS **Application Firewall** must not block the server (it's off by default).
- A link flap on power‑cycle can drop a *manually set* IP on the adapter; `--bind-dynamic` re‑binds when the address returns.

## Reverting to RouterOS

OpenWrt netboot never touches NAND until `sysupgrade`, so before that a power‑cycle restores RouterOS. After flashing, reinstall RouterOS with the official **MikroTik Netinstall** (Windows/Linux): put the router in Etherboot (Reset button), point Netinstall at a RouterOS `arm` `.npk`, Install.

## Credits

Written from a real, working macOS install of OpenWrt 25.12.5 on an hAP ac². Corrections and other ipq40xx MikroTik models welcome — open a PR.

## License

MIT — see [LICENSE](LICENSE).
