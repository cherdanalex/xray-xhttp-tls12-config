# Руководство по развертыванию Xray XHTTP сервера

Подробное руководство по установке и настройке интегрированного Xray сервера с XHTTP, TLS 1.2/1.3, Reality протоколом и поддержкой .env.

## 🚀 Автоматическая установка

### Быстрый запуск - одна команда

```bash
curl -fsSL https://raw.githubusercontent.com/cherdanalex/xray-xhttp-tls12-config/main/install-direct.sh -o /tmp/install.sh && sudo bash /tmp/install.sh
```

**Внутри уже всё спросит и настроит!**

## 📋 Что происходит при установке

### 1. Сбор конфигурации
Скрипт запрашивает следующие данные:

#### Домен
```
Enter your domain name (e.g., example.com): yourdomain.com
```
- Должен быть валидным доменом
- Должен указывать на ваш сервер
- Не должен содержать протокол (http://) или путь

#### Email для Let's Encrypt
```
Enter your email for Let's Encrypt: your@email.com
```
- Используется для уведомлений о сертификатах
- Должен быть валидным email адресом

#### SSH порт
```
Enter SSH port (default: 22): 22
```
- Порт для SSH доступа
- По умолчанию 22
- **ВАЖНО**: Убедитесь, что знаете этот порт!

#### UUID клиента
```
Enter UUID for Xray client (press Enter to generate): 
```
- Уникальный идентификатор для клиента
- Если не указан, генерируется автоматически
- **ВАЖНО**: Сохраните этот UUID!

#### Внутренний порт Xray
```
Enter Xray internal port (default: 10000): 10000
```
- Порт для внутреннего общения Xray с Nginx
- По умолчанию 10000

### 2. Создание .env файла
Все настройки сохраняются в `.env`:

```bash
# Xray XHTTP Server Configuration
DOMAIN=yourdomain.com
EMAIL=your@email.com
SSH_PORT=22
XRAY_UUID=12345678-1234-1234-1234-123456789abc
XRAY_PORT=10000

# Reality Keys (DO NOT SHARE)
REALITY_PRIVATE_KEY=your-private-key-here
REALITY_PUBLIC_KEY=your-public-key-here
REALITY_SHORT_ID=abcd1234
```

### 3. Установка компонентов
- **Обновление системы** - обновляет пакеты
- **Установка зависимостей**: Xray, Nginx, Certbot, UFW
- **Настройка firewall** - с idempotency и чистой копией правил
- **Конфигурация Nginx** - создает конфиг для прокси с XHTTP поддержкой
- **Получение SSL сертификата** - через Let's Encrypt
- **Настройка Xray** - создает конфигурацию сервера с XHTTP
- **Запуск сервисов** - стартует все необходимые сервисы
- **Настройка автообновления** - добавляет cron задачи

## 🔄 Idempotency и повторный запуск

### Безопасный повторный запуск
```bash
# Повторный запуск не сломает существующую конфигурацию
sudo ./scripts/deploy.sh
```

При повторном запуске:
- ✅ Загружается существующий `.env` файл
- ✅ Предлагается переконфигурация (y/N)
- ✅ Firewall правила не дублируются
- ✅ Существующие сертификаты сохраняются
- ✅ Конфигурации обновляются из шаблонов

## 📊 Проверка установки

### Проверка сервисов
```bash
# Статус Xray
sudo systemctl status xray

# Статус Nginx
sudo systemctl status nginx

# Проверка портов
sudo netstat -tlnp | grep -E ':(80|443|10000)'
```

### Проверка SSL сертификата
```bash
# Проверка сертификата
openssl s_client -connect $DOMAIN:443 -servername $DOMAIN

# Проверка через certbot
sudo certbot certificates
```

### Проверка логов
```bash
# Логи развертывания
sudo tail -f /var/log/xray-deploy.log

# Логи Xray
sudo tail -f /var/log/xray/error.log

# Логи Nginx
sudo tail -f /var/log/nginx/error.log
```

## 🔄 Обновление и обслуживание

### Обновление сертификатов
```bash
# Ручное обновление
sudo ./scripts/update-cert.sh

# Проверка cron задач
sudo crontab -l
```

### Обновление конфигураций
```bash
# После изменения .env файла
export $(cat .env | xargs)
sudo envsubst < configs/xray-server.json.example > /etc/xray/config.json
sudo envsubst < configs/nginx-xray-proxy.conf.example > /etc/nginx/sites-available/xray-proxy
sudo systemctl reload xray nginx
```

### Проверка firewall правил
```bash
# Текущие правила
sudo ufw status

# Чистая копия в конфиге
cat configs/ufw-rules.conf
```

## 📱 Настройка клиента

После успешной установки используйте конфигурацию из `client-configs/xray-client.json` для настройки вашего клиента.

### Клиенты с поддержкой XHTTP

- **v2rayN** (Windows) - последняя версия
- **v2rayNG** (Android) - последняя версия
- **Xray-core** (CLI) - для всех платформ

## 🗑️ Удаление

Для полного удаления:

```bash
# Остановка сервисов
sudo systemctl stop xray nginx
sudo systemctl disable xray nginx

# Удаление конфигураций
sudo rm -rf /etc/xray
sudo rm -f /etc/nginx/sites-available/xray-proxy
sudo rm -f /etc/nginx/sites-enabled/xray-proxy

# Удаление сертификатов (опционально)
sudo certbot delete --cert-name $DOMAIN

# Удаление Xray
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove

# Удаление cron задач
sudo crontab -l | grep -v "update-cert.sh" | sudo crontab -

# Удаление логов
sudo rm -f /var/log/xray-deploy.log
sudo rm -rf /var/log/xray
```

## 📝 Следующие шаги

После успешной установки:

1. **Протестируйте подключение** с помощью клиентской конфигурации
2. **Настройте клиент** с параметрами из `client-configs/xray-client.json`
3. **Мониторьте логи** для выявления проблем
4. **Настройте мониторинг** (опционально)
5. **Создайте резервные копии** конфигураций

## 🆘 Получение помощи

При возникновении проблем:

1. Проверьте [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
2. Посмотрите логи развертывания
3. Проверьте статус всех сервисов
4. Убедитесь в правильности DNS настроек
