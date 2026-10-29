# Конфигурация виртуальной машины devops-vm

Владелец: Тараканов Леонид Валентинович, ЭФБО-11-24. Репозиторий: https://github.com/inexcusableevil/devops-course-2026.

## 1. Параметры машины

VirtualBox 7.2.22 на macOS 15.4.1 Apple Silicon. Ubuntu Server 24.04.5 LTS ARM64, стандартная серверная установка без графической среды, English, раскладка US. Имя машины `devops-vm`, память 2048 МБ, 2 процессора, диск VDI 25 ГБ с динамическим выделением. EFI, контроллер диска VirtioSCSI. После обновления ядро `6.8.0-147-generic`. Диск целиком используется системой: EFI 1 ГБ, остальное раздел `/`. Часовой пояс `Europe/Moscow`.

## 2. Сетевые интерфейсы

| Интерфейс | MAC | Режим | Адрес | Назначение |
|---|---|---|---|---|
| enp0s8 | 08:00:27:a5:16:f7 | NAT | 10.0.2.15/24, DHCP | Исходящий доступ в Интернет; шлюз 10.0.2.2 |
| enp0s9 | 08:00:27:bd:92:7d | Host-only, devops-hostonly | 192.168.56.2/24, статический | Доступ с Mac; адрес хоста 192.168.56.1; внешнего шлюза нет |

На актуальной macOS в VirtualBox используется **Host-only Network**, эквивалентный по назначению Host-only Adapter из методички. Во время установки DHCP назначал .2, после установки .3. Чтобы имя и дальнейший деплой не зависели от смены адреса, в установленной системе закреплён .2. Других виртуальных машин в этом сегменте нет.

В `/etc/netplan/50-cloud-init.yaml` интерфейсы сопоставлены по указанным MAC. Для `nat`: `dhcp4: true`, `accept-ra: false`, `dhcp4-overrides: {use-dns: false}`, `nameservers: {addresses: [192.168.0.1]}`. Для `hostonly`: `dhcp4: false`, `addresses: [192.168.56.2/24]`. Права netplan-файла 600. Применение: `sudo netplan apply`.

DNS-прокси NAT 10.0.2.3 и внешние UDP DNS оказались недоступны; прямой запрос к DNS маршрутизатора 192.168.0.1 работал. Этот адрес указан явно. При переносе Mac в другую сеть проверить актуальный DNS маршрутизатора и изменить его в netplan. Функция Host Resolver включена и в настройках NAT, однако сама по себе проблему на данном хосте не устранила.

На Mac `/etc/hosts` содержит `192.168.56.2 devops.local`; проверка `dscacheutil -q host -a name devops.local`. На VM строка `127.0.1.1 devops-vm.devops.local devops-vm`; `hostname -f` возвращает `devops-vm.devops.local`.

## 3. Правило проброса портов

Адаптер 1 NAT: имя `ssh`, TCP, адрес хоста `127.0.0.1`, порт хоста `2222`, адрес гостя не указан. До усиления SSH гостевой порт 22; после настройки гостевой порт **2222**. Правило не публикуется на всех интерфейсах Mac.

```sh
VBoxManage modifyvm devops-vm --nat-pf1 delete=ssh
VBoxManage modifyvm devops-vm --nat-pf1 'ssh,tcp,127.0.0.1,2222,,2222'
```

Команды `modifyvm` применяются к выключенной VM. При работающей машине используются `VBoxManage controlvm devops-vm natpf1 delete ssh` и `VBoxManage controlvm devops-vm natpf1 'ssh,tcp,127.0.0.1,2222,,2222'`. На Mac исполняемый файл находится в `/Applications/VirtualBox.app/Contents/MacOS/VBoxManage`.

## 4. Учётные записи

`student` (UID 1000) создан установщиком и имеет sudo; используется для локальной консоли и восстановления после снимка. `devops` (UID 1001) входит в `devops`, `sudo`, `users`; для удалённой работы разрешён только вход этой учётной записи по отдельному ключу Ed25519. Пароли сохранены владельцем отдельно и в Git не размещаются. Пароль sudo не отменён, `NOPASSWD` не используется.

