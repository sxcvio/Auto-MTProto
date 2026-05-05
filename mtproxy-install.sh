#!/bin/bash
# =============================================================================
#  MTProxy Installer — Telegram MTProto Proxy
#  Автоматическая установка и настройка прокси-сервера для Telegram
#  https://github.com/TelegramMessenger/MTProxy
#
#  Автор: SXCVIO
# =============================================================================

set -e

# ─── Цвета ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# ─── Баннер ──────────────────────────────────────────────────────────────────
print_banner() {
    echo ""
    echo -e "${CYAN}${BOLD}"
    echo "  ╔╦╗╔╦╗╔═╗  ╔═╗┬─┐┌─┐─┐ ┬┬ ┬"
    echo "  ║║║ ║ ╠═╝  ╠═╝├┬┘│ │┌┴┬┘└┬┘"
    echo "  ╩ ╩ ╩ ╩    ╩  ┴└─└─┘┴ └─ ┴ "
    echo -e "${NC}"
    echo -e "${DIM}  Telegram MTProxy — Автоматическая установка${NC}"
    echo -e "${DIM}  ──────────────────────────────────────────${NC}"
    echo -e "${DIM}  Автор: ${NC}${BOLD}SXCVIO${NC}"
    echo ""
}

# ─── Утилиты вывода ──────────────────────────────────────────────────────────
info()    { echo -e "  ${BLUE}ℹ${NC}  $1"; }
success() { echo -e "  ${GREEN}✔${NC}  $1"; }
warn()    { echo -e "  ${YELLOW}⚠${NC}  $1"; }
error()   { echo -e "  ${RED}✖${NC}  $1"; exit 1; }
step()    { echo -e "\n  ${CYAN}${BOLD}▶ $1${NC}"; }

# ─── Проверка root ───────────────────────────────────────────────────────────
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Скрипт нужно запускать от root: sudo bash $0"
    fi
}

# ─── Определение ОС ──────────────────────────────────────────────────────────
detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        error "Не удалось определить ОС. Поддерживаются: Ubuntu, Debian, CentOS, Rocky, Alma."
    fi

    case $OS in
        ubuntu|debian)  PKG_MANAGER="apt" ;;
        centos|rhel|rocky|almalinux) PKG_MANAGER="yum" ;;
        *) error "Неподдерживаемая ОС: $OS" ;;
    esac

    info "Система: ${BOLD}${PRETTY_NAME}${NC}"
}

