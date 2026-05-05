#!/bin/bash
# =============================================================================
#  MTProxy Installer — Telegram MTProto Proxy
#  https://github.com/sxcvio/Auto-MTProto
#  Autor: SXCVIO
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

INSTALL_DIR="/opt/mtproxy"
PORT=443
SECRET=""
PUBLIC_IP=""
MAX_USERS=0
WORKERS=1
BOTTLENECK="CPU"

# ---- output helpers ---------------------------------------------------------
info()    { echo -e "  ${BLUE}i${NC}  $1"; }
success() { echo -e "  ${GREEN}+${NC}  $1"; }
warn()    { echo -e "  ${YELLOW}!${NC}  $1"; }
error()   { echo -e "  ${RED}x${NC}  $1"; exit 1; }
step()    { echo -e "\n  ${CYAN}${BOLD}>> $1${NC}"; }

# ---- table (ASCII, no Unicode, no ANSI inside printf) -----------------------
# Box width: label 16 + value 26 + 4 spaces = 46 inner chars
# Full line:  "  |" + 46 + "|"  = 51 visible chars, always the same

_TW=46

trow() {
    local lbl="$1" val="$2"
    local vmax=$(( _TW - 18 ))
    (( ${#val} > vmax )) && val="${val:0:$(( vmax - 1 ))}~"
    # All printf here is pure ASCII — no ANSI escapes inside the format string
    local body
    body=$(printf "  %-16s%-28s" "$lbl" "$val")
    echo -e "  ${BOLD}|${NC}${body}  ${BOLD}|${NC}"
}

thead() {
    local txt="$1"
    local inner=$(( _TW ))
    local total_pad=$(( inner - ${#txt} ))
    local lp=$(( total_pad / 2 ))
    local rp=$(( total_pad - lp ))
    local body
    body=$(printf "%${lp}s%s%${rp}s" "" "$txt" "")
    echo -e "  ${BOLD}|${NC}${body}  ${BOLD}|${NC}"
}

_hline() {
    local c="$1" l="$2" r="$3"
    local bar
    bar=$(printf '%0.s-' $(seq 1 $(( _TW + 2 ))))
    echo -e "  ${BOLD}${l}${bar}${r}${NC}"
}

ttop() { _hline - '+' '+'; }
tsep() { _hline - '+' '+'; }
tbot() { _hline - '+' '+'; }

# ---- banner -----------------------------------------------------------------
print_banner() {
    echo ""
    echo -e "${CYAN}${BOLD}"
    echo "  +-+-+-+  +-+-+-+-+-+"
    echo "  |M|T|P|  |P|r|o|x|y|"
    echo "  +-+-+-+  +-+-+-+-+-+"
    echo -e "${NC}"
    echo -e "  ${DIM}Telegram MTProxy -- Automatic Installer${NC}"
    echo -e "  ${DIM}----------------------------------------------${NC}"
    echo -e "  ${DIM}Author: ${NC}${BOLD}SXCVIO${NC}"
    echo ""
}

# ---- root check -------------------------------------------------------------
check_root() {
    [[ $EUID -eq 0 ]] || error "Run as root: sudo bash $0"
}

# ---- OS detection -----------------------------------------------------------
detect_os() {
    [[ -f /etc/os-release ]] || error "Could not detect OS."
    source /etc/os-release
    OS="${ID:-unknown}"
    OS_PRETTY="${PRETTY_NAME:-$OS}"
    case $OS in
        ubuntu|debian)               PKG_MANAGER="apt" ;;
        centos|rhel|rocky|almalinux) PKG_MANAGER="yum" ;;
        *) error "Unsupported OS: $OS" ;;
    esac
    info "System: ${BOLD}${OS_PRETTY}${NC}"
}

# ---- server analysis --------------------------------------------------------
analyze_server() {
    step "Analyzing server hardware"

    local cpu_cores cpu_mhz cpu_model
    local ram_total_gb ram_avail_mb
    local disk_free_gb load_avg
    local net_iface net_speed aes_ni

    cpu_cores=$(nproc)
    cpu_mhz=$(awk '/cpu MHz/{s+=$4;n++} END{if(n)printf "%d",s/n; else print "?"}' /proc/cpuinfo)
    cpu_model=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs | cut -c1-26)

    ram_total_gb=$(awk '/MemTotal/{printf "%.1f",$2/1024/1024}' /proc/meminfo)
    ram_avail_mb=$(awk '/MemAvailable/{printf "%d",$2/1024}' /proc/meminfo)

    disk_free_gb=$(df -BG / | awk 'NR==2{gsub("G","");print $4}')
    load_avg=$(awk '{printf "%.2f",$1}' /proc/loadavg)

    net_iface=$(ip route get 8.8.8.8 2>/dev/null \
        | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1);exit}}')
    net_iface="${net_iface:-eth0}"
    net_speed=1000
    local _spd
    _spd=$(cat /sys/class/net/${net_iface}/speed 2>/dev/null || echo "")
    if [[ -n "$_spd" ]] && (( _spd > 0 && _spd <= 100000 )) 2>/dev/null; then
        net_speed=$_spd
    fi

    if grep -qw "aes" /proc/cpuinfo 2>/dev/null; then
        aes_ni="yes"
    else
        aes_ni="no"
    fi

    # -- capacity calculation -------------------------------------------------
    #
    # Sources:
    #  [1] hub.docker.com/r/telegrammessenger/proxy:
    #      "A worker handles up to 60,000 connections."
    #  [2] seriyps/mtproto_proxy docs:
    #      "Telegram opens 3 to 8 TCP connections per client" -> avg 5
    #      "1Gbps / 4-core / 8GB RAM -> 90k connections"
    #  [3] Real operator data (rameerez, 1 year, 512MB/2vCPU):
    #      "99.9% CPU idle at ~40 active clients, peak 200 clients, no sweat"
    #      "MTProxy only handles auth/setup; media goes direct to Telegram DCs"
    #      "Total traffic in 1 year: ~17 MB" (basically nothing)
    #
    # Key insight: MTProxy is I/O-bound, not CPU-bound.
    # The bottleneck on small servers is almost always RAM (open sockets).
    #
    # Parameters per user:
    #   TCP connections  : 5  (average of 3-8)
    #   RAM per conn     : 40 KB (kernel socket buffers + MTProxy userspace)
    #   Traffic per user : 2 KB/s average (text + notifications only)
    #     -> use 5 KB/s (40 Kbit/s) as conservative budget
    #   OS RAM reserve   : 256 MB
    #
    # CPU limit (official Telegram cap):
    #   with AES-NI  : 60,000 conn/core -> 12,000 users/core
    #   without      : 12,000 conn/core ->  2,400 users/core
    #
    # "Connected users" = holding a session (idle is fine, uses only RAM).
    # "Active users"    = writing right now, ~10% of connected at any moment.

    local conns_per_user=5
    local ram_kb_per_conn=40
    local ram_os_reserve_mb=256
    local net_kbps_per_user=40   # 5 KB/s * 8 bit

    local conns_per_core
    if [[ "$aes_ni" == "yes" ]]; then
        conns_per_core=60000
    else
        conns_per_core=12000
    fi

    local limit_cpu_conns limit_cpu
    limit_cpu_conns=$(( cpu_cores * conns_per_core ))
    limit_cpu=$(( limit_cpu_conns / conns_per_user ))

    local ram_proxy_mb limit_ram_conns limit_ram
    ram_proxy_mb=$(( ram_avail_mb - ram_os_reserve_mb ))
    [[ $ram_proxy_mb -lt 32 ]] && ram_proxy_mb=32
    limit_ram_conns=$(( ram_proxy_mb * 1024 / ram_kb_per_conn ))
    limit_ram=$(( limit_ram_conns / conns_per_user ))

    local net_usable_kbps limit_net
    net_usable_kbps=$(( net_speed * 1000 * 85 / 100 ))
    limit_net=$(( net_usable_kbps / net_kbps_per_user ))

    MAX_USERS=$limit_cpu
    BOTTLENECK="CPU"
    if (( limit_ram < MAX_USERS )); then MAX_USERS=$limit_ram; BOTTLENECK="RAM"; fi
    if (( limit_net < MAX_USERS )); then MAX_USERS=$limit_net; BOTTLENECK="Net"; fi

    local active_users=$(( MAX_USERS / 10 ))
    [[ $active_users -lt 1 ]] && active_users=1

    WORKERS=$cpu_cores
    (( WORKERS > 16 )) && WORKERS=16

    local tier
    if   (( MAX_USERS >= 10000 )); then tier="**** Powerful server"
    elif (( MAX_USERS >= 3000  )); then tier="***- High load"
    elif (( MAX_USERS >= 500   )); then tier="**-- Medium load"
    elif (( MAX_USERS >= 100   )); then tier="*--- Light load"
    else                                tier="---- Minimal"
    fi

    local aes_label
    [[ "$aes_ni" == "yes" ]] && aes_label="yes (hardware AES)" || aes_label="no (software AES)"

    echo ""
    ttop
    thead "     Server characteristics"
    tsep
    trow "CPU:" "${cpu_cores} cores @ ${cpu_mhz} MHz"
    trow "Model:" "${cpu_model}"
    trow "AES-NI:" "${aes_label}"
    trow "RAM total:" "${ram_total_gb} GB"
    trow "RAM free:" "${ram_avail_mb} MB available"
    trow "Disk free:" "${disk_free_gb} GB"
    trow "Network:" "${net_speed} Mbit/s (${net_iface})"
    trow "Load avg:" "${load_avg}"
    tsep
    thead "  Capacity limits (conn -> users)"
    tsep
    trow "CPU:" "$(printf '%d conn -> ~%d users' $limit_cpu_conns $limit_cpu)"
    trow "RAM:" "$(printf '%d conn -> ~%d users' $limit_ram_conns $limit_ram)"
    trow "Network:" "$(printf '~%d Kbps -> ~%d users' $net_usable_kbps $limit_net)"
    tsep
    trow "Connected:" "~${MAX_USERS} (hold session)"
    trow "Active:" "~${active_users} (active ~10%)"
    trow "Workers:" "${WORKERS}"
    trow "Bottleneck:" "${BOTTLENECK}"
    trow "Tier:" "${tier}"
    tbot
    echo ""
    info "Connected = idle sessions; Active = actually writing right now."
    info "Media (photos/video) goes direct to Telegram DCs, NOT through proxy."
}

