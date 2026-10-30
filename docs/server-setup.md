# Конфигурация виртуальной машины devops-vm

Студент: Николай Грачев, ЭФБО-02-24. Практическая работа №5.

## 1. Параметры машины

VirtualBox 7.2.22 на macOS с Apple Silicon. Гостевая система — Ubuntu Server
24.04.5 LTS ARM64, без графической среды. Выделены 2048 МБ RAM, 2 ядра CPU,
динамический диск VDI объёмом 25 ГБ. Имя VM и hostname — `devops-vm`.

## 2. Сетевые интерфейсы

- `enp0s8`: NAT, адрес `10.0.2.15/24`, доступ к пакетным репозиториям.
- `enp0s9`: Host-only Network `devops-host-only`, адрес `192.168.56.2/24`,
  доступ с Mac. Адрес Mac в этой сети — `192.168.56.1`.

Адреса выдаёт DHCP. На современной macOS VirtualBox использует Host-only
Network вместо устаревшего Host-only Adapter. Bridged-сеть не используется.
Проверка: `ip -brief address`.

На Mac в `/etc/hosts` добавлены имена:

```text
192.168.56.2 devops.local api.devops.local
```

`api.devops.local` подготовлено для варианта 1 контрольной №2. На сервере:

```sh
sudo hostnamectl set-hostname devops-vm
sudo sed -i 's/^127.0.1.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts
hostname -f
```

Ожидаемый FQDN: `devops-vm.devops.local`.

## 3. Правило проброса портов

Правило NAT `ssh`: TCP, адрес хоста `127.0.0.1`, порт хоста `2222`.
При установке порт гостя равен `22`; после усиления SSH — `2222`.
Для запущенной VM изменение выполняется на Mac:

```sh
VBoxManage controlvm devops-vm natpf1 delete ssh
VBoxManage controlvm devops-vm natpf1 ssh,tcp,127.0.0.1,2222,,2222
```

Перед изменением удерживается отдельная SSH-сессия через Host-only.

## 4. Учётные записи

- `student`, UID 1000: создан установщиком, входит в sudo; нужен для исходного
  состояния и восстановления. После усиления SSH удалённый вход ему запрещён.
- `devops`, UID 1001: группы `devops`, `sudo`, `users`; управление сервером
  по отдельному Ed25519-ключу. Пароль используется для sudo, а не для SSH.
- `root`: пароль заблокирован; SSH-вход запрещён.

Создание `devops` после восстановления исходного снимка:

```sh
sudo adduser devops
sudo usermod -aG sudo devops
```

На Mac создана отдельная пара `~/.ssh/devops_vm` и `~/.ssh/devops_vm.pub`.
Закрытый ключ не копируется на VM и не добавляется в Git. Открытый ключ
устанавливается с Mac до отключения парольного входа:

```sh
ssh-copy-id -i ~/.ssh/devops_vm.pub -p 2222 devops@127.0.0.1
```

Права на VM: `~/.ssh` — 700, `authorized_keys` — 600, владелец devops.
Перед первым подключением отпечаток ключа хоста сверяется с консолью VM:

```sh
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

Проверенный Ed25519-отпечаток данного стенда:
`SHA256:r1ON7D61P5ZCxnjmEEiT3oWniMav7q7vT2UICKubFaA`.
Он сохраняется клиентом в `~/.ssh/known_hosts`.

В `~/.ssh/config` на Mac:

```sshconfig
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes

Host devops.local
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

## 5. Служба SSH

Основной файл `/etc/ssh/sshd_config` не изменён. Его копия сохранена как
`/etc/ssh/sshd_config.backup`. Изменения находятся в
`/etc/ssh/sshd_config.d/99-hardening.conf`; эталон включён в
`config/ssh/99-hardening.conf` этого репозитория:

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

При восстановлении сначала проверьте вход `devops` по ключу. Затем сохраните
рабочую SSH-сессию, установите drop-in и проверьте конфликты:

```sh
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
sudo install -m 644 config/ssh/99-hardening.conf /etc/ssh/sshd_config.d/99-hardening.conf
grep -r PasswordAuthentication /etc/ssh/sshd_config.d/ /etc/ssh/sshd_config
sudo sshd -t
sudo sshd -T | grep -Ei '^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers)'
```

Если более ранний drop-in содержит активную строку `PasswordAuthentication yes`,
закомментируйте именно эту строку: применяется первое прочитанное значение.
На данном стенде конфликтующая строка закомментирована; основной файл сохранён.

```sh
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
sudo ss -tlnp | grep sshd
```

Ожидаются `0.0.0.0:2222` и `[::]:2222`. После изменения NAT проверьте отдельные
новые соединения, не закрывая рабочее:

```sh
ssh devops
ssh -p 2222 -i ~/.ssh/devops_vm root@127.0.0.1
ssh -p 2222 -o PubkeyAuthentication=no devops@127.0.0.1
```

Первое успешно, остальные отклоняются. Клиент в обоих отказах может показать
`Permission denied (publickey)`; журнал различает запрет пользователя root
через AllowUsers и отсутствие принятого метода аутентификации у devops.
До усиления сервер предлагал `publickey,password`, после — только `publickey`.

## 6. Правила межсетевого экрана

UFW активен, включён при загрузке. Политики: deny incoming, allow outgoing.
Разрешены TCP 80 и 443; для TCP 2222 действует LIMIT. IPv6 включён,
соответствующие правила созданы и для IPv6. Логирование medium.

Порядок восстановления:

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

Разрешение SSH создаётся до активации. Новое соединение проверяется до закрытия
старой сессии. `ufw allow ssh` не заменяет правило 2222: имя ssh означает порт 22.
При доставке файлов следует учитывать лимит шесть соединений за 30 секунд.