# ─── Анализ характеристик сервера ────────────────────────────────────────────
analyze_server() {
    step "Анализ характеристик сервера"

    # ── Сбор данных о железе ───────────────────────────────────────────────

    # CPU
    CPU_CORES=$(nproc)
    CPU_MHZ=$(awk '/cpu MHz/ {sum+=$4; n++} END {if(n>0) printf "%d", sum/n; else print "?"}' /proc/cpuinfo)
    CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs)

    # RAM
    RAM_TOTAL_MB=$(awk '/MemTotal/  {printf "%d", $2/1024}' /proc/meminfo)
    RAM_AVAIL_MB=$(awk '/MemAvailable/ {printf "%d", $2/1024}' /proc/meminfo)
    RAM_TOTAL_GB=$(awk '/MemTotal/  {printf "%.1f", $2/1024/1024}' /proc/meminfo)

    # Диск
    DISK_FREE_GB=$(df -BG / | awk 'NR==2 {gsub("G",""); print $4}')

    # Текущая нагрузка (load average за 1 мин)
    LOAD_AVG=$(awk '{printf "%.2f", $1}' /proc/loadavg)

    # Сеть: пытаемся определить реальную скорость интерфейса
    NET_IFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1)
    NET_SPEED=1000  # дефолт: 1 Гбит/с (типично для VPS)
    if [[ -n "$NET_IFACE" ]]; then
        # /sys/class/net быстрее и надёжнее ethtool на VPS
        SYS_SPEED=$(cat /sys/class/net/${NET_IFACE}/speed 2>/dev/null || echo "")
        if [[ -n "$SYS_SPEED" && "$SYS_SPEED" -gt 0 ]] 2>/dev/null; then
            NET_SPEED=$SYS_SPEED
        fi
    fi
    # Защита от безумных значений (некоторые VPS возвращают 65535 или -1)
    [[ $NET_SPEED -gt 100000 || $NET_SPEED -le 0 ]] 2>/dev/null && NET_SPEED=1000

    # ── Реалистичный расчёт (на основе реальных замеров) ──────────────────
    #
    # Как работает MTProxy на самом деле:
    #   — Прокси работает ТОЛЬКО на этапе установки сессии MTProto.
    #     После хендшейка медиа (фото, видео, файлы) идут напрямую
    #     между клиентом и DC Telegram, минуя прокси.
    #   — Через прокси проходят: служебные сообщения, текст, уведомления.
    #     Это очень легкий трафик (~1–5 КБ/с на активного юзера в чате,
    #     ~0 КБ/с на idle-пользователя).
    #   — Telegram открывает 3–8 TCP-соединений на одного пользователя.
    #     Берём среднее: 5 соединений/юзер.
    #   — RAM на соединение: ~20–40 КБ (буферы ядра + userspace MTProxy).
    #     Реальный замер: 4 ядра / 8 ГБ RAM держат 90k соединений = 18k юзеров.
    #   — CPU: шифрование AES-256-CTR — ~15k соединений на ядро (без AES-NI),
    #     с AES-NI (все современные VPS) до 50k+ соединений на ядро.
    #
    # Источники: seriyps/mtproto_proxy (90k conn / 4 ядра / 8 ГБ),
    #            реальные наблюдения операторов прокси.

    CONNS_PER_USER=5          # TCP-соединений на одного пользователя
    RAM_KB_PER_CONN=35        # КБ RAM на соединение (буферы)
    RAM_OS_RESERVE_MB=256     # резерв для ОС и системных процессов

    # Определяем наличие AES-NI (аппаратное ускорение шифрования)
    if grep -qw "aes" /proc/cpuinfo 2>/dev/null; then
        AES_NI="да"
        CONNS_PER_CORE=40000  # с AES-NI: ~40k соединений на ядро
    else
        AES_NI="нет"
        CONNS_PER_CORE=12000  # без AES-NI: ~12k соединений на ядро
    fi

    # Лимит по CPU (соединения → пользователи)
    LIMIT_CPU_CONNS=$(( CPU_CORES * CONNS_PER_CORE ))
    LIMIT_CPU=$(( LIMIT_CPU_CONNS / CONNS_PER_USER ))

    # Лимит по RAM
    # Доступная RAM минус резерв ОС → делим на (КБ/соединение × 1024) → в пользователей
    RAM_FOR_PROXY_MB=$(( RAM_AVAIL_MB - RAM_OS_RESERVE_MB ))
    [[ $RAM_FOR_PROXY_MB -lt 64 ]] && RAM_FOR_PROXY_MB=64
    RAM_FOR_PROXY_KB=$(( RAM_FOR_PROXY_MB * 1024 ))
    LIMIT_RAM_CONNS=$(( RAM_FOR_PROXY_KB / RAM_KB_PER_CONN ))
    LIMIT_RAM=$(( LIMIT_RAM_CONNS / CONNS_PER_USER ))

    # Лимит по сети
    # Служебный трафик через прокси: ~3 КБ/с на активного юзера в среднем.
    # Пиковый (все пишут одновременно): ~15 КБ/с.
    # Считаем по среднему с запасом: 5 КБ/с = 40 Кбит/с на пользователя.
    # При этом используем 85% пропускной способности (запас на ACK-пакеты и overhead).
    NET_USABLE_KBPS=$(( NET_SPEED * 1000 * 85 / 100 ))  # Мбит → Кбит, 85%
    TRAFFIC_PER_USER_KBPS=40
    LIMIT_NET=$(( NET_USABLE_KBPS / TRAFFIC_PER_USER_KBPS ))

    # Лимит по открытым файловым дескрипторам (каждое соединение = 1 fd)
    # Системный лимит по умолчанию 65535 fd, мы его поднимем в сервисе до 1M
    # но на старых ядрах может быть жёстче. Считаем по 1M / 5 = 200k юзеров —
    # это никогда не будет узким местом на реальных серверах.
    LIMIT_FD=200000

    # Итоговый минимум — реальный bottleneck
    MAX_USERS=$LIMIT_CPU
    [[ $LIMIT_RAM -lt $MAX_USERS ]]  && MAX_USERS=$LIMIT_RAM
    [[ $LIMIT_NET -lt $MAX_USERS ]]  && MAX_USERS=$LIMIT_NET
    [[ $LIMIT_FD  -lt $MAX_USERS ]]  && MAX_USERS=$LIMIT_FD

    # Определяем узкое место (что первым ограничит рост)
    BOTTLENECK="CPU"
    MIN_VAL=$LIMIT_CPU
    [[ $LIMIT_RAM -lt $MIN_VAL ]] && { MIN_VAL=$LIMIT_RAM; BOTTLENECK="RAM"; }
    [[ $LIMIT_NET -lt $MIN_VAL ]] && { MIN_VAL=$LIMIT_NET; BOTTLENECK="Сеть"; }

    # Количество воркеров = кол-во ядер (не больше 16 — ограничение MTProxy)
    WORKERS=$CPU_CORES
    [[ $WORKERS -gt 16 ]] && WORKERS=16

    # ── Оценка класса сервера ───────────────────────────────────────────────
    if   [[ $MAX_USERS -ge 10000 ]]; then TIER="${GREEN}${BOLD}★★★★ Мощный сервер${NC}"
    elif [[ $MAX_USERS -ge 3000  ]]; then TIER="${GREEN}★★★☆ Высокая нагрузка${NC}"
    elif [[ $MAX_USERS -ge 500   ]]; then TIER="${CYAN}★★☆☆ Средняя нагрузка${NC}"
    elif [[ $MAX_USERS -ge 100   ]]; then TIER="${YELLOW}★☆☆☆ Лёгкая нагрузка${NC}"
    else                                   TIER="${RED}☆☆☆☆ Минимальная${NC}"
    fi

    echo ""
    echo -e "  ${BOLD}┌──────────────────────────────────────────────┐${NC}"
    echo -e "  ${BOLD}│          Характеристики сервера              │${NC}"
    echo -e "  ${BOLD}├──────────────────────────────────────────────┤${NC}"
    printf  "  ${BOLD}│${NC}  %-13s %-30s ${BOLD}│${NC}\n" "CPU:"      "${CPU_CORES} ядер @ ${CPU_MHZ} МГц"
    printf  "  ${BOLD}│${NC}  %-13s %-30s ${BOLD}│${NC}\n" "Модель:"   "${CPU_MODEL:0:30}"
    printf  "  ${BOLD}│${NC}  %-13s %-30s ${BOLD}│${NC}\n" "AES-NI:"   "${AES_NI} (аппарат. шифрование)"
    printf  "  ${BOLD}│${NC}  %-13s %-30s ${BOLD}│${NC}\n" "RAM всего:"    "${RAM_TOTAL_GB} ГБ"
    printf  "  ${BOLD}│${NC}  %-13s %-30s ${BOLD}│${NC}\n" "RAM свободно:" "${RAM_AVAIL_MB} МБ доступно"
    printf  "  ${BOLD}│${NC}  %-13s %-30s ${BOLD}│${NC}\n" "Диск:"     "Свободно ${DISK_FREE_GB} ГБ"
    printf  "  ${BOLD}│${NC}  %-13s %-30s ${BOLD}│${NC}\n" "Сеть:"     "${NET_SPEED} Мбит/с (${NET_IFACE:-eth0})"
    printf  "  ${BOLD}│${NC}  %-13s %-30s ${BOLD}│${NC}\n" "Load avg:" "${LOAD_AVG} (сейчас)"
    echo -e "  ${BOLD}├──────────────────────────────────────────────┤${NC}"
    echo -e "  ${BOLD}│${NC}  ${DIM}Лимиты (соединений → уникальных польз.)${NC}    ${BOLD}│${NC}"
    printf  "  ${BOLD}│${NC}  %-13s %-30s ${BOLD}│${NC}\n" "CPU:"      "~${LIMIT_CPU_CONNS} conn → ~${LIMIT_CPU} польз."
    printf  "  ${BOLD}│${NC}  %-13s %-30s ${BOLD}│${NC}\n" "RAM:"      "~${LIMIT_RAM_CONNS} conn → ~${LIMIT_RAM} польз."
    printf  "  ${BOLD}│${NC}  %-13s %-30s ${BOLD}│${NC}\n" "Сеть:"     "~${NET_USABLE_KBPS} Кбит/с → ~${LIMIT_NET} польз."
    echo -e "  ${BOLD}├──────────────────────────────────────────────┤${NC}"
    printf  "  ${BOLD}│${NC}  ${GREEN}${BOLD}%-13s${NC} ${BOLD}%-30s${NC} ${BOLD}│${NC}\n" "Макс. польз.:" "≈ ${MAX_USERS} одновременно"
    printf  "  ${BOLD}│${NC}  %-13s %-30s ${BOLD}│${NC}\n" "Воркеры:"  "${WORKERS} (по числу ядер)"
    printf  "  ${BOLD}│${NC}  %-13s %-30s ${BOLD}│${NC}\n" "Узкое место:" "${BOTTLENECK}"
    printf  "  ${BOLD}│${NC}  %-13s " "Класс:"; echo -e "${TIER}               ${BOLD}│${NC}"
    echo -e "  ${BOLD}└──────────────────────────────────────────────┘${NC}"
    echo ""

    info "Расчёт учитывает: 5 TCP-соединений/юзер, ${RAM_KB_PER_CONN} КБ RAM/соединение,"
    info "трафик ~5 КБ/с/юзер (только служебные данные, медиа идёт напрямую к DC)."
}