# ---- install deps -----------------------------------------------------------
install_deps() {
    step "Installing dependencies"
    if [[ $PKG_MANAGER == "apt" ]]; then
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
            git curl build-essential libssl-dev zlib1g-dev xxd 2>/dev/null
    else
        yum install -y -q git curl openssl-devel zlib-devel xxd
        yum groupinstall -y -q "Development Tools"
    fi
    success "Dependencies installed"
}

# ---- build MTProxy ----------------------------------------------------------
build_mtproxy() {
    step "Building MTProxy from source"

    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"

    # NOTE: We clone GetPageSpeed/MTProxy (community-maintained fork), NOT the
    # official TelegramMessenger/MTProxy which is abandoned and breaks on
    # modern GCC (>= 10) due to missing -fcommon flag.
    info "Cloning MTProxy fork (GetPageSpeed)..."
    git clone -q --depth 1 \
        https://github.com/GetPageSpeed/MTProxy \
        "$INSTALL_DIR/src" \
        || error "Clone failed. Check your internet connection."

    cd "$INSTALL_DIR/src"

    # Patch Makefile: add -fcommon to fix multiple-definition linker errors on GCC >= 10
    if grep -q "COMMON_CFLAGS" Makefile 2>/dev/null; then
        sed -i '/COMMON_CFLAGS/s/$/ -fcommon/' Makefile
        sed -i '/COMMON_LDFLAGS/s/$/ -fcommon/' Makefile
        info "Makefile patched: -fcommon added for GCC >= 10 compatibility"
    fi

    local ncpu
    ncpu=$(nproc)
    info "Compiling with ${ncpu} cores (1-3 min)..."
    make -j"$ncpu" 2>/dev/null \
        || make 2>/dev/null \
        || error "Compilation failed. Check dependencies."

    [[ -f objs/bin/mtproto-proxy ]] || error "Binary not found after build."
    cp objs/bin/mtproto-proxy "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/mtproto-proxy"
    cd "$INSTALL_DIR"
    success "MTProxy built successfully"
}

