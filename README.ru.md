# Установка OpenWrt на MikroTik hAP ac² — с macOS

Прошивка **OpenWrt** на **MikroTik hAP ac²** (`RBD52G-5HacD2HnD`, ipq40xx) **только с Mac** — без Linux-виртуалки, без Windows, без MikroTik Netinstall.

> 🇬🇧 English version: [README.md](README.md)

## Зачем это

Страница устройства hAP ac2 в вики OpenWrt удалена, а почти все остальные гайды рассчитаны на Linux с `dnsmasq`. На macOS привычный способ «`dnsmasq` раздаёт и DHCP, и TFTP» **выглядит рабочим, но образ по факту не передаётся** — по двум неочевидным причинам:

1. **TFTP-сервер dnsmasq не слушает адрес интерфейса.** С `--bind-interfaces` он слушает только loopback/IPv6, и TFTP-запрос загрузчика на `192.168.77.1:69` упирается в **ICMP «port 69 unreachable»**. (Лечится `--bind-dynamic`.)
2. **Ломается согласование размера блока TFTP.** Даже когда сервер отвечает, передача обрывается на **`error 4 Illegal TFTP Operation`**.

Рабочая на macOS комбинация:

> **`dnsmasq` — только DHCP/BOOTP + встроенный в macOS `tftpd` — для передачи файла по TFTP.**

Системный `tftpd` слушает wildcard-сокет (нет проблемы привязки) и уважает запрошенный загрузчиком размер блока — образ доходит целиком.

---

## Что нужно

- MikroTik **hAP ac²** (`RBD52G-5HacD2HnD`). Проверено на RouterOS 6.49.x, но метод от версии не зависит.
- **Mac** с **Homebrew**.
- **USB/Thunderbolt Ethernet-адаптер** и кабель (весь процесс — по проводу).
- ~15 минут.

⚠️ **Это полностью заменяет RouterOS.** До команды `sysupgrade` OpenWrt живёт только в оперативке — любое выключение питания возвращает RouterOS, пока вы не прошили. Откат возможен позже через MikroTik Netinstall (в конце).

Везде замените **`en10`** на имя вашего адаптера (`ifconfig` или Системные настройки → Сеть; это тот интерфейс, что становится *active* при подключении кабеля к роутеру).

---

## Шаг 1 — Скачать образы OpenWrt

Берём текущий релиз с <https://downloads.openwrt.org/releases/> → `targets/ipq40xx/mikrotik/`. Нужны **два** файла:

| Назначение | Файл |
|---|---|
| Netboot (в оперативку) | `openwrt-<ver>-ipq40xx-mikrotik-mikrotik_hap-ac2-initramfs-kernel.bin` |
| Постоянный (во флеш) | `openwrt-<ver>-ipq40xx-mikrotik-mikrotik_hap-ac2-squashfs-sysupgrade.bin` |

```sh
mkdir -p ~/owrt && cd ~/owrt
VER=24.10.0   # <-- укажите вашу версию
curl -fLO https://downloads.openwrt.org/releases/$VER/targets/ipq40xx/mikrotik/openwrt-$VER-ipq40xx-mikrotik-mikrotik_hap-ac2-initramfs-kernel.bin
curl -fLO https://downloads.openwrt.org/releases/$VER/targets/ipq40xx/mikrotik/openwrt-$VER-ipq40xx-mikrotik-mikrotik_hap-ac2-squashfs-sysupgrade.bin
shasum -a 256 *.bin   # сверьте с файлом sha256sums в той же папке
```

## Шаг 2 — Установить dnsmasq

```sh
brew install dnsmasq
```

## Шаг 3 — Запустить netboot-сервер

Поправьте переменные в начале [`scripts/netboot-server.sh`](scripts/netboot-server.sh) (`IFACE`, `INITRAMFS`) и запустите **через sudo**. Скрипт задаёт статический IP на адаптере, кладёт initramfs туда, откуда его отдаёт системный `tftpd`, поднимает `tftpd` и запускает `dnsmasq` (DHCP/BOOTP) в переднем плане:

```sh
sudo bash scripts/netboot-server.sh
```

Окно **не закрывайте** (dnsmasq работает в переднем плане). Должно написать, что `tftpd` слушает `*.69`.

> Ключевое отличие от Linux-гайдов: `dnsmasq … --bind-dynamic --no-ping --bootp-dynamic --dhcp-boot=<initramfs>,,192.168.77.1` **без** `--enable-tftp`; файл отдаёт системный `tftpd`.

## Шаг 4 — Перевести роутер в режим netboot

Два варианта:

**A. Из RouterOS (надёжно), со стороны LAN:** зайдите на роутер как обычно (`192.168.88.1`, Winbox/SSH) и выполните:
```
/system routerboard settings set boot-device=try-ethernet-once-then-nand boot-protocol=bootp
```
Важно `bootp`: после RouterOS 6.46.6 MikroTik изменил netboot по DHCP, **надёжен именно BOOTP**.

**B. Кнопка Reset («Etherboot»):** выключить питание, зажать **Reset**, подать питание не отпуская, держать ~15–20 с до входа в сетевую загрузку, отпустить.

## Шаг 5 — Загрузить OpenWrt по сети

1. Подключите кабель Mac к порту **`ether1`** роутера (WAN — netboot идёт только через него).
2. С запущенным netboot-сервером (Шаг 3) **передёрните питание** роутера (выдернуть, ~5 с, воткнуть).
3. Смотрите окно сервера / `sudo tcpdump -i en10 'port 69 or port 67'`. Должно быть: BOOTP → передача initramfs по TFTP.
4. Через ~30–60 с роутер работает на **OpenWrt в оперативке**. В логе dnsmasq будет видно повторный DHCP-запрос с именем хоста **`OpenWrt`**.