# ─── Установка зависимостей ───────────────────────────────────────────────────
install_deps() {
    step "Установка зависимостей"

    if [[ $PKG_MANAGER == "apt" ]]; then
        apt-get update -qq
        apt-get install -y -qq \
            git curl build-essential libssl-dev zlib1g-dev xxd net-tools 2>/dev/null \
            || apt-get install -y git curl build-essential libssl-dev zlib1g-dev xxd net-tools
    else
        yum install -y -q git curl openssl-devel zlib-devel xxd net-tools
        yum groupinstall -y "Development Tools" -q
    fi

    success "Зависимости установлены"
}

# ─── Сборка MTProxy ───────────────────────────────────────────────────────────
build_mtproxy() {
    step "Сборка MTProxy из исходников"

    INSTALL_DIR="/opt/mtproxy"
    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"

    # Клонируем репозиторий
    info "Клонирование репозитория..."
    git clone -q https://github.com/TelegramMessenger/MTProxy "$INSTALL_DIR/src" \
        || error "Не удалось клонировать репозиторий. Проверьте интернет-соединение."

    cd "$INSTALL_DIR/src"

    info "Компиляция (это займёт ~1–2 минуты)..."
    make -j"$CPU_CORES" 2>/dev/null || make 2>/dev/null \
        || error "Ошибка компиляции. Возможно, не хватает зависимостей."

    cp objs/bin/mtproto-proxy "$INSTALL_DIR/"
    cd "$INSTALL_DIR"

    success "MTProxy собран успешно"
}