# ---- config -----------------------------------------------------------------
setup_config() {
    step "Generating secret and downloading config"

    cd "$INSTALL_DIR"

    info "Downloading Telegram configuration..."
    curl -fsSL --max-time 15 https://core.telegram.org/getProxySecret \
        -o proxy-secret   || error "Failed to download proxy-secret."
    curl -fsSL --max-time 15 https://core.telegram.org/getProxyConfig \
        -o proxy-multi.conf || error "Failed to download proxy-multi.conf."

    SECRET=$(head -c 16 /dev/urandom | xxd -ps)
    echo "$SECRET" > "$INSTALL_DIR/secret.txt"
    chmod 600 "$INSTALL_DIR/secret.txt"
    success "Secret generated"

    info "Detecting public IP..."
    PUBLIC_IP=""
    for svc in \
        "https://api.ipify.org" \
        "https://ifconfig.me/ip" \
        "https://icanhazip.com" \
        "https://checkip.amazonaws.com"
    do
        PUBLIC_IP=$(curl -fsSL --max-time 5 "$svc" 2>/dev/null | tr -d '[:space:]')
        [[ -n "$PUBLIC_IP" ]] && break
    done
    [[ -z "$PUBLIC_IP" ]] && PUBLIC_IP="YOUR_SERVER_IP"
    success "Public IP: ${BOLD}${PUBLIC_IP}${NC}"
}

