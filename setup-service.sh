#!/bin/bash
# Aether Player - Настройка системного сервиса
# Создает systemd сервис для автозапуска плеера при загрузке системы

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[УСПЕХ]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[ВНИМАНИЕ]${NC} $1"
}

print_error() {
    echo -e "${RED}[ОШИБКА]${NC} $1"
}

print_header() {
    echo -e "${PURPLE}"
    echo "=================================================="
    echo "🚀 AETHER PLAYER - НАСТРОЙКА АВТОЗАПУСКА"
    echo "=================================================="
    echo -e "${NC}"
}

# Проверяем, что установка завершена
check_installation() {
    print_status "Проверяем установку Aether Player..."
    
    if [ ! -f "/home/$USER/aether-player/app.py" ]; then
        print_error "Aether Player не найден! Сначала запустите install.sh"
        exit 1
    fi
    
    if [ ! -d "/home/$USER/aether-player/.venv" ]; then
        print_error "Python окружение не найдено! Сначала запустите install.sh"
        exit 1
    fi
    
    print_success "Установка найдена!"
}

# Создаем systemd сервис
create_systemd_service() {
    print_status "Создаем systemd сервис..."
    
    # Получаем абсолютные пути
    USER_HOME="/home/$USER"
    AETHER_PATH="$USER_HOME/aether-player"
    PYTHON_PATH="$AETHER_PATH/.venv/bin/python"
    
    # Создаем файл сервиса
    sudo tee /etc/systemd/system/aether-player.service > /dev/null << EOF
[Unit]
Description=Aether Player - Web Music Player
Documentation=https://github.com/EvgeniiiV/aether-player
After=network.target sound.service
Wants=network.target

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$AETHER_PATH
Environment=PYTHONPATH=$AETHER_PATH
Environment=PYTHONUNBUFFERED=1
ExecStart=$PYTHON_PATH app.py
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=10
KillMode=mixed
TimeoutStopSec=30

# Логирование
StandardOutput=journal
StandardError=journal
SyslogIdentifier=aether-player

# Безопасность
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ReadWritePaths=$AETHER_PATH

[Install]
WantedBy=multi-user.target
EOF
    
    print_success "Файл сервиса создан: /etc/systemd/system/aether-player.service"
}

# Создаем скрипт для ожидания HDD
create_hdd_wait_script() {
    print_status "Создаем скрипт ожидания HDD..."
    
    sudo tee /usr/local/bin/aether-wait-hdd.sh > /dev/null << 'EOF'
#!/bin/bash
# Скрипт ожидания внешнего HDD для медиа файлов

# Настройки (отредактируйте под ваши нужды)
HDD_DEVICE="/dev/sda1"          # USB HDD устройство
MOUNT_POINT="/mnt/music"        # Точка монтирования
MEDIA_LINK="/home/$USER/aether-player/media-hdd"  # Символьная ссылка
MAX_WAIT=60                     # Максимальное время ожидания (секунды)

echo "[$(date)] Ожидание HDD устройства $HDD_DEVICE..."

# Создаем точку монтирования
sudo mkdir -p "$MOUNT_POINT"

# Ожидаем появления устройства
for i in $(seq 1 $MAX_WAIT); do
    if [ -b "$HDD_DEVICE" ]; then
        echo "[$(date)] Устройство найдено! Монтируем..."
        
        # Монтируем устройство
        if sudo mount "$HDD_DEVICE" "$MOUNT_POINT" 2>/dev/null; then
            echo "[$(date)] HDD успешно смонтирован в $MOUNT_POINT"
            
            # Создаем символьную ссылку в папке проекта
            if [ -L "$MEDIA_LINK" ]; then
                rm "$MEDIA_LINK"
            fi
            ln -sf "$MOUNT_POINT" "$MEDIA_LINK"
            
            echo "[$(date)] Символьная ссылка создана: $MEDIA_LINK -> $MOUNT_POINT"
            exit 0
        else
            echo "[$(date)] Ошибка монтирования $HDD_DEVICE"
            exit 1
        fi
    fi
    
    echo "[$(date)] Ожидание... ($i/$MAX_WAIT)"
    sleep 1
done

echo "[$(date)] ВНИМАНИЕ: HDD не найден за $MAX_WAIT секунд. Продолжаем без него."
exit 0
EOF
    
    sudo chmod +x /usr/local/bin/aether-wait-hdd.sh
    print_success "Скрипт ожидания HDD создан: /usr/local/bin/aether-wait-hdd.sh"
}