⚠️ **Не выключайте питание** до Шага 6 — OpenWrt только в оперативке.

## Шаг 6 — Зайти в OpenWrt и прошить навсегда

LAN у OpenWrt — `192.168.1.1` на **LAN-портах (ether2‑5)**, не на `ether1`.

1. **Переткните кабель из `ether1` в LAN-порт (`ether2`‑`ether5`).**
2. Зайдите в OpenWrt. Дефолтный `192.168.1.1` часто конфликтует с домашней сетью, поэтому надёжнее всего **IPv6 link-local** (без конфликта IPv4):
   ```sh
   ping6 -c3 ff02::1%en10          # найти соседей
   ndp -an | grep en10            # найти адрес роутера fe80::…
   ssh root@'fe80::XXXX:XXXX:XXXX:XXXX%en10'   # OpenWrt initramfs: root без пароля (просто Enter)
   ```
   (Или, если `192.168.1.x` у вас свободна: `sudo ipconfig set en10 MANUAL 192.168.1.2 255.255.255.0` и используйте `192.168.1.1`.)
3. Передайте **sysupgrade**-образ на роутер и прошейте. `scp` может не сработать (в initramfs часто нет SFTP) — надёжнее передать через SSH:
   ```sh
   LL='fe80::XXXX:XXXX:XXXX:XXXX%en10'
   cat ~/owrt/openwrt-*-squashfs-sysupgrade.bin | ssh root@"$LL" 'cat > /tmp/sysupgrade.bin'
   ssh root@"$LL" 'sha256sum /tmp/sysupgrade.bin'    # сверьте с суммой скачанного
   ssh root@"$LL" 'sysupgrade -n /tmp/sysupgrade.bin'
   ```
   SSH-сессия оборвётся с «Connection failed» — **это нормально** (`sysupgrade` закрывает все сессии и прошивает). ⚠️ **Не выключайте питание во время прошивки** (~1–3 мин), роутер перезагрузится сам.
4. После перезагрузки — **постоянный OpenWrt с флеша**. Проверьте (overlay должен быть на флеше, не на tmpfs):
   ```sh
   ssh root@"$LL" 'mount | grep overlay'
   # ожидается:  /dev/mtdblock8 on /overlay type jffs2 …   и   overlayfs:/overlay on /
   ```

## Шаг 7 — Базовая настройка и очистка

На роутере (по link-local SSH):
```sh
passwd root                                   # задать пароль (нужен для входа в LuCI/SSH)
uci set network.lan.ipaddr='192.168.9.1'      # опц.: увести LAN с 192.168.1.1, чтобы не конфликтовать с домашней сетью
uci commit network && /etc/init.d/network restart
```
На Mac остановите netboot-сервер и верните сеть — см. [`scripts/cleanup.sh`](scripts/cleanup.sh):
```sh
sudo bash scripts/cleanup.sh
```
Потом откройте **http://192.168.9.1** (или ваш LAN-IP), логин `root`. LuCI входит в релизные образы. Wi-Fi радио есть, но по умолчанию выключены — включите в LuCI (Network → Wireless).

---

## Почему TFTP в dnsmasq не работает на macOS (диагностика)

Если хотите разобраться сами — вот точные симптомы и как их увидеть:

- **Ничего не передаётся, в логе dnsmasq про TFTP тишина.** `--dumpfile` в dnsmasq пишет только DHCP — снимайте *настоящий* дамп: `sudo tcpdump -i en10 -w /tmp/cap.pcap` во время попытки.
- В дампе видно, как роутер шлёт `TFTP RRQ …` на `192.168.77.1:69`, а Mac отвечает **`ICMP udp port 69 unreachable`** → никто не слушает. `netstat -an -p udp | grep '\.69 '` покажет, что TFTP dnsmasq привязан только к `127.0.0.1`/IPv6, **не** к адресу адаптера. Виноват `--bind-interfaces`; лечит `--bind-dynamic`.
- После этого передача начинается, но обрывается на **`error 4 Illegal TFTP Operation`** около ~900-го блока. `--tftp-no-blocksize` помогает лишь отчасти. Надёжно — отдать файл **системным `tftpd`** (он уважает `blksize 1452` и дотягивает до конца).

Прочие грабли:
- Для netboot на RouterOS > 6.46.6 используйте **BOOTP**, не DHCP.
- **Файрвол приложений macOS** не должен блокировать сервер (по умолчанию выключен).
- Мигание линка при передёргивании питания может сбросить *вручную заданный* IP на адаптере; `--bind-dynamic` перепривязывается, когда адрес возвращается.

## Откат на RouterOS

До `sysupgrade` netboot не трогает NAND — передёргивание питания вернёт RouterOS. После прошивки верните RouterOS официальным **MikroTik Netinstall** (Windows/Linux): введите роутер в Etherboot (кнопка Reset), укажите Netinstall на `.npk` RouterOS `arm`, Install.

## Благодарности

Написано по реальной, рабочей установке OpenWrt 25.12.5 на hAP ac2 с macOS. Правки и другие модели MikroTik на ipq40xx приветствуются — присылайте PR.

## Лицензия

**CC BY-NC 4.0** — [Creative Commons Attribution‑NonCommercial 4.0 International](https://creativecommons.org/licenses/by-nc/4.0/). См. [LICENSE](LICENSE).

Можно использовать, распространять и изменять этот гайд и скрипты в **некоммерческих** целях с указанием авторства. **Коммерческое использование запрещено.**

© 2026 SqKruch