# ---- systemd service --------------------------------------------------------
create_service() {
    step "Creating systemd service"

    local local_ip nat_line=""
    local_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "")
    if [[ -n "$local_ip" && "$local_ip" != "$PUBLIC_IP" ]]; then
        nat_line="    --nat-info ${local_ip}:${PUBLIC_IP} \\"$'\n'
    fi

    cat > /etc/systemd/system/mtproxy.service << EOF
[Unit]
Description=Telegram MTProxy Server
Documentation=https://github.com/sxcvio/Auto-MTProto
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/mtproto-proxy \
    -u nobody \
    -p 8888 \
    -H ${PORT} \
    -S ${SECRET} \
${nat_line}    --aes-pwd ${INSTALL_DIR}/proxy-secret ${INSTALL_DIR}/proxy-multi.conf \
    -M ${WORKERS}
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/security/limits.d/99-mtproxy.conf << 'LIMITS'
* soft nofile 1048576
* hard nofile 1048576
LIMITS

    if ! grep -q "fs.file-max" /etc/sysctl.conf 2>/dev/null; then
        echo "fs.file-max = 1048576" >> /etc/sysctl.conf
    fi
    sysctl -p -q 2>/dev/null || true

    systemctl daemon-reload
    systemctl enable mtproxy -q 2>/dev/null || true
    systemctl start mtproxy

    sleep 3

    if systemctl is-active --quiet mtproxy; then
        success "Service started and enabled on boot"
    else
        warn "Service failed to start. Last log lines:"
        echo ""
        journalctl -u mtproxy -n 20 --no-pager 2>/dev/null || true
        echo ""
        warn "Diagnostic commands:"
        warn "  systemctl status mtproxy"
        warn "  journalctl -u mtproxy -f"
    fi
}

