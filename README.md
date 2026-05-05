<div align="center">

<img src="https://img.shields.io/badge/Telegram-MTProxy-2CA5E0?style=for-the-badge&logo=telegram&logoColor=white"/>

```
  +-+-+-+  +-+-+-+-+-+
  |M|T|P|  |P|r|o|x|y|
  +-+-+-+  +-+-+-+-+-+
```

**Автоматическая установка MTProxy сервера для Telegram**  
*Один скрипт — и ваш прокси готов к работе*

---

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Stars](https://img.shields.io/github/stars/sxcvio/Auto-MTProto?style=flat-square&color=yellow)](https://github.com/sxcvio/Auto-MTProto/stargazers)
[![Issues](https://img.shields.io/github/issues/sxcvio/Auto-MTProto?style=flat-square&color=red)](https://github.com/sxcvio/Auto-MTProto/issues)
[![OS](https://img.shields.io/badge/OS-Ubuntu%20%7C%20Debian%20%7C%20CentOS-orange?style=flat-square&logo=linux&logoColor=white)](#)
[![Author](https://img.shields.io/badge/Author-SXCVIO-9b59b6?style=flat-square)](https://github.com/sxcvio)

</div>

---

## ⚡ Быстрый старт

Скопируйте и вставьте одну команду на сервер:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/sxcvio/Auto-MTProto/main/mtproxy-install.sh)
```

> [!IMPORTANT]
> Требуются права **root**. Если вы обычный пользователь — добавьте `sudo` перед командой.

---

## 🎬 Как это выглядит

```
  +-+-+-+  +-+-+-+-+-+
  |M|T|P|  |P|r|o|x|y|
  +-+-+-+  +-+-+-+-+-+

  Telegram MTProxy -- Avtomaticheskaya ustanovka
  ----------------------------------------------
  Avtor: SXCVIO

  i  Sistema: Ubuntu 24.04 LTS

  >> Analiz kharakteristik servera

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

  +  Zavisimosti ustanovleny
  +  MTProxy sobran uspeshno
  +  Sekret sgenerirovan
  +  Vneshniy IP: 1.2.3.4
  +  Servis zapushchen i dobavlen v avtozagruzku
  +  Avtoobnovlenie nastroeno (ezhednevno v 03:00)
  +  UFW: port 443/tcp otkryt

  +=========================================+
  |   OK  Ustanovka zavershena uspeshno!    |
  +=========================================+

  Server:   1.2.3.4
  Port:     443
  Secret:   a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6

  Ssylka -- nazhmite ili otpravte druziyam:

  https://t.me/proxy?server=1.2.3.4&port=443&secret=a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6

  ------------------------------------------------------
  Max users: ~7639 (connected) | Bottleneck: RAM
  ------------------------------------------------------

  ------------------------------------------------------
  Avtor: SXCVIO | github.com/sxcvio/Auto-MTProto
  ------------------------------------------------------
```

---

## 🔧 Что делает скрипт

| Шаг | Действие |
|-----|----------|
| 1️⃣ | Определяет ОС (Ubuntu / Debian / CentOS / Rocky / Alma) |
| 2️⃣ | Анализирует CPU, AES-NI, RAM, сеть и текущую нагрузку |
| 3️⃣ | Считает реальную ёмкость: подключённых и активных пользователей |
| 4️⃣ | Клонирует поддерживаемый форк MTProxy и собирает из исходников |
| 5️⃣ | Скачивает конфиги Telegram и генерирует уникальный секрет |
| 6️⃣ | Создаёт `systemd`-сервис с автозапуском и NAT-поддержкой |
| 7️⃣ | Настраивает ежедневное обновление конфига Telegram (03:00) |
| 8️⃣ | Открывает порт 443 в UFW / firewalld |
| 9️⃣ | Выводит готовую ссылку для подключения |

---

## 📊 Как считается ёмкость сервера

MTProxy — очень лёгкий прокси. Он обрабатывает только служебный трафик (текст, уведомления). Фото, видео и файлы идут **напрямую** между клиентом и дата-центром Telegram — через прокси не проходят.

Скрипт находит три ограничения и берёт минимум:

```
CPU  →  с AES-NI:  60 000 conn/ядро  →  12 000 польз./ядро
         без AES-NI: 12 000 conn/ядро  →   2 400 польз./ядро

RAM  →  40 КБ на соединение (буферы ядра + MTProxy)
         1 746 МБ своб. → 38 195 conn → 7 639 польз.

Сеть →  ~5 КБ/с на пользователя (только служебный трафик)
         1 Гбит/с → ~21 250 польз.

Узкое место → минимум из трёх = реальный лимит
```

Скрипт показывает **два числа**:

| Показатель | Что значит |
|---|---|
| **Connected** | держат TCP-сессию (idle) — ограничено RAM |
| **Active (~10%)** | реально пишут прямо сейчас — ограничено CPU |

**Примеры для типичных VPS (с AES-NI):**

| Конфигурация | Connected | Active |
|---|---:|---:|
| 1 ядро / 512 МБ / 100 Мбит | ~640 | ~64 |
| 1 ядро / 2 ГБ / 1 Гбит | ~7 600 | ~760 |
| 2 ядра / 4 ГБ / 1 Гбит | ~16 700 | ~1 670 |
| 4 ядра / 8 ГБ / 1 Гбит | ~21 250 | ~2 125 |
| 8 ядер / 32 ГБ / 10 Гбит | ~64 000 | ~6 400 |

> Ёмкость на 1 ядро / 2 ГБ RAM кажется большой — и это правда: реальный оператор держал 200 клиентов на сервере за $3.5/мес при 99.9% CPU idle.

---

## 🖥️ Поддерживаемые системы

<div align="center">

| ОС | Версии | Статус |
|---|---|---|
| **Ubuntu** | 20.04, 22.04, 24.04 | ✅ Поддерживается |
| **Debian** | 10, 11, 12 | ✅ Поддерживается |
| **CentOS** | 7, 8 Stream | ✅ Поддерживается |
| **Rocky Linux** | 8, 9 | ✅ Поддерживается |
| **AlmaLinux** | 8, 9 | ✅ Поддерживается |

</div>

---

## 📱 Как подключиться

**Способ 1 — По ссылке (проще всего)**

После установки скопируйте ссылку из вывода скрипта и нажмите на неё — Telegram сам предложит подключиться.

```
https://t.me/proxy?server=ВАШ_IP&port=443&secret=ВАШ_СЕКРЕТ
```

**Способ 2 — Вручную**

```
Android:  Настройки → Данные и память → Прокси
iOS:      Настройки → Данные и память → Прокси
Desktop:  Настройки → Продвинутые → Тип соединения
```

Тип: **MTProto** · Сервер: `ВАШ_IP` · Порт: `443` · Секрет: `ВАШ_СЕКРЕТ`

---

## 🛠️ Управление сервером

```bash
# Статус
systemctl status mtproxy

# Логи в реальном времени
journalctl -u mtproxy -f

# Перезапуск
systemctl restart mtproxy

# Остановить
systemctl stop mtproxy

# Посмотреть секрет
cat /opt/mtproxy/secret.txt

# Статистика (только локально)
curl http://127.0.0.1:8888/stats
```

---

## ❓ FAQ

<details>
<summary><b>Почему сборка идёт из форка, а не официального репо?</b></summary>

Официальный репо `TelegramMessenger/MTProxy` заброшен и не обновлялся годами. На современных дистрибутивах с GCC ≥ 10 (Ubuntu 22+, Debian 12+) он падает с ошибками компиляции из-за отсутствия флага `-fcommon`. Скрипт использует форк `GetPageSpeed/MTProxy` — актуальный и поддерживаемый.

</details>

<details>
<summary><b>Что такое AES-NI и зачем скрипт его проверяет?</b></summary>

AES-NI — аппаратное ускорение шифрования в процессоре. MTProxy шифрует трафик через AES-256-CTR. С AES-NI одно ядро держит до **60 000 соединений** (официальный лимит Telegram), без него — около 12 000. Все современные VPS имеют AES-NI, скрипт проверяет `/proc/cpuinfo` и учитывает это в расчёте.

</details>

<details>
<summary><b>Почему прокси потребляет так мало трафика?</b></summary>

MTProxy работает только на этапе установки MTProto-сессии. После этого медиа (фото, видео, файлы) идут **напрямую** между клиентом и DC Telegram, минуя прокси. Через прокси проходит только текст и уведомления — ~2–5 КБ/с на активного пользователя. Реальный оператор за год работы передал через прокси всего ~17 МБ.

</details>

<details>
<summary><b>В чём разница между Connected и Active?</b></summary>

**Connected** — пользователи, которые держат открытую TCP-сессию (Telegram работает в фоне). Это ограничено RAM: каждое соединение занимает ~40 КБ буферов ядра.

**Active (~10%)** — пользователи, которые прямо сейчас пишут сообщения. В реальности в любой момент активны около 10% подключённых.

</details>

<details>
<summary><b>Прокси может читать мои сообщения?</b></summary>

Нет. Весь трафик Telegram зашифрован на стороне клиента по протоколу MTProto. Оператор прокси видит только факт подключения и IP-адрес, но не содержимое переписки.

</details>

<details>
<summary><b>Почему порт 443?</b></summary>

Порт 443 — стандартный HTTPS. Трафик на него выглядит как обычный веб-сёрфинг, что сильно затрудняет блокировку со стороны провайдеров и DPI-систем.

</details>

<details>
<summary><b>Нужен ли сервер за рубежом?</b></summary>

Не обязательно. VPS в России нередко работает стабильнее зарубежного: DPI активнее фильтрует трансграничный трафик, а подключение к российскому IP на порт 443 выглядит как обычный HTTPS. Главное — чтобы сам сервер имел доступ к серверам Telegram.

</details>

<details>
<summary><b>Как обновить конфигурацию Telegram вручную?</b></summary>

```bash
curl -fsSL https://core.telegram.org/getProxyConfig -o /opt/mtproxy/proxy-multi.conf
systemctl restart mtproxy
```

Скрипт настраивает автообновление через cron каждую ночь в 03:00, так что вручную это делать не нужно.

</details>

<details>
<summary><b>Прокси перестал работать — что делать?</b></summary>

```bash
# Посмотреть что происходит
systemctl status mtproxy
journalctl -u mtproxy -n 50

# Попробовать перезапустить
systemctl restart mtproxy
```

Если ошибка в логах связана с бинарником — запустите скрипт установки повторно, он пересоберёт MTProxy из исходников.

</details>

---

## 🤝 Вклад в проект

Нашли баг или есть идея?

1. Сделайте [Fork](https://github.com/sxcvio/Auto-MTProto/fork) репозитория
2. Создайте ветку: `git checkout -b fix/описание`
3. Сделайте коммит: `git commit -m 'fix: описание изменения'`
4. Откройте [Pull Request](https://github.com/sxcvio/Auto-MTProto/pulls)

Или просто откройте [Issue](https://github.com/sxcvio/Auto-MTProto/issues).

---

<div align="center">

Сделано с ❤️ автором **[SXCVIO](https://github.com/sxcvio)**

*Если проект оказался полезным — поставьте ⭐ звезду!*

</div>