На Mac ключи `~/.ssh/devops_vm` (600) и `~/.ssh/devops_vm.pub`; отпечаток открытого ключа `SHA256:nsw14+e4azm25VifRjxyC8sQoyrif1rnCqy7modPt5U`. На VM каталог `/home/devops/.ssh` имеет права 700, `authorized_keys` — 600, владелец devops. Закрытый ключ не копируется на VM и не попадает в репозиторий.

Отпечаток ключа хоста Ed25519 сверен через консоль: `SHA256:QE4zSqUiEWbbjAS8nKrxJV3bHXJkzlIDa706TQFY6hM`. Доверенные ключи сохраняются на Mac в `~/.ssh/known_hosts`.

Конфигурация клиента Mac:

```sshconfig
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
    ControlMaster auto
    ControlPath ~/.ssh/devops-%C
    ControlPersist 120
```

Для прямого подключения по Host-only добавлен отдельный блок `Host devops.local` с `HostName devops.local`, `Port 2222`, `User devops`, `IdentityFile ~/.ssh/devops_vm`, `IdentitiesOnly yes`. Блок `Host devops` сам по себе не применяется к имени devops.local; без второго блока клиент не предъявлял выделенный ключ.

Мультиплексирование позволяет повторно использовать одно SSH-соединение и не исчерпывать лимит UFW при последовательных командах доставки. Для завершения: `ssh -O exit devops`.

## 5. Служба SSH

Исходный `/etc/ssh/sshd_config` не изменён; резервная копия `/etc/ssh/sshd_config.backup`. Дополняющий файл `/etc/ssh/sshd_config.d/99-hardening.conf` совпадает с `config/ssh/99-hardening.conf` в репозитории:

```text
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

В `/etc/ssh/sshd_config.d/50-cloud-init.conf` закомментирована строка `PasswordAuthentication yes`: OpenSSH использует первое встреченное значение, поэтому файл 99 не переопределял бы файл 50. Перед применением обязательны `sudo sshd -t` и `sudo sshd -T`. Сокетная активация отключена: `sudo systemctl disable --now ssh.socket`; обычная служба включена: `sudo systemctl enable --now ssh.service`. Затем `sudo systemctl restart ssh`. `sudo ss -tlnp` показывает 0.0.0.0:2222 и [::]:2222.

Во время изменения порта исходная сессия оставалась открытой. Новая сессия по ключу проверена до её закрытия. Вход root и вход с `PubkeyAuthentication=no` отклоняются. В обоих случаях клиент фактически показал `Permission denied (publickey)`; журнал сервера для root дополнительно указывает запрет по AllowUsers. До усиления сервер предлагал `publickey,password`, после — только `publickey`.

## 6. Правила межсетевого экрана

UFW активен и включён при загрузке: deny incoming, allow outgoing; routed disabled. Правила IPv4 и IPv6: 2222/tcp LIMIT с комментарием `SSH rate-limited`, 80/tcp ALLOW HTTP, 443/tcp ALLOW HTTPS. Регистрация `medium`, журнал `/var/log/ufw.log`.

```sh
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 2222/tcp comment 'SSH'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw enable
sudo ufw delete allow 2222/tcp
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw logging medium
sudo ufw status verbose
```

Разрешение SSH создаётся **до** включения экрана. Проверка нового соединения выполняется при сохранённой исходной сессии. `ufw allow ssh` не используется: это правило открыло бы стандартный порт 22 из `/etc/services`.

Проверка заблокированного порта: с Mac `curl -m 3 http://192.168.56.2:8080` возвращает тайм-аут; запись UFW содержит SRC=192.168.56.1, DST=192.168.56.2, PROTO=TCP, DPT=8080. Факультативный сервер на 127.0.0.1:8080 был доступен через `ssh -L 9090:127.0.0.1:8080 -N devops`, затем `curl http://localhost:9090`. Внешний трафик идёт через разрешённый SSH 2222, а соединение с 8080 создаёт sshd на loopback VM.