# ---- cron -------------------------------------------------------------------
setup_cron() {
    step "Setting up automatic config update"

    cat > /etc/cron.d/mtproxy-update << CRONEOF
# MTProxy: update Telegram config daily at 03:00
0 3 * * * root curl -fsSL --max-time 30 https://core.telegram.org/getProxyConfig -o ${INSTALL_DIR}/proxy-multi.conf && systemctl restart mtproxy
CRONEOF

    chmod 644 /etc/cron.d/mtproxy-update
    success "Auto-update configured (daily at 03:00)"
}

# ---- firewall ---------------------------------------------------------------
setup_firewall() {
    step "Configuring firewall"

    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "active"; then
        ufw allow ${PORT}/tcp comment "MTProxy" -q 2>/dev/null \
            && success "UFW: port ${PORT}/tcp opened" \
            || warn "UFW: failed to open port -- run manually: ufw allow ${PORT}/tcp"
    elif command -v firewall-cmd &>/dev/null && firewall-cmd --state &>/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=${PORT}/tcp -q 2>/dev/null \
            && firewall-cmd --reload -q \
            && success "firewalld: port ${PORT}/tcp opened" \
            || warn "firewalld: failed to open port"
    else
        info "No firewall detected. For iptables:"
        info "  iptables -A INPUT -p tcp --dport ${PORT} -j ACCEPT"
    fi
}

# ---- result -----------------------------------------------------------------
print_result() {
    local proxy_link="https://t.me/proxy?server=${PUBLIC_IP}&port=${PORT}&secret=${SECRET}"

    echo ""
    echo -e "${GREEN}${BOLD}"
    echo "  +=========================================+"
    echo "  |   OK  Installation complete!    |"
    echo "  +=========================================+"
    echo -e "${NC}"

    echo -e "  ${BOLD}Connection details:${NC}"
    echo ""
    echo -e "  ${DIM}Server:${NC}   ${BOLD}${PUBLIC_IP}${NC}"
    echo -e "  ${DIM}Port:${NC}     ${BOLD}${PORT}${NC}"
    echo -e "  ${DIM}Secret:${NC}   ${BOLD}${SECRET}${NC}"
    echo ""
    echo -e "  ${CYAN}${BOLD}Proxy link -- tap to connect or share:${NC}"
    echo ""
    echo -e "  ${GREEN}${BOLD}${proxy_link}${NC}"
    echo ""
    echo -e "  ${DIM}------------------------------------------------------${NC}"
    echo -e "  Max users: ~${MAX_USERS} (connected) | Bottleneck: ${BOTTLENECK}"
    echo -e "  ${DIM}------------------------------------------------------${NC}"
    echo ""
    echo -e "  ${BOLD}Useful commands:${NC}"
    echo -e "  ${CYAN}systemctl status mtproxy${NC}          -- status"
    echo -e "  ${CYAN}journalctl -u mtproxy -f${NC}           -- logs"
    echo -e "  ${CYAN}systemctl restart mtproxy${NC}         -- restart"
    echo -e "  ${CYAN}curl http://127.0.0.1:8888/stats${NC}  -- stats"
    echo -e "  ${CYAN}cat ${INSTALL_DIR}/secret.txt${NC}     -- show secret"
    echo ""
    echo ""
    echo -e "  ${DIM}------------------------------------------------------${NC}"
    echo -e "  ${DIM}Author: ${NC}${BOLD}SXCVIO${NC}${DIM} | github.com/sxcvio/Auto-MTProto${NC}"
    echo -e "  ${DIM}------------------------------------------------------${NC}"
    echo ""
}

# ---- main -------------------------------------------------------------------
main() {
    print_banner
    check_root
    detect_os
    analyze_server
    install_deps
    build_mtproxy
    setup_config
    create_service
    setup_cron
    setup_firewall
    print_result
}

main