# Настраиваем и запускаем сервис
setup_service() {
    print_status "Настраиваем systemd сервис..."
    
    # Перезагружаем systemd конфигурацию
    sudo systemctl daemon-reload
    
    # Включаем автозапуск
    sudo systemctl enable aether-player.service
    
    print_success "Автозапуск включен!"
    
    # Предлагаем запустить сейчас
    echo
    read -p "Запустить Aether Player сейчас? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        print_status "Запускаем сервис..."
        sudo systemctl start aether-player.service
        sleep 3
        
        # Проверяем статус
        if sudo systemctl is-active --quiet aether-player.service; then
            print_success "Сервис запущен успешно!"
            
            # Показываем IP адрес
            LOCAL_IP=$(hostname -I | awk '{print $1}')
            echo
            print_success "🎉 Aether Player доступен по адресу:"
            echo -e "${GREEN}   http://$LOCAL_IP:5000${NC}"
            echo
        else
            print_error "Ошибка запуска сервиса!"
            echo "Проверьте логи: sudo journalctl -u aether-player.service -f"
        fi
    fi
}

# Создаем скрипты управления
create_management_scripts() {
    print_status "Создаем скрипты управления..."
    
    # Скрипт для проверки статуса
    cat > "/home/$USER/aether-player/status.sh" << 'EOF'
#!/bin/bash
echo "🎵 Статус Aether Player:"
echo "========================"
systemctl status aether-player.service --no-pager -l
echo
echo "Последние логи:"
echo "==============="
journalctl -u aether-player.service -n 10 --no-pager
EOF
    
    # Скрипт для перезапуска
    cat > "/home/$USER/aether-player/restart.sh" << 'EOF'
#!/bin/bash
echo "🔄 Перезапускаем Aether Player..."
sudo systemctl restart aether-player.service
sleep 2
echo "✅ Готово!"
./status.sh
EOF
    
    # Скрипт для остановки
    cat > "/home/$USER/aether-player/stop.sh" << 'EOF'
#!/bin/bash
echo "⏹️ Останавливаем Aether Player..."
sudo systemctl stop aether-player.service
echo "✅ Остановлен!"
EOF
    
    # Делаем скрипты исполняемыми
    chmod +x "/home/$USER/aether-player/status.sh"
    chmod +x "/home/$USER/aether-player/restart.sh" 
    chmod +x "/home/$USER/aether-player/stop.sh"
    
    print_success "Скрипты управления созданы!"
}

# Главная функция
main() {
    print_header
    
    print_status "Настраиваем автозапуск Aether Player..."
    echo
    
    check_installation
    create_systemd_service
    create_hdd_wait_script
    setup_service
    create_management_scripts
    
    echo
    print_success "🎉 НАСТРОЙКА АВТОЗАПУСКА ЗАВЕРШЕНА!"
    echo
    print_status "Управление сервисом:"
    echo "  Статус:     ./status.sh"
    echo "  Перезапуск: ./restart.sh"
    echo "  Остановка:  ./stop.sh"
    echo
    print_status "Системные команды:"
    echo "  sudo systemctl start aether-player"
    echo "  sudo systemctl stop aether-player"
    echo "  sudo systemctl restart aether-player"
    echo "  sudo journalctl -u aether-player -f"
    echo
    print_warning "Для подключения HDD отредактируйте:"
    echo "  /usr/local/bin/aether-wait-hdd.sh"
    echo
}

# Запускаем настройку
main