## 7. Снимки состояния

| Снимок | Момент создания и содержание |
|---|---|
| 01-clean-install | После установки Ubuntu, исправления сети и успешного обновления, VM выключена; ещё нет devops и усиления SSH |
| 02-keys-configured | После создания devops, добавления в sudo и проверки входа отдельным ключом; SSH ещё 22 |
| 03-ssh-hardened | После переноса SSH на 2222, запрета root и паролей, проверки второго подключения; перед включением UFW |

VM и снимки сохраняются для следующих практических работ. Восстановление снимка меняет гостевую конфигурацию; сверять правило NAT с реальным портом SSH. После отката 01 нужно вернуть гостевой порт правила на 22, а после усиления — снова 2222.

### Восстановление после 01-clean-install

1. Выключить VM, восстановить снимок 01-clean-install. В NAT вернуть гостевой порт 22, запустить VM. Исходные сеть, DNS и ключ хоста уже содержатся в снимке. Подключиться `ssh -p 2222 student@127.0.0.1` и не закрывать сессию до финальной проверки.
2. На VM `sudo adduser devops` (задать сохранённый владельцем пароль), `sudo usermod -aG sudo devops`. На Mac `ssh-copy-id -i ~/.ssh/devops_vm.pub -p 2222 devops@127.0.0.1`. Проверить `ssh devops` и права 700/600.
3. Передать конфигурацию `scp config/ssh/99-hardening.conf devops:/tmp/99-hardening.conf`. На VM:

```sh
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
sudo sed -i 's/^PasswordAuthentication yes/# PasswordAuthentication yes/' /etc/ssh/sshd_config.d/50-cloud-init.conf
sudo install -o root -g root -m 644 /tmp/99-hardening.conf /etc/ssh/sshd_config.d/99-hardening.conf
sudo sshd -t
sudo sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers)'
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
sudo ss -tlnp | grep sshd
```

4. На Mac изменить правило NAT на гостевой порт 2222 по разделу 3. В отдельном терминале проверить `ssh devops`, отказ root и отказ парольного входа. До успешной проверки исходное соединение не закрывать.
5. На VM выполнить все команды UFW из раздела 6. Проверить новое подключение. Выполнить `sudo hostnamectl set-hostname devops-vm` и `sudo sed -i 's/^127.0.1.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts`, затем `sudo timedatectl set-timezone Europe/Moscow`.
6. Для проверки именно состояния ПР №5 получить версию аудита `git show 1f40882:scripts/audit.sh > /tmp/audit-pr5.sh` на хосте и доставить её в `/home/devops/scripts/audit.sh`, установить право выполнения `chmod +x`, запустить в терминале после `sudo -v`. Ожидается 6 успешных проверок и код 0; проверить подключение по `devops.local`.

Скрипт проверяет эффективную конфигурацию SSH, нестандартный порт, MaxAuthTries=3, активность UFW и политику deny. Отрицательный тест: временно MaxAuthTries=10 — одна ошибка и код 1; восстановить 3 и проверить `sshd -t`. Без TTY запускать `sudo scripts/audit.sh`, иначе sudo внутри дочернего процесса потребует интерактивного подтверждения.


## 8. Веб-сервер

Пакет Ubuntu `nginx`, фактически установлен 1.24.0-2ubuntu7.19. Главный процесс — root, рабочие — www-data. Каталог `/var/www/devops-site` принадлежит devops:devops, каталоги 755, файлы 644. www-data читает файлы, но не записывает их. Единственная активная конфигурация `/etc/nginx/sites-available/devops-site`; ссылка `/etc/nginx/sites-enabled/devops-site`. Её полное содержимое сохранено в `config/nginx/devops-site.conf`. Файл стандартного ресурса сохранён, отключена только ссылка `sites-enabled/default`.

Восстановление веб-сервера после разделов 1–7:

```sh
# VM
sudo apt update && sudo apt install -y nginx rsync
sudo mkdir -p /var/www/devops-site
sudo chown devops:devops /var/www/devops-site
sudo chmod 755 /var/www/devops-site
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key -out /etc/ssl/certs/devops.crt \
  -subj '/CN=devops.local' -addext 'subjectAltName=DNS:devops.local'
sudo chown root:root /etc/ssl/private/devops.key /etc/ssl/certs/devops.crt
sudo chmod 600 /etc/ssl/private/devops.key
sudo chmod 644 /etc/ssl/certs/devops.crt
# Mac, из корня репозитория
scp config/nginx/devops-site.conf devops:/tmp/devops-site.conf
# VM
sudo install -o root -g root -m 644 /tmp/devops-site.conf /etc/nginx/sites-available/devops-site
sudo ln -sfn /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/devops-site
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
# Mac
scp devops:/etc/ssl/certs/devops.crt ~/devops.crt
rsync -avz --delete --chmod=D755,F644 --dry-run site/ devops:/var/www/devops-site/
rsync -avz --delete --chmod=D755,F644 site/ devops:/var/www/devops-site/
curl -4 -I http://devops.local
curl -4 --cacert ~/devops.crt -I https://devops.local
```

Закрытый ключ `/etc/ssl/private/devops.key` (root:root, 600) не копируется и не публикуется. Открытый сертификат `/etc/ssl/certs/devops.crt` (root:root, 644) передан на Mac через проверенное SSH-соединение. Срок — 365 дней: фактический сертификат выдан 30.10.2026 01:19:39 MSK и истекает 30.10.2027 01:19:39 MSK. SAN — DNS:devops.local; subject и issuer совпадают. При повторном выпуске сертификата нужно повторить безопасное копирование на клиента. Корневой процесс Nginx читает ключ до обслуживания запросов рабочими процессами.

HTTP перенаправляется кодом 301 на HTTPS. HSTS для учебного самоподписанного сертификата не добавлен. Журнал HTTPS ресурса — `/var/log/nginx/devops-site.access.log`, ошибки — `/var/log/nginx/devops-site.error.log`. Блок HTTP не задаёт отдельный access_log, поэтому его перенаправления записываются в общий `/var/log/nginx/access.log`.

На данном Mac встроенный openrsync (совместимый с 2.6.9) отклонил `--chmod=D755,F644`; установлена современная версия `brew install rsync`, фактически 3.5.1 в `/opt/homebrew/bin/rsync`. Проверять `command -v rsync` и `rsync --version`. В curl используется `-4`: имя .local на этом Mac при попытке разрешения обоих семейств адресов иногда приводило к задержке, тогда как IPv4 из hosts работал. В Chrome после очистки кэша имени пользователем сайт открылся.

Сценарий `scripts/deploy.sh [--dry-run]` находит корень по расположению самого сценария, проверяет наличие index.html и чистоту Git, вызывает ровно один rsync через SSH с BatchMode=yes и ConnectTimeout=5, нормализует права и удаляет лишние файлы в каталоге назначения. Проверка HTTPS выполняется curl с --cacert, без -k. Dry-run не проверяет HTTP и не меняет сервер. Успех выводит короткий хеш коммита. На Mac ключ и профиль SSH настроены по разделу 4, сертификат находится в `~/devops.crt`.

Пять обязательных сценариев проверены: dry-run — 0 и неизменный SHA256; изменение с коммитом — 0 и видно в браузере; незакоммиченное изменение (в том числе staged) — 1 без изменения SHA256 сервера; Nginx остановлен — синхронизация выполнена, HTTPS недоступен, код 1, служба затем запущена; index.html переименован с коммитом — 1 без удаления главной страницы на сервере, затем имя восстановлено отдельным коммитом.

