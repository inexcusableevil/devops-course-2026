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
6. Доставить `scripts/audit.sh` в `/home/devops/scripts/audit.sh`, установить право выполнения `chmod +x`, запустить в терминале после `sudo -v`. Ожидается 6 успешных проверок и код 0; проверить подключение по `devops.local`.

Скрипт проверяет эффективную конфигурацию SSH, нестандартный порт, MaxAuthTries=3, активность UFW и политику deny. Отрицательный тест: временно MaxAuthTries=10 — одна ошибка и код 1; восстановить 3 и проверить `sshd -t`. Без TTY запускать `sudo scripts/audit.sh`, иначе sudo внутри дочернего процесса потребует интерактивного подтверждения.
