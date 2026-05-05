<div align="center">

<img src="https://img.shields.io/badge/Telegram-MTProxy-2CA5E0?style=for-the-badge&logo=telegram&logoColor=white"/>

```
  +-+-+-+  +-+-+-+-+-+
  |M|T|P|  |P|r|o|x|y|
  +-+-+-+  +-+-+-+-+-+
```

**One-command Telegram MTProxy server installer**  
*Run the script — get a working proxy*

---

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Stars](https://img.shields.io/github/stars/sxcvio/Auto-MTProto?style=flat-square&color=yellow)](https://github.com/sxcvio/Auto-MTProto/stargazers)
[![Issues](https://img.shields.io/github/issues/sxcvio/Auto-MTProto?style=flat-square&color=red)](https://github.com/sxcvio/Auto-MTProto/issues)
[![OS](https://img.shields.io/badge/OS-Ubuntu%20%7C%20Debian%20%7C%20CentOS-orange?style=flat-square&logo=linux&logoColor=white)](#)
[![Author](https://img.shields.io/badge/Author-SXCVIO-9b59b6?style=flat-square)](https://github.com/sxcvio)

</div>

---

## ⚡ Quick Start

Paste one command on your server and you're done:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/sxcvio/Auto-MTProto/main/mtproxy-install.sh)
```

> [!IMPORTANT]
> Requires **root** privileges. If you are a regular user, prepend `sudo`.

---

## 🎬 What it looks like

```
  +-+-+-+  +-+-+-+-+-+
  |M|T|P|  |P|r|o|x|y|
  +-+-+-+  +-+-+-+-+-+

  Telegram MTProxy -- Automatic Installer
  ---------------------------------------
  Author: SXCVIO

  i  System: Ubuntu 24.04 LTS

  >> Analyzing server hardware

  +------------------------------------------------+
  |              Server characteristics            |
  +------------------------------------------------+
  |  CPU:            1 cores @ 2095 MHz            |
  |  Model:          Intel Xeon (Skylake)          |
  |  AES-NI:         yes (hardware AES)            |
  |  RAM total:      1.9 GB                        |
  |  RAM free:       1746 MB available             |
  |  Disk free:      17 GB                         |
  |  Network:        1000 Mbit/s (eth0)            |
  |  Load avg:       0.03                          |
  +------------------------------------------------+
  |        Capacity limits (conn -> users)         |
  +------------------------------------------------+
  |  CPU:            60000 conn -> ~12000 users    |
  |  RAM:            38195 conn -> ~7639 users     |
  |  Network:        ~850000 Kbps -> ~21250 users  |
  +------------------------------------------------+
  |  Connected:      ~7639 (hold session)          |
  |  Active:         ~763 (active ~10%)            |
  |  Workers:        1                             |
  |  Bottleneck:     RAM                           |
  |  Tier:           **-- Medium load              |
  +------------------------------------------------+

  i  Connected = idle sessions; Active = actually writing right now.
  i  Media (photos/video) goes direct to Telegram DCs, NOT through proxy.

  +  Dependencies installed
  +  MTProxy built successfully
  +  Secret generated
  +  Public IP: 1.2.3.4
  +  Service started and enabled on boot
  +  Auto-update configured (daily at 03:00)
  +  UFW: port 443/tcp opened

  +=========================================+
  |        Installation complete!           |
  +=========================================+

  Server:   1.2.3.4
  Port:     443
  Secret:   a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6

  Proxy link -- tap to connect or share:

  https://t.me/proxy?server=1.2.3.4&port=443&secret=a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6

  ------------------------------------------------------
  Max users: ~7639 (connected) | Bottleneck: RAM
  ------------------------------------------------------
  Author: SXCVIO | github.com/sxcvio/Auto-MTProto
  ------------------------------------------------------
```

---

## 🔧 What the script does

| Step | Action |
|------|--------|
| 1️⃣ | Detects OS (Ubuntu / Debian / CentOS / Rocky / AlmaLinux) |
| 2️⃣ | Reads CPU, AES-NI support, RAM, network speed and current load |
| 3️⃣ | Calculates realistic capacity: connected and active user limits |
| 4️⃣ | Clones the maintained MTProxy fork and builds from source |
| 5️⃣ | Downloads Telegram config files and generates a unique secret |
| 6️⃣ | Creates a `systemd` service with autostart and NAT support |
| 7️⃣ | Sets up daily automatic config refresh (cron at 03:00) |
| 8️⃣ | Opens port 443 in UFW / firewalld |
| 9️⃣ | Prints the ready-to-use proxy link |

---

## 📊 How capacity is calculated

MTProxy is extremely lightweight. It only handles the MTProto handshake — after that, all media (photos, videos, files) travels **directly** between the client and Telegram's data centers, bypassing the proxy entirely.

The script finds three bottlenecks and takes the minimum:

```
CPU  →  with AES-NI:    60,000 conn/core  →  12,000 users/core
         without AES-NI: 12,000 conn/core  →   2,400 users/core

RAM  →  40 KB per connection (kernel socket buffers + MTProxy)
         1,746 MB free → 38,195 conn → 7,639 users

Net  →  ~5 KB/s per user (text and notifications only)
         1 Gbit/s → ~21,250 users

Bottleneck → lowest of the three = real limit
```

The output shows **two numbers**:

| Metric | Meaning |
|--------|---------|
| **Connected** | Holding an open TCP session (idle in background) — limited by RAM |
| **Active (~10%)** | Actually sending messages right now — limited by CPU |

**Typical VPS examples (with AES-NI):**

| Config | Connected | Active |
|--------|----------:|-------:|
| 1 core / 512 MB / 100 Mbit | ~640 | ~64 |
| 1 core / 2 GB / 1 Gbit | ~7,600 | ~760 |
| 2 cores / 4 GB / 1 Gbit | ~16,700 | ~1,670 |
| 4 cores / 8 GB / 1 Gbit | ~21,250 | ~2,125 |
| 8 cores / 32 GB / 10 Gbit | ~64,000 | ~6,400 |

> Numbers look large — and that's accurate. A real operator ran a public proxy on a $3.5/mo instance (512 MB / 2 vCPU) for a year with 99.9% CPU idle and a peak of 200 simultaneous clients.

---

## 🖥️ Supported systems

<div align="center">

| OS | Versions | Status |
|----|----------|--------|
| **Ubuntu** | 20.04, 22.04, 24.04 | ✅ Supported |
| **Debian** | 10, 11, 12 | ✅ Supported |
| **CentOS** | 7, 8 Stream | ✅ Supported |
| **Rocky Linux** | 8, 9 | ✅ Supported |
| **AlmaLinux** | 8, 9 | ✅ Supported |

</div>

---

## 📱 How to connect

**Option 1 — One tap (easiest)**

Copy the link from the script output and tap it — Telegram will open and prompt you to connect automatically.

```
https://t.me/proxy?server=YOUR_IP&port=443&secret=YOUR_SECRET
```

**Option 2 — Manual setup**

```
Android:  Settings → Data and Storage → Proxy Settings
iOS:      Settings → Data and Storage → Proxy
Desktop:  Settings → Advanced → Connection Type
```

Type: **MTProto** · Server: `YOUR_IP` · Port: `443` · Secret: `YOUR_SECRET`

---

## 🛠️ Server management

```bash
# Status
systemctl status mtproxy

# Live logs
journalctl -u mtproxy -f

# Restart
systemctl restart mtproxy

# Stop
systemctl stop mtproxy

# Show secret
cat /opt/mtproxy/secret.txt

# Local stats
curl http://127.0.0.1:8888/stats
```

---

## ❓ FAQ

<details>
<summary><b>Why a fork instead of the official repo?</b></summary>

The official `TelegramMessenger/MTProxy` repo is abandoned and hasn't been updated in years. On modern distros with GCC ≥ 10 (Ubuntu 22+, Debian 12+) it fails to compile due to a missing `-fcommon` flag. The script uses `GetPageSpeed/MTProxy` — an actively maintained community fork with this and other fixes applied.

</details>

<details>
<summary><b>What is AES-NI and why does the script check for it?</b></summary>

AES-NI is hardware-accelerated encryption built into the CPU. MTProxy encrypts all traffic using AES-256-CTR. With AES-NI, one core handles up to **60,000 connections** (Telegram's official per-worker cap); without it, roughly 12,000. The script checks `/proc/cpuinfo` and uses the correct limit in its calculation. All modern VPS providers expose AES-NI.

</details>

<details>
<summary><b>Why does the proxy use almost no bandwidth?</b></summary>

MTProxy only participates in the initial MTProto session handshake. After that, media — photos, videos, voice messages, files — goes **directly** between the Telegram client and Telegram's data centers. The proxy never sees it. Only text messages and notifications pass through, roughly 2–5 KB/s per active user. One real operator transferred just ~17 MB total through their proxy over an entire year.

</details>

<details>
<summary><b>What is the difference between Connected and Active?</b></summary>

**Connected** — users with an open TCP session (Telegram running in the background). Each session holds ~40 KB of kernel buffers, so this is limited by available RAM.

**Active (~10%)** — users who are actually sending messages at this moment. In practice, only about 10% of connected users are active at any given time.

</details>

<details>
<summary><b>Can the proxy operator read my messages?</b></summary>

No. All Telegram traffic is end-to-end encrypted using the MTProto protocol. The proxy operator can only see that a connection was made and the client's IP address — never the content of any messages.

</details>

<details>
<summary><b>Why port 443?</b></summary>

Port 443 is the standard HTTPS port. Traffic on it looks like ordinary web browsing to ISPs and DPI systems, making it significantly harder to detect and block compared to a non-standard port.

</details>

<details>
<summary><b>Does the server need to be outside my country?</b></summary>

Not necessarily. A domestic VPS sometimes works better than a foreign one because DPI systems tend to focus on cross-border traffic. A connection from a local IP on port 443 looks like a normal HTTPS request. The only hard requirement is that the server itself can reach Telegram's servers.

</details>

<details>
<summary><b>How do I update the Telegram config manually?</b></summary>

```bash
curl -fsSL https://core.telegram.org/getProxyConfig -o /opt/mtproxy/proxy-multi.conf
systemctl restart mtproxy
```

The script sets up a cron job to do this automatically every night at 03:00, so manual updates are rarely needed.

</details>

<details>
<summary><b>The proxy stopped working — what do I do?</b></summary>

```bash
# Check what's happening
systemctl status mtproxy
journalctl -u mtproxy -n 50

# Try restarting
systemctl restart mtproxy
```

If the logs show a binary error, re-run the installer — it will rebuild MTProxy from source.

</details>

---

## 🤝 Contributing

Found a bug or have an idea?

1. [Fork](https://github.com/sxcvio/Auto-MTProto/fork) the repository
2. Create a branch: `git checkout -b fix/your-description`
3. Commit your change: `git commit -m 'fix: your description'`
4. Open a [Pull Request](https://github.com/sxcvio/Auto-MTProto/pulls)

Or just open an [Issue](https://github.com/sxcvio/Auto-MTProto/issues).

---

<div align="center">

Made with ❤️ by **[SXCVIO](https://github.com/sxcvio)**

*If this project helped you — drop a ⭐ star!*

</div>