Диагностика прав: файл 600 → HTTP 403 и `open() ... failed (13: Permission denied)`; каталог 755 → 200, 750 → 403, 744 → 403, 711 → 200. Для каталога с недостатком x журнал содержит `is forbidden (13: Permission denied)`. При 744 www-data видит имена, но не читает файл; при 711 читает известное имя, но не получает список. Во всех опытах восстановлены 755/644. Доставка файла 666 без --chmod позволила www-data записать `<h1>defaced</h1>`; штатный деплой восстановил содержимое и 644, после чего www-data touch отклонён.

Аудит содержит четыре проверки раздела [4]: активность Nginx, nginx -t, срок сертификата не менее 30 дней, отсутствие world-writable вместе с режимом ключа 600. Все 10 проверок проходят с кодом 0. `sudo env CERT_MIN_DAYS=400 scripts/audit.sh` даёт одну ошибку и код 1; временный chmod 666 index.html — также 1; после восстановления — 0. Для проверки в терминале VM достаточно sudo -v и запуска сценария; без TTY запускать весь сценарий через sudo.

Создан снимок `04-nginx-https` (UUID ec12bad8-86b0-4fee-bc3d-381b99dda5cc) на выключенной VM после успешных проверок TLS, деплоя и прав. Попытка живого снимка затянулась, отменена; VirtualBox оставил VMM приостановленным при внешнем состоянии Running. После разрешённого владельцем принудительного выключения сделан обычный снимок, VM запущена заново и конфигурация проверена. Конфигурация, сертификат, ключ и снимки сохраняются для практической работы №7.

Подготовка Docker: установлен официальный Docker Engine Community 29.9.2, Compose 5.6.1 из подписанного репозитория download.docker.com (Ubuntu noble/arm64), не docker.io. Учётная запись devops добавлена в docker (у неё уже есть sudo). Проверка `docker run hello-world` без sudo выполнена в новой группе через `sg docker -c`; получено Hello from Docker. Участник docker фактически имеет возможности root через подключение каталогов хоста. Полная последовательность установки сохранена в разделе 9 для восстановления конфигурации приложения.


## 9. Контейнеризация

Docker Engine Community 29.9.2 и Compose 5.6.1 установлены из официального подписанного репозитория Docker, Ubuntu noble/arm64. Пакет docker.io не устанавливался. В группе docker — devops, уже имеющий sudo. Членство даёт фактические возможности root через Docker API, поэтому дополнительных пользователей в группу не добавляем. Для применения членства нужна новая SSH-сессия; при существующем ControlMaster завершить её командой ssh -O exit devops и подключиться заново, либо однократно использовать sg docker -c.

Установка из официального репозитория (VM):

```sh
set -e
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl --connect-timeout 10 --max-time 60 -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker devops
# После новой SSH-сессии
docker version
docker compose version
docker run --rm hello-world
```

Проект на сервере — `/home/devops/app`, владелец devops:devops. Исходники, Dockerfile, требования и docker-compose.yml находятся в `app/` репозитория. Зависимости шаблона зафиксированы: Flask 3.0.3, psycopg2-binary 2.9.9, Gunicorn 22.0.0. Dockerfile использует python:3.12-slim, системного пользователя app и exec-форму CMD. Исходники в образе принадлежат root с правами 644; процесс app (UID/GID 999) читает их, но touch /app/app.py получает Permission denied. Порт EXPOSE 5000 является метаданными.

Доставка с Mac из корня репозитория, каждый новый вариант команды с --delete сначала в пробном режиме:

```sh
rsync -avz --delete --exclude=.env --dry-run app/ devops:app/
rsync -avz --delete --exclude=.env app/ devops:app/
```

`/home/devops/app/.env` создаётся исключительно на VM, права 600, devops:devops. Его нельзя переносить на Mac или добавлять в Git. В `.gitignore` и `.dockerignore` исключён .env; `.env.example` содержит только имена переменных и change_me. Исключение --exclude=.env защищает серверный файл от --delete.

```sh
# VM, только при первоначальной установке; секрет не выводить в журнал
cd /home/devops/app
umask 077
cp .env.example .env
chmod 600 .env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 16)/" .env
docker compose up -d --build
docker compose ps
```

