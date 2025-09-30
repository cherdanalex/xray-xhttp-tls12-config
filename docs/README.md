# Xray Server with XHTTP and TLS 1.2 Configuration

Автоматизированное развертывание Xray сервера с поддержкой XHTTP, TLS 1.2/1.3, Reality протоколом и полной интеграцией компонентов.

## 🚀 Ключевые особенности

- **XHTTP Support** - современный транспортный протокол для лучшей производительности
- **Полная интеграция** - все компоненты работают как единая система
- **Поддержка .env** - все настройки в одном файле
- **Idempotency** - безопасный повторный запуск без дублирования
- **Улучшенное логирование** - детальные логи в `/var/log/xray-deploy.log`
- **Автоматическое управление правилами** - чистая копия настроек firewall
- **TLS 1.2/1.3 поддержка** - современная криптография
- **Reality протокол** - обход блокировок
- **Nginx интеграция** - надежный веб-сервер и прокси
- **Автоматическое обновление сертификатов** - Let's Encrypt интеграция

## 📁 Структура проекта

```
xray-xhttp-tls12-config/
├── configs/                      # Конфигурационные файлы
│   ├── xray-server.json.example      # Серверная конфигурация Xray с XHTTP
│   ├── xray-client.json.example      # Клиентская конфигурация с XHTTP
│   ├── nginx-xray-proxy.conf.example # Nginx прокси конфигурация
│   └── ufw-rules.conf                # Чистая копия правил firewall
├── scripts/                      # Скрипты развертывания
│   ├── deploy.sh                # Основной скрипт (просит данные, вызывает всё)
│   ├── update-cert.sh           # Обновление TLS сертификатов
│   └── firewall-setup.sh        # Настройка firewall с idempotency
├── systemd/                     # Systemd unit файлы
│   ├── xray.service             # Сервис Xray с ограничениями безопасности
│   └── nginx.service            # Кастомный сервис Nginx
├── docs/                        # Документация
│   ├── README.md                # Основная документация
│   ├── DEPLOYMENT.md            # Руководство по развертыванию
│   └── TROUBLESHOOTING.md       # Решение проблем
└── .gitignore                   # Игнорируемые файлы
```

## ⚡ Быстрый старт

### Требования

- Ubuntu 20.04+ или Debian 11+
- Root доступ (sudo)
- Домен, указывающий на ваш сервер
- Открытые порты 80, 443, и ваш SSH порт

### Установка одной командой

```bash
curl -fsSL https://raw.githubusercontent.com/cherdanalex/xray-xhttp-tls12-config/main/install-direct.sh -o /tmp/install.sh && sudo bash /tmp/install.sh
```

Скрипт автоматически:
1. **Запросит конфигурацию** (домен, email, порты, UUID)
2. **Создаст .env файл** с настройками
3. **Установит все зависимости** (Xray, Nginx, Certbot, UFW)
4. **Настроит firewall** с idempotency
5. **Получит SSL сертификат** через Let's Encrypt
6. **Запустит все сервисы** с правильными настройками
7. **Настроит автообновление** сертификатов

## 📋 Что устанавливается

- **Xray** - основной прокси сервер с XHTTP и Reality протоколом
- **Nginx** - веб-сервер и прокси с TLS 1.2/1.3
- **Certbot** - автоматические SSL сертификаты
- **UFW** - настройка firewall с чистой копией правил

## 🔧 Конфигурация через .env

После первого запуска создается файл `.env` с настройками:

```bash
# Xray XHTTP Server Configuration
DOMAIN=yourdomain.com
EMAIL=your@email.com
SSH_PORT=22
XRAY_UUID=your-uuid-here
XRAY_PORT=10000

# Reality Keys (DO NOT SHARE)
REALITY_PRIVATE_KEY=your-private-key
REALITY_PUBLIC_KEY=your-public-key
REALITY_SHORT_ID=your-short-id
```

## 🔄 Idempotency и безопасность

- **Безопасный повторный запуск** - правила не дублируются
- **Чистая копия настроек** - все правила сохраняются в `configs/ufw-rules.conf`
- **Валидация входных данных** - проверка доменов, email, портов, UUID
- **Ограничения systemd** - сервисы запускаются с минимальными правами

## 📱 Клиентская конфигурация

После развертывания клиентская конфигурация сохраняется в `client-configs/xray-client.json`.

### Поддерживаемые клиенты

- **v2rayN** (Windows) - с поддержкой XHTTP
- **v2rayNG** (Android) - с поддержкой XHTTP
- **V2RayU** (macOS)
- **Qv2ray** (Cross-platform)
- **Xray-core** (CLI)

## 🔄 Автоматическое обновление

- **Сертификаты** - автоматически обновляются через cron
- **Firewall правила** - проверяются при каждом запуске
- **Конфигурации** - пересоздаются из шаблонов при изменениях

## 📊 Мониторинг и логирование

### Логи

- **Основные логи**: `/var/log/xray-deploy.log`
- **Xray логи**: `/var/log/xray/`
- **Nginx логи**: `/var/log/nginx/`

### Команды мониторинга

```bash
# Проверить статус сервисов
sudo systemctl status xray nginx

# Посмотреть логи развертывания
sudo tail -f /var/log/xray-deploy.log

# Проверить firewall правила
sudo ufw status
```

## 🔒 Безопасность

- **Firewall** - минимальные правила с idempotency
- **Systemd ограничения** - сервисы с ограниченными правами
- **SSL/TLS** - современные протоколы и шифры
- **Reality протокол** - обход блокировок
- **XHTTP** - современный транспортный протокол
- **Автоматическое обновление** - сертификаты обновляются автоматически

## 📚 Документация

- [DEPLOYMENT.md](DEPLOYMENT.md) - Подробное руководство по развертыванию
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Решение распространенных проблем

## 🤝 Поддержка

При возникновении проблем:

1. Проверьте [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
2. Посмотрите логи: `tail -f /var/log/xray-deploy.log`
3. Проверьте статус сервисов: `systemctl status xray nginx`
4. Проверьте firewall: `ufw status`

## 🆕 Что нового в этой версии

- ✅ **XHTTP Support** - современный транспортный протокол
- ✅ **Поддержка .env** - все настройки в одном файле
- ✅ **Idempotency** - безопасный повторный запуск
- ✅ **Улучшенное логирование** - детальные логи всех операций
- ✅ **Чистая копия правил** - firewall правила сохраняются в конфиге
- ✅ **Безопасное создание .env** - защита от ошибок heredoc
- ✅ **Кастомный nginx.service** - улучшенная конфигурация systemd
- ✅ **Автоматическое управление** - все компоненты работают как единая система

## 📄 Лицензия

MIT License - см. файл LICENSE для деталей.