# ─── Генерация секрета и загрузка конфигов ───────────────────────────────────
setup_config() {
    step "Генерация секрета и загрузка конфигурации"

    INSTALL_DIR="/opt/mtproxy"
    cd "$INSTALL_DIR"

    # Скачиваем секреты и конфиг Telegram
    info "Загрузка конфигурации от Telegram..."
    curl -s https://core.telegram.org/getProxySecret -o proxy-secret \
        || error "Не удалось загрузить proxy-secret. Проверьте интернет."
    curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf \
        || error "Не удалось загрузить proxy-multi.conf. Проверьте интернет."

    # Генерируем секрет пользователя
    # dd+xxd: переносимее чем openssl rand на старых системах
    SECRET=$(head -c 16 /dev/urandom | xxd -ps)
    success "Секрет сгенерирован"

    # Сохраняем в файл чтобы не потерять
    echo "$SECRET" > "$INSTALL_DIR/secret.txt"
    chmod 600 "$INSTALL_DIR/secret.txt"

    # Определяем внешний IP
    info "Определение внешнего IP..."
    PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org \
             || curl -s --max-time 5 https://ifconfig.me \
             || curl -s --max-time 5 https://icanhazip.com \
             || echo "YOUR_SERVER_IP")

    success "IP сервера: ${BOLD}${PUBLIC_IP}${NC}"
}

# ─── Создание systemd сервиса ─────────────────────────────────────────────────
create_service() {
    step "Создание systemd сервиса"

    INSTALL_DIR="/opt/mtproxy"
    PORT=443

    cat > /etc/systemd/system/mtproxy.service << EOF
[Unit]
Description=Telegram MTProxy Server
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=nobody
WorkingDirectory=${INSTALL_DIR}
ExecStartPre=/bin/bash -c 'curl -s https://core.telegram.org/getProxyConfig -o ${INSTALL_DIR}/proxy-multi.conf'
ExecStart=${INSTALL_DIR}/mtproto-proxy \\
    -u nobody \\
    -p 8888 \\
    -H ${PORT} \\
    -S ${SECRET} \\
    --aes-pwd ${INSTALL_DIR}/proxy-secret ${INSTALL_DIR}/proxy-multi.conf \\
    -M ${WORKERS}
Restart=always
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    # Настройка лимита файлов для большого числа соединений
    cat > /etc/security/limits.d/mtproxy.conf << EOF
nobody soft nofile 1048576
nobody hard nofile 1048576
EOF

    # Поднимаем системный лимит fs.file-max если нужно
    CURRENT_FILEMAX=$(sysctl -n fs.file-max 2>/dev/null || echo 0)
    if [[ $CURRENT_FILEMAX -lt 1048576 ]]; then
        echo "fs.file-max = 1048576" >> /etc/sysctl.conf
        sysctl -p -q 2>/dev/null || true
    fi

    systemctl daemon-reload
    systemctl enable mtproxy -q
    systemctl start mtproxy

    sleep 2

    if systemctl is-active --quiet mtproxy; then
        success "Сервис запущен и добавлен в автозагрузку"
    else
        warn "Сервис не запустился. Проверьте логи: journalctl -u mtproxy -n 30"
    fi
}

