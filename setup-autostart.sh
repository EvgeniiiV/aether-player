#!/bin/bash

# Скрипт для настройки автоматического запуска Aether Player через systemd

echo "🔧 Настройка автоматического запуска Aether Player..."

# Создаем systemd сервис
SERVICE_FILE="/etc/systemd/system/aether-player.service"

echo "📝 Создаем файл сервиса..."
sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=Aether Player Music Server
After=network.target multi-user.target
Requires=network.target

[Service]
Type=simple
User=eu
Group=eu
WorkingDirectory=/home/eu/aether-player
Environment=PATH=/usr/bin:/usr/local/bin:/home/eu/.local/bin
ExecStartPre=/bin/bash -c 'sleep 10'
ExecStartPre=/home/eu/aether-player/mount-hdd.sh
ExecStart=/usr/bin/python3 -c "import sys; sys.path.insert(0, '.'); from app import app; app.run(host='0.0.0.0', port=5000, debug=False)"
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Перезагружаем systemd
echo "🔄 Перезагружаем systemd..."
sudo systemctl daemon-reload

# Включаем автозапуск
echo "⚡ Включаем автозапуск..."
sudo systemctl enable aether-player.service

# Запускаем сервис
echo "🚀 Запускаем сервис..."
sudo systemctl start aether-player.service

# Ждем запуска
sleep 5

# Проверяем статус
echo "📋 Статус сервиса:"
sudo systemctl status aether-player.service --no-pager -l

echo ""
echo "✅ Настройка завершена!"
echo ""
echo "🔄 Управление сервисом:"
echo "  - Статус: sudo systemctl status aether-player"
echo "  - Остановить: sudo systemctl stop aether-player"
echo "  - Запустить: sudo systemctl start aether-player"
echo "  - Перезапустить: sudo systemctl restart aether-player"
echo "  - Отключить автозапуск: sudo systemctl disable aether-player"
echo "  - Логи: sudo journalctl -u aether-player -f"
echo ""
echo "🌐 Сервер доступен по адресу:"
echo "  http://$(hostname -I | awk '{print $1}'):5000"
echo ""
echo "🔌 После полной перезагрузки RPi (sudo reboot) сервер запустится автоматически"
echo "⚡ Для перезапуска только сервиса: sudo systemctl restart aether-player"