Проверка с Mac `curl -m 3 http://192.168.56.2:8080` завершилась тайм-аутом.
В `/var/log/ufw.log` зарегистрировано: SRC=192.168.56.1, DST=192.168.56.2,
PROTO=TCP, DPT=8080. Это исходный адрес Mac, адрес VM, протокол и порт назначения.

Аудит: `scripts/audit.sh`, при работе без терминала — `sudo scripts/audit.sh`.
Корректная конфигурация даёт код 0; MaxAuthTries=10 даёт код 1.
После отрицательной проверки восстановлены MaxAuthTries=3 и код 0.

## 7. Снимки состояния

- `01-clean-install`: установленная и обновлённая Ubuntu, student, OpenSSH,
  два сетевых интерфейса, NAT 2222 → 22; до создания devops.
- `02-keys-configured`: пользователь devops и ключевой вход проверены,
  SSH ещё на порту 22, NAT 2222 → 22.
- `03-ssh-hardened`: SSH на 2222, вход по ключу работает, root и вход без ключа
  отклоняются, NAT 2222 → 2222. UFW настраивается следующим шагом работы.

Все три итоговых снимка сделаны на выключенной VM. Первая попытка live-снимка
02 зависла в VirtualBox; после отмены потребовался перезапуск учебной VM.
Затем состояние этапа настройки ключей было воспроизведено, и снимок 02
пересоздан без сохранения RAM. Дальнейшее усиление SSH повторено и проверено.

В начале №6 требуется восстановление со снимка 01 только по этому документу.
После восстановления нужно повторить разделы 3–6, доставить audit.sh и убедиться
в коде 0. Пароли и приватные ключи в репозитории отсутствуют.

## 8. Веб-сервер

Установлены пакеты `nginx` и `rsync` из репозитория Ubuntu:

```sh
sudo apt update
sudo apt install -y nginx rsync
```

На Mac встроенный openrsync 2.6.9 не принял обязательный параметр
`--chmod=D755,F644`. Установлен GNU rsync через `brew install rsync`;
в PATH перед `/usr/bin` должен находиться `/opt/homebrew/bin`.

Ресурс: `devops.local`. Каталог `/var/www/devops-site` принадлежит
`devops:devops`; каталоги имеют права 755, файлы — 644. `www-data` читает
страницы, но не может изменять их. Подготовка каталога:

```sh
sudo install -d -o devops -g devops -m 755 /var/www/devops-site
```

Конфигурация хранится в `config/nginx/devops-site`. На VM она устанавливается
в `/etc/nginx/sites-available/devops-site`. В `sites-enabled` находится только
ссылка на этот ресурс; ссылка `default` удалена, исходный файл сохранён:

```sh
sudo install -m 644 config/nginx/devops-site /etc/nginx/sites-available/devops-site
sudo ln -s /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/devops-site
sudo unlink /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

Команды `ln` и `unlink` относятся к первичной настройке. При повторной установке
существующую правильную ссылку сохраняют. Главный процесс Nginx работает от root,
рабочие — от www-data. HTTP на порту 80 возвращает 301 на HTTPS, порт 443
обслуживает статические файлы; неизвестный путь возвращает собственную страницу
404. Журналы — `/var/log/nginx/devops-site.access.log` и
`/var/log/nginx/devops-site.error.log`. Правила UFW 80/443 сохранены, профиль
Nginx Full дополнительно не разрешался.

Сертификат самоподписанный, RSA 2048, срок 365 дней, CN и SAN `devops.local`:

```sh
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj '/CN=devops.local' \
  -addext 'subjectAltName=DNS:devops.local'
sudo chmod 600 /etc/ssl/private/devops.key
sudo chmod 644 /etc/ssl/certs/devops.crt
sudo nginx -t && sudo systemctl reload nginx
```

Ключ принадлежит root и остаётся только в `/etc/ssl/private`; его читает главный
процесс Nginx. Сертификат общедоступен; на Mac он получен по ранее проверенному SSH:

```sh
scp devops:/etc/ssl/certs/devops.crt ~/devops.crt
curl --cacert ~/devops.crt -I https://devops.local
```

Без явного доверия `curl` завершился с кодом 60. Совпадающие subject и issuer
подтверждают самоподпись. HSTS не добавлен. Встроенный macOS LibreSSL не понимает
`openssl x509 -ext`; поля сертификата проверены OpenSSL внутри Ubuntu.

Доставка из чистой рабочей копии репозитория на Mac:

```sh
scripts/deploy.sh --dry-run
scripts/deploy.sh
```

Сценарий определяет корень Git, требует `site/index.html` и отсутствие всех
незафиксированных изменений, включая индекс и новые файлы. Один rsync через SSH
использует `--delete --chmod=D755,F644`; перед первым запуском выполнен dry-run.
После реальной доставки `curl --cacert` проверяет HTTPS. При ошибке сценарий
возвращает 1, при успехе — 0 и короткий хеш коммита. Пароль не запрашивается:
включены BatchMode и ConnectTimeout. UFW limit требует избегать шести новых
SSH-соединений за 30 секунд; служебные проверки используют одно соединение.

В начале работы VM действительно восстановлена с `01-clean-install`.
По разделам 3–6 восстановлены учётная запись, ключ, SSH, NAT, UFW и FQDN;
аудит вернул 0. Восстановление с проверкой заняло 21,9 секунды. Снимок
`04-nginx-https` сделан на выключенной VM после включения HTTPS с временной
страницей, до доставки основного сайта. Все журналы экспериментов сохранены
в `self/study/evidence/practice-6` на Mac.
