# Решение проблем Xray XHTTP сервера

Руководство по диагностике и решению наиболее распространенных проблем при развертывании и работе интегрированного Xray сервера с XHTTP.

## 🔍 Общая диагностика

### Проверка статуса сервисов

```bash
# Проверить статус всех сервисов
sudo systemctl status xray nginx

# Проверить активные соединения
sudo netstat -tlnp | grep -E ':(80|443|10000)'

# Проверить использование портов
sudo ss -tlnp | grep -E ':(80|443|10000)'
```

### Проверка логов

```bash
# Логи развертывания (основные)
sudo tail -f /var/log/xray-deploy.log

# Логи Xray
sudo journalctl -u xray -f
sudo tail -f /var/log/xray/error.log

# Логи Nginx
sudo journalctl -u nginx -f
sudo tail -f /var/log/nginx/error.log
```

## ❌ Проблемы с портами

### Порт уже используется

**Симптомы:**
```
bind: address already in use
Failed to bind port 443
```

**Решение:**
```bash
# Найти процесс, использующий порт
sudo lsof -i :443
sudo netstat -tlnp | grep :443

# Остановить конфликтующий процесс
sudo systemctl stop apache2  # если Apache
sudo systemctl stop nginx    # если другой Nginx
```

### Порт заблокирован firewall

**Симптомы:**
```
Connection refused
Timeout connecting
```

**Решение:**
```bash
# Проверить правила UFW
sudo ufw status

# Добавить правило
sudo ufw allow 443/tcp

# Проверить чистую копию правил
cat configs/ufw-rules.conf
```

## 🔐 Проблемы с SSL сертификатами

### Сертификат не выдается

**Симптомы:**
```
Failed to obtain certificate
Certbot error
```

**Возможные причины и решения:**

#### 1. Домен не указывает на сервер
```bash
# Проверить DNS
nslookup yourdomain.com
dig yourdomain.com

# Проверить доступность порта 80
curl -I http://yourdomain.com
```

#### 2. Порт 80 заблокирован
```bash
# Проверить правила firewall
sudo ufw status
sudo ufw allow 80/tcp

# Проверить, что Nginx слушает на порту 80
sudo netstat -tlnp | grep :80
```

#### 3. Nginx не запущен
```bash
# Запустить Nginx
sudo systemctl start nginx
sudo systemctl enable nginx

# Проверить конфигурацию
sudo nginx -t
```

## 🌐 Проблемы с Nginx

### Nginx не запускается

**Симптомы:**
```
nginx: configuration file test failed
Failed to start nginx
```

**Решение:**
```bash
# Проверить конфигурацию
sudo nginx -t

# Проверить синтаксис
sudo nginx -T

# Посмотреть детальные ошибки
sudo journalctl -u nginx -n 50
```

### Nginx возвращает 502 Bad Gateway

**Симптомы:**
```
502 Bad Gateway
Connection refused to upstream
```

**Решение:**
```bash
# Проверить, что Xray запущен
sudo systemctl status xray

# Проверить, что Xray слушает на правильном порту
sudo netstat -tlnp | grep xray

# Проверить логи Nginx
sudo tail -f /var/log/nginx/error.log
```

## 🚀 Проблемы с Xray

### Xray не запускается

**Симптомы:**
```
Failed to start xray
xray: configuration error
```

**Решение:**
```bash
# Проверить конфигурацию
sudo xray -test -config /etc/xray/config.json

# Проверить права доступа
sudo ls -la /etc/xray/config.json
sudo chown xray:xray /etc/xray/config.json

# Проверить синтаксис JSON
sudo cat /etc/xray/config.json | jq .
```

### Xray не принимает соединения

**Симптомы:**
```
Connection refused
No inbound connections
```

**Решение:**
```bash
# Проверить, что Xray слушает на порту
sudo netstat -tlnp | grep xray

# Проверить firewall правила
sudo ufw status | grep 10000

# Проверить логи Xray
sudo tail -f /var/log/xray/error.log
```

### Проблемы с XHTTP

**Симптомы:**
```
XHTTP connection failed
Transport error
```

