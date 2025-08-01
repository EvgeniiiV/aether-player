#!/bin/bash

# Установка автоматического управления питанием периферии

echo "🔧 Настройка автоматического управления питанием..."

SCRIPT_DIR="/home/eu/aether-player"
SERVICE_NAME="aether-power"

# Создаем systemd сервис для автозапуска
cat << 'EOF' | sudo tee /etc/systemd/system/aether-power.service > /dev/null
[Unit]
Description=Aether Player Power Management
After=multi-user.target
Before=aether-player.service

[Service]
Type=oneshot
RemainAfterExit=yes
User=root
WorkingDirectory=/home/eu/aether-player
ExecStart=/usr/bin/python3 /home/eu/aether-player/power-control.py on
ExecStop=/usr/bin/python3 /home/eu/aether-player/power-control.py safe-off
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF

# Создаем скрипт автозапуска для интеграции с основным сервисом
cat << 'EOF' | sudo tee /home/eu/aether-player/startup-with-power.sh > /dev/null
#!/bin/bash

# Скрипт комплексного запуска Aether Player с управлением питанием

echo "🚀 Запуск Aether Player с управлением питанием..."

# 1. Включаем питание периферии
/usr/bin/python3 /home/eu/aether-player/power-control.py on

# 2. Ждем стабилизации питания
sleep 3

# 3. Монтируем HDD
/home/eu/aether-player/mount-hdd.sh

# 4. Запускаем Aether Player
/home/eu/aether-player/start-server.sh

echo "✅ Система полностью запущена!"
EOF

sudo chmod +x /home/eu/aether-player/startup-with-power.sh
sudo chmod +x /home/eu/aether-player/power-control.sh

# Перезагружаем systemd
sudo systemctl daemon-reload

# Включаем автозапуск
sudo systemctl enable aether-power.service

echo ""
echo "✅ Настройка завершена!"
echo ""
echo "🔧 Управление сервисом:"
echo "  sudo systemctl start aether-power    - Запустить управление питанием"
echo "  sudo systemctl stop aether-power     - Остановить и безопасно выключить"
echo "  sudo systemctl status aether-power   - Статус сервиса"
echo ""
echo "🎛️ Ручное управление:"
echo "  ./power-control.sh on               - Включить питание"
echo "  ./power-control.sh safe-off         - Безопасно выключить"
echo "  ./power-control.sh status           - Проверить состояние"
echo ""
echo "⚠️ ВАЖНО: Подключите реле к GPIO 18 (pin 12) RPi"
echo "   GPIO 18 → Оптопара → Реле 220В → Розетки периферии"
