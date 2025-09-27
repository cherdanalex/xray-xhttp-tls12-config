#!/bin/bash
# deploy.sh - Автоматическое развертывание архитектуры xHTTP + TLS 1.2

echo "=========================================="
echo "Развертывание архитектуры xHTTP + TLS 1.2"
echo "=========================================="

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo "Ошибка: Запустите скрипт с правами root (sudo)"
    exit 1
fi

# Остановка сервисов
echo "Остановка сервисов..."
systemctl stop xray 2>/dev/null || true
systemctl stop nginx 2>/dev/null || true

# Резервное копирование текущих конфигураций
echo "Создание резервных копий..."
BACKUP_DIR="/root/backup-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Копирование текущих конфигураций
if [ -f "/usr/local/etc/xray/config.json" ]; then
    cp /usr/local/etc/xray/config.json "$BACKUP_DIR/xray-config.json.backup"
    echo "✓ Резервная копия Xray конфигурации создана"
fi

if [ -f "/etc/nginx/sites-available/default" ]; then
    cp /etc/nginx/sites-available/default "$BACKUP_DIR/nginx-default.backup"
    echo "✓ Резервная копия Nginx конфигурации создана"
fi

# Установка Nginx если не установлен
if ! command -v nginx &> /dev/null; then
    echo "Установка Nginx..."
    apt update
    apt install -y nginx
    echo "✓ Nginx установлен"
fi

# Создание конфигурации Nginx
echo "Создание конфигурации Nginx..."
cp configs/nginx-xray-proxy.conf /etc/nginx/sites-available/xray-xhttp-proxy

# Включение сайта Nginx
echo "Настройка Nginx..."
ln -sf /etc/nginx/sites-available/xray-xhttp-proxy /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Копирование конфигурации Xray
echo "Настройка Xray..."
cp configs/xray-config.json /usr/local/etc/xray/config.json

# Настройка файрвола
echo "Настройка файрвола..."
ufw allow 443/tcp
ufw allow out 443/tcp
ufw deny 10000/tcp
ufw allow from 127.0.0.1 to any port 10000
ufw allow 22/tcp
ufw --force enable
echo "✓ Файрвол настроен"

# Тест конфигурации Nginx
echo "Проверка конфигурации Nginx..."
if nginx -t; then
    echo "✓ Конфигурация Nginx корректна"
else
    echo "✗ Ошибка в конфигурации Nginx"
    exit 1
fi

# Запуск сервисов
echo "Запуск сервисов..."
systemctl start nginx
systemctl start xray

# Проверка статуса сервисов
echo "Проверка статуса сервисов..."
if systemctl is-active --quiet nginx; then
    echo "✓ Nginx запущен"
else
    echo "✗ Ошибка запуска Nginx"
fi

if systemctl is-active --quiet xray; then
    echo "✓ Xray запущен"
else
    echo "✗ Ошибка запуска Xray"
fi

# Проверка портов
echo "Проверка портов..."
if netstat -tlnp | grep -q ":443 "; then
    echo "✓ Порт 443 открыт"
else
    echo "✗ Порт 443 не открыт"
fi

if netstat -tlnp | grep -q ":10000 "; then
    echo "✓ Порт 10000 открыт (локально)"
else
    echo "✗ Порт 10000 не открыт"
fi

echo ""
echo "=========================================="
echo "Развертывание завершено!"
echo "=========================================="
echo ""
echo "Архитектура:"
echo "Client (xHTTP + TLS 1.2) → Nginx:443 (TLS терминация) → Xray:10000 (xHTTP plain)"
echo ""
echo "Следующие шаги:"
echo "1. Замените 'your-domain.com' на ваш домен в конфигурации Nginx"
echo "2. Настройте SSL сертификаты"
echo "3. Перезапустите сервисы: systemctl restart nginx xray"
echo ""
echo "Резервные копии сохранены в: $BACKUP_DIR"
