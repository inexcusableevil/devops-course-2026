#!/usr/bin/env bash
set -uo pipefail
PASS=0; FAIL=0
check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  [OK]   $desc"; ((PASS+=1))
    else
        echo "  [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"
        ((FAIL+=1))
    fi
}
echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"
echo "[1] Служба SSH"
SSH_CONFIG="$(sudo sshd -T)"
check "Вход от имени root запрещён" "no" "$(awk '/^permitrootlogin /{print $2}' <<< "$SSH_CONFIG")"
check "Парольная аутентификация отключена" "no" "$(awk '/^passwordauthentication /{print $2}' <<< "$SSH_CONFIG")"
SSH_PORT="$(awk '/^port /{print $2;exit}' <<< "$SSH_CONFIG")"
NONSTANDARD=no
[[ "$SSH_PORT" =~ ^[0-9]+$ && "$SSH_PORT" -ne 22 ]] && NONSTANDARD=yes
check "Порт SSH отличается от 22" "yes" "$NONSTANDARD"
check "MaxAuthTries равен 3" "3" "$(awk '/^maxauthtries /{print $2}' <<< "$SSH_CONFIG")"
echo "[2] Межсетевой экран"
UFW_STATUS="$(LC_ALL=C sudo ufw status verbose)"
check "Межсетевой экран активен" "active" "$(awk '/^Status:/{print $2}' <<< "$UFW_STATUS")"
check "Входящий трафик запрещён по умолчанию" "deny" "$(sed -nE 's/^Default: ([^ ]+) \(incoming\).*/\1/p' <<< "$UFW_STATUS")"
echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd
echo "[4] Веб-сервер"
check "Служба nginx активна" "active" "$(systemctl is-active nginx)"
NGINX_SYNTAX=no
sudo nginx -t >/dev/null 2>&1 && NGINX_SYNTAX=yes
check "Конфигурация nginx корректна" "yes" "$NGINX_SYNTAX"
CERT_MIN_DAYS="${CERT_MIN_DAYS:-30}"
CERT_OK=no
if [[ "$CERT_MIN_DAYS" =~ ^[0-9]+$ ]] && \
    openssl x509 -in /etc/ssl/certs/devops.crt -noout \
    -checkend "$((CERT_MIN_DAYS * 86400))" >/dev/null 2>&1; then
    CERT_OK=yes
fi
check "Сертификат действителен ещё минимум ${CERT_MIN_DAYS} дней" "yes" "$CERT_OK"
WEB_PERMISSIONS=no
WORLD_WRITABLE="$(find /var/www/devops-site -perm -o+w 2>&1)"
KEY_MODE="$(sudo stat -c '%a' /etc/ssl/private/devops.key)"
[[ -z "$WORLD_WRITABLE" && "$KEY_MODE" == 600 ]] && WEB_PERMISSIONS=yes
check "Нет записи для всех; закрытый ключ имеет права 600" "yes" "$WEB_PERMISSIONS"
echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