**Решение:**
```bash
# Проверить версию Xray (должна поддерживать XHTTP)
xray version

# Обновить Xray до последней версии
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# Проверить конфигурацию XHTTP
sudo cat /etc/xray/config.json | jq '.inbounds[0].streamSettings.xhttpSettings'
```

## 🔥 Проблемы с Firewall

### SSH доступ заблокирован

**Симптомы:**
```
Connection refused on SSH port
Unable to connect via SSH
```

**КРИТИЧЕСКАЯ ПРОБЛЕМА!**

**Решение:**
```bash
# Если у вас есть физический доступ к серверу:
sudo ufw disable
sudo ufw --force reset
sudo ufw allow 22/tcp
sudo ufw enable
```

### Неправильные правила firewall

**Симптомы:**
```
Services not accessible
Connection timeouts
```

**Решение:**
```bash
# Проверить текущие правила
sudo ufw status verbose

# Сбросить и пересоздать правила
sudo ./scripts/firewall-setup.sh

# Проверить чистую копию правил
cat configs/ufw-rules.conf
```

## 🌍 Проблемы с DNS

### Домен не резолвится

**Симптомы:**
```
Domain does not resolve
DNS lookup failed
```

**Решение:**
```bash
# Проверить DNS записи
nslookup yourdomain.com
dig yourdomain.com A

# Проверить с разных DNS серверов
nslookup yourdomain.com 8.8.8.8
nslookup yourdomain.com 1.1.1.1
```

## 📱 Проблемы с клиентами

### Клиент не подключается

**Симптомы:**
```
Connection failed
Handshake failed
XHTTP error
```

**Проверьте:**
1. Правильность UUID в клиенте
2. Правильность Reality ключей
3. Правильность домена
4. Правильность порта
5. Поддержка XHTTP в клиенте

```bash
# Проверить конфигурацию клиента
cat client-configs/xray-client.json

# Сравнить с серверной конфигурацией
sudo cat /etc/xray/config.json | jq .
```

### Медленное подключение

**Симптомы:**
```
Slow connection speed
High latency
```

**Решение:**
```bash
# Проверить нагрузку на сервер
htop

# Проверить сетевую статистику
ss -s

# Проверить логи на ошибки
sudo tail -f /var/log/xray/error.log
```

## 🔧 Проблемы с .env файлом

### .env файл поврежден

**Симптомы:**
```
.env: line X: command not found
Configuration not loaded
```

**Решение:**
```bash
# Удалить поврежденный .env
rm -f .env

# Перезапустить deploy.sh для создания нового
sudo ./scripts/deploy.sh
```

## 🔧 Восстановление после сбоя

### Полное восстановление

```bash
# Остановить все сервисы
sudo systemctl stop xray nginx

# Восстановить конфигурации из .env
export $(cat .env | xargs)
sudo envsubst < configs/xray-server.json.example > /etc/xray/config.json
sudo envsubst < configs/nginx-xray-proxy.conf.example > /etc/nginx/sites-available/xray-proxy

# Перезапустить сервисы
sudo systemctl start nginx xray

# Проверить статус
sudo systemctl status xray nginx
```

## 📞 Получение помощи

### Информация для отчета о проблеме

При обращении за помощью предоставьте:

```bash
# Системная информация
uname -a
lsb_release -a

# Версия Xray
xray version

# Статус сервисов
sudo systemctl status xray nginx

# Конфигурация (без ключей)
cat .env | grep -v REALITY_PRIVATE_KEY

# Последние логи
sudo tail -n 50 /var/log/xray-deploy.log
sudo tail -n 50 /var/log/xray/error.log
sudo tail -n 50 /var/log/nginx/error.log
```

### Полезные команды для диагностики

```bash
# Проверить все сервисы
sudo systemctl status xray nginx ufw

# Проверить логи в реальном времени
sudo tail -f /var/log/xray-deploy.log /var/log/xray/error.log /var/log/nginx/error.log

# Проверить конфигурации
sudo nginx -t
sudo xray -test -config /etc/xray/config.json

# Проверить .env файл
cat .env
```

Помните: всегда делайте резервные копии конфигураций перед изменениями!