# ─── Настройка автообновления конфига ────────────────────────────────────────
setup_cron() {
    step "Настройка автообновления конфигурации"

    INSTALL_DIR="/opt/mtproxy"

    # Ежедневное обновление конфига Telegram и перезапуск
    cat > /etc/cron.d/mtproxy-update << EOF
# Обновление конфигурации MTProxy каждый день в 03:00
0 3 * * * root curl -s https://core.telegram.org/getProxyConfig -o ${INSTALL_DIR}/proxy-multi.conf && systemctl restart mtproxy
EOF

    success "Автообновление настроено (ежедневно в 03:00)"
}

# ─── Открытие порта в firewall ────────────────────────────────────────────────
setup_firewall() {
    step "Настройка файрвола"

    if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
        ufw allow 443/tcp -q 2>/dev/null && success "UFW: порт 443 открыт" || warn "UFW: не удалось открыть порт"
    elif command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port=443/tcp -q 2>/dev/null \
        && firewall-cmd --reload -q \
        && success "firewalld: порт 443 открыт" || warn "firewalld: не удалось открыть порт"
    else
        info "UFW/firewalld не обнаружены. Если используете iptables — откройте порт 443 вручную."
    fi
}

# ─── Итоговый вывод ───────────────────────────────────────────────────────────
print_result() {
    PORT=443

    # Ссылка для подключения (формат официальный)
    PROXY_LINK="https://t.me/proxy?server=${PUBLIC_IP}&port=${PORT}&secret=${SECRET}"

    echo ""
    echo -e "${GREEN}${BOLD}"
    echo "  ╔═══════════════════════════════════════════╗"
    echo "  ║      ✅  Установка завершена успешно!      ║"
    echo "  ╚═══════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  ${BOLD}Данные для подключения:${NC}"
    echo ""
    echo -e "  ${DIM}Сервер:${NC}  ${BOLD}${PUBLIC_IP}${NC}"
    echo -e "  ${DIM}Порт:${NC}    ${BOLD}${PORT}${NC}"
    echo -e "  ${DIM}Секрет:${NC}  ${BOLD}${SECRET}${NC}"
    echo ""
    echo -e "  ${BOLD}${CYAN}Ссылка для подключения (отправьте друзьям):${NC}"
    echo ""
    echo -e "  ${GREEN}${BOLD}${PROXY_LINK}${NC}"
    echo ""
    echo -e "  ${DIM}────────────────────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}Возможности сервера:${NC} ~${MAX_USERS} одновременных пользователей"
    echo -e "  ${DIM}────────────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "  ${BOLD}Как подключиться в Telegram:${NC}"
    echo -e "  ${DIM}1. Нажмите на ссылку выше — Telegram откроется автоматически${NC}"
    echo -e "  ${DIM}2. Или вручную: Настройки → Данные и память → Прокси${NC}"
    echo -e "  ${DIM}   Тип: MTProto, Сервер: ${PUBLIC_IP}, Порт: ${PORT}, Секрет: ${SECRET}${NC}"
    echo ""
    echo -e "  ${BOLD}Полезные команды:${NC}"
    echo -e "  ${DIM}Статус:     ${CYAN}systemctl status mtproxy${NC}"
    echo -e "  ${DIM}Логи:       ${CYAN}journalctl -u mtproxy -f${NC}"
    echo -e "  ${DIM}Перезапуск: ${CYAN}systemctl restart mtproxy${NC}"
    echo -e "  ${DIM}Секрет:     ${CYAN}cat /opt/mtproxy/secret.txt${NC}"
    echo ""
    echo -e "  ${YELLOW}💡 Хотите монетизировать прокси? Напишите @MTProxyBot в Telegram${NC}"
    echo "     команду /newproxy и получите TAG для продвижения своего канала."
    echo ""
    echo -e "  ${DIM}────────────────────────────────────────────────────────${NC}"
    echo -e "  ${DIM}  Скрипт создан автором ${NC}${BOLD}SXCVIO${NC}"
    echo -e "  ${DIM}────────────────────────────────────────────────────────${NC}"
    echo ""
}

# ─── MAIN ─────────────────────────────────────────────────────────────────────
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