На действующем томе не пересоздавать .env с новым паролем: PostgreSQL инициализируется переменными только при создании пустой базы. Хранить исходный файл на VM. Compose-проект app создаёт сеть bridge `app_backend`, сервисы app и db. DNS-имя db разрешается внутри сети в IP контейнера PostgreSQL; localhost внутри app — сам контейнер. Проверка `docker compose exec -T app getent hosts db </dev/null`. При автоматическом запуске через bash -s перенаправление stdin предотвращает поглощение остатка сценария командой compose exec.

Приложение опубликовано строго как `127.0.0.1:5000:5000`, база PostgreSQL 16-alpine не имеет ports. Проверять `sudo ss -tlnp` и `docker compose ps`: один хостовый сокет 127.0.0.1:5000, 5432 на хосте отсутствует. Зависимость app от db с condition service_healthy ждёт pg_isready (interval 5s, timeout 3s, retries 5), а не только запуска процесса. В healthcheck двойной $$ оставляет подстановку переменных оболочке внутри db.

Именованный том `app_db_data` смонтирован в `/var/lib/postgresql/data`; данные сохраняются независимо от контейнеров. Фактическая проверка: обращения дали Visits 1, 2, 3; перед down — 4, после down/up — 5. Учебный опыт down -v удалил только этот вновь созданный тестовый том; после up получено Visits 1. Финальный том сохранён. Не применять -v к данным, которые требуется сохранить. Тег postgres:16-alpine удерживает основную версию формата данных.

Снимок `05-docker-compose` (UUID a51f9995-936a-44a1-b579-8843a437f217) создан после штатного выключения VM. Содержит приложение, healthy-базу, .env и том; VM затем запущена. Живые снимки после затруднения с VirtualBox не используются.

Обратный прокси добавлен в HTTPS-блок `/etc/nginx/sites-available/devops-site`; полная конфигурация сохранена в `config/nginx/devops-site.conf`:

```nginx
    location /app/ {
        proxy_pass http://127.0.0.1:5000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
```

Завершающий / в proxy_pass заменяет /app/ на /; /app/health превращается в /health. Статический корень /var/www/devops-site сохранён. Применять только `sudo nginx -t && sudo systemctl reload nginx`. Восстановление: передать конфигурацию из репозитория как в разделе 8 и установить её теми же командами.

Проверки с Mac: `curl -4 --cacert ~/devops.crt https://devops.local/app/`, `/app/health` и `-I https://devops.local/`. Временный контейнер exposed с -p 5001:5000 подтвердил доступность /health с Mac при отсутствии правила UFW 5001: Docker создаёт DNAT и перенаправляет трафик в FORWARD до обычных входящих правил UFW. Контейнер остановлен после опыта. Loopback-публикация штатного приложения исключает прямой сетевой доступ.

При остановленном app запрос к /app/ получает 502; журнал /var/log/nginx/devops-site.error.log содержит connect() failed (111: Connection refused) while connecting to upstream. Отказ между Nginx и контейнером, TLS и сам Nginx доступны. Восстановить `cd /home/devops/app && docker compose start app`, дождаться /health и повторить запрос. Для полной остановки проекта использовать down без -v, для запуска — up -d.

Раздел [5] scripts/audit.sh проверяет Docker active, app-db-1 healthy, отсутствие внешних слушателей 5000/5432 и права .env 600. Полный аудит — 14 проверок, код 0. Отрицательный опыт: временно в серверном docker-compose.yml публикация 5000:5000, compose up -d; обнаружены 0.0.0.0:5000 и [::]:5000, код 1. После возврата 127.0.0.1:5000:5000 и пересоздания app — код 0. Файл .env и том при проверке не изменяются.

Для полного восстановления после снимка 01 последовательно выполнить разделы 1–8, установить Docker по разделу 9, доставить app/ с --exclude=.env, создать серверный секрет, поднять Compose, установить конфигурацию Nginx из репозитория и запустить аудит. Для сохранения существующих данных использовать имеющиеся .env и app_db_data. Секретов в репозитории нет.
