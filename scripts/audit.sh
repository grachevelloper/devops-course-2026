#!/usr/bin/env bash
set -uo pipefail

PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        printf '  [OK]   %s\n' "$desc"
        ((PASS++))
    else
        printf "  [FAIL] %s (ожидалось: '%s', получено: '%s')\n" "$desc" "$expected" "$actual"
        ((FAIL++))
    fi
}

export LC_ALL=C
printf 'Аудит конфигурации: %s, %s\n' "$(hostname -f)" "$(date '+%Y-%m-%d %H:%M')"
printf '[1] Служба SSH\n'
SSH_CONFIG=$(sudo sshd -T)
check "Вход от имени root запрещён" "no" "$(awk '/^permitrootlogin /{print $2}' <<< "$SSH_CONFIG")"
check "Парольная аутентификация отключена" "no" "$(awk '/^passwordauthentication /{print $2}' <<< "$SSH_CONFIG")"
SSH_PORT=$(awk '/^port /{print $2}' <<< "$SSH_CONFIG")
NONSTANDARD_PORT=no
if [[ "$SSH_PORT" =~ ^[0-9]+$ ]] && [[ "$SSH_PORT" -ne 22 ]]; then
    NONSTANDARD_PORT=yes
fi
check "Порт SSH отличается от 22" "yes" "$NONSTANDARD_PORT"
check "Лимит попыток аутентификации равен 3" "3" "$(awk '/^maxauthtries /{print $2}' <<< "$SSH_CONFIG")"

printf '[2] Межсетевой экран\n'
UFW_STATUS=$(sudo ufw status verbose)
check "Межсетевой экран активен" "active" "$(awk '/^Status:/{print $2}' <<< "$UFW_STATUS")"
check "Входящий трафик по умолчанию запрещён" "deny" "$(sed -n 's/^Default: \([^ ]*\) (incoming).*/\1/p' <<< "$UFW_STATUS")"

printf '[3] Учётные записи\n'
awk -F: '$3 >= 1000 && $3 < 65534 {printf "    %s (uid=%s)\n", $1, $3}' /etc/passwd

printf 'Пройдено: %s, не пройдено: %s\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
