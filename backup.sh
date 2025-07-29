#!/bin/bash
# Aether Player - Система резервного копирования
# Создает бэкапы конфигурации для быстрого восстановления

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
    echo "💾 AETHER PLAYER - РЕЗЕРВНОЕ КОПИРОВАНИЕ"
    echo "=================================================="
    echo -e "${NC}"
}

# Настройки
AETHER_PATH="/home/$USER/aether-player"
BACKUP_BASE_DIR="/mnt/music/aether-backups"  # На внешнем диске
BACKUP_LOCAL_DIR="$AETHER_PATH/backups"      # Локальная копия
DATE_STAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="aether-backup-$DATE_STAMP"

# Создание структуры папок для бэкапов
create_backup_structure() {
    print_status "Создаем структуру папок для бэкапов..."
    
    # Создаем папки
    mkdir -p "$BACKUP_LOCAL_DIR"
    mkdir -p "$BACKUP_BASE_DIR" 2>/dev/null || {
        print_warning "Внешний диск недоступен, используем только локальное копирование"
        BACKUP_BASE_DIR="$BACKUP_LOCAL_DIR/external"
        mkdir -p "$BACKUP_BASE_DIR"
    }
    
    print_success "Папки созданы!"
}

# Создание полного бэкапа конфигурации
create_config_backup() {
    print_status "Создаем бэкап конфигурации..."
    
    BACKUP_PATH="$BACKUP_BASE_DIR/$BACKUP_NAME"
    mkdir -p "$BACKUP_PATH"
    
    # Создаем манифест бэкапа
    cat > "$BACKUP_PATH/backup-manifest.txt" << EOF
=== AETHER PLAYER BACKUP ===
Дата создания: $(date)
Хост: $(hostname)
Пользователь: $USER
Версия системы: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)
IP адрес: $(hostname -I | awk '{print $1}')

Содержимое бэкапа:
- Код приложения (app.py, static/, templates/)
- Конфигурационные файлы
- Системные настройки (systemd service)
- Скрипты управления
- Python зависимости
- Git конфигурация

НЕ включено:
- Медиа файлы (слишком большие)
- Логи (.log файлы)
- Временные файлы
- Виртуальное окружение (пересоздается)
EOF
    
    # Копируем основные файлы проекта
    print_status "Копируем файлы проекта..."
    rsync -av --exclude='.venv' --exclude='*.log' --exclude='__pycache__' \
          --exclude='media' --exclude='backups' \
          "$AETHER_PATH/" "$BACKUP_PATH/project/"
    
    # Копируем системные конфигурации
    print_status "Копируем системные конфигурации..."
    mkdir -p "$BACKUP_PATH/system"
    
    # Systemd сервис
    if [ -f "/etc/systemd/system/aether-player.service" ]; then
        cp "/etc/systemd/system/aether-player.service" "$BACKUP_PATH/system/"
    fi
    
    # Cron задачи
    crontab -l > "$BACKUP_PATH/system/crontab.txt" 2>/dev/null || echo "# Нет cron задач" > "$BACKUP_PATH/system/crontab.txt"
    
    # Настройки аудио (если есть)
    if [ -f "/home/$USER/.asoundrc" ]; then
        cp "/home/$USER/.asoundrc" "$BACKUP_PATH/system/"
    fi
    
    # Сетевые настройки
    cp /etc/dhcpcd.conf "$BACKUP_PATH/system/" 2>/dev/null || true
    cp /etc/wpa_supplicant/wpa_supplicant.conf "$BACKUP_PATH/system/" 2>/dev/null || true
    
    # Создаем requirements.txt с точными версиями
    if [ -d "$AETHER_PATH/.venv" ]; then
        source "$AETHER_PATH/.venv/bin/activate"
        pip freeze > "$BACKUP_PATH/project/requirements-frozen.txt"
        deactivate
    fi
    
    print_success "Конфигурация скопирована в $BACKUP_PATH"
}

# Создание скрипта восстановления
create_restore_script() {
    print_status "Создаем скрипт восстановления..."
    
    BACKUP_PATH="$BACKUP_BASE_DIR/$BACKUP_NAME"
    
    cat > "$BACKUP_PATH/restore.sh" << 'EOF'
#!/bin/bash
# Скрипт восстановления Aether Player из бэкапа

set -e

echo "🔄 ВОССТАНОВЛЕНИЕ AETHER PLAYER ИЗ БЭКАПА"
echo "========================================"

RESTORE_PATH="/home/$USER/aether-player"
BACKUP_DIR="$(dirname "$0")"

echo "Восстанавливаем из: $BACKUP_DIR"
echo "Целевая папка: $RESTORE_PATH"
echo

# Останавливаем сервис если запущен
sudo systemctl stop aether-player 2>/dev/null || true

# Создаем резервную копию текущего состояния
if [ -d "$RESTORE_PATH" ]; then
    echo "Создаем резервную копию текущего состояния..."
    mv "$RESTORE_PATH" "$RESTORE_PATH.backup-$(date +%Y%m%d_%H%M%S)"
fi

# Восстанавливаем файлы проекта
echo "Восстанавливаем файлы проекта..."
cp -r "$BACKUP_DIR/project" "$RESTORE_PATH"

# Восстанавливаем системные настройки
echo "Восстанавливаем системные настройки..."
if [ -f "$BACKUP_DIR/system/aether-player.service" ]; then
    sudo cp "$BACKUP_DIR/system/aether-player.service" "/etc/systemd/system/"
    sudo systemctl daemon-reload
fi

# Восстанавливаем cron
if [ -f "$BACKUP_DIR/system/crontab.txt" ] && [ -s "$BACKUP_DIR/system/crontab.txt" ]; then
    crontab "$BACKUP_DIR/system/crontab.txt"
fi

# Создаем виртуальное окружение
echo "Создаем виртуальное окружение..."
cd "$RESTORE_PATH"
python3 -m venv .venv
source .venv/bin/activate

# Устанавливаем зависимости
if [ -f "requirements-frozen.txt" ]; then
    pip install -r requirements-frozen.txt
else
    pip install -r requirements.txt
fi

# Создаем папку для медиа
mkdir -p "$RESTORE_PATH/media"

# Устанавливаем права
chmod +x *.sh

echo
echo "✅ ВОССТАНОВЛЕНИЕ ЗАВЕРШЕНО!"
echo
echo "Для запуска выполните:"
echo "  sudo systemctl enable aether-player"
echo "  sudo systemctl start aether-player"
echo
EOF
    
    chmod +x "$BACKUP_PATH/restore.sh"
    print_success "Скрипт восстановления создан!"
}

# Создание архива бэкапа
create_backup_archive() {
    print_status "Создаем архив бэкапа..."
    
    cd "$BACKUP_BASE_DIR"
    tar -czf "$BACKUP_NAME.tar.gz" "$BACKUP_NAME/"
    
    # Проверяем размер архива
    ARCHIVE_SIZE=$(du -h "$BACKUP_NAME.tar.gz" | cut -f1)
    print_success "Архив создан: $BACKUP_NAME.tar.gz ($ARCHIVE_SIZE)"
    
    # Создаем символьную ссылку на последний бэкап
    ln -sf "$BACKUP_NAME.tar.gz" "latest-backup.tar.gz"
    ln -sf "$BACKUP_NAME" "latest-backup"
    
    print_success "Ссылка на последний бэкап обновлена"
}

# Очистка старых бэкапов
cleanup_old_backups() {
    print_status "Очищаем старые бэкапы..."
    
    cd "$BACKUP_BASE_DIR"
    
    # Оставляем только последние 5 архивов
    ls -t aether-backup-*.tar.gz 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true
    
    # Оставляем только последние 3 папки
    ls -td aether-backup-*/ 2>/dev/null | tail -n +4 | xargs rm -rf 2>/dev/null || true
    
    print_success "Старые бэкапы очищены (оставлены последние 5)"
}

# Создание локальной копии
create_local_copy() {
    print_status "Создаем локальную копию бэкапа..."
    
    # Копируем последний архив в локальную папку
    if [ -f "$BACKUP_BASE_DIR/latest-backup.tar.gz" ]; then
        cp "$BACKUP_BASE_DIR/latest-backup.tar.gz" "$BACKUP_LOCAL_DIR/"
        print_success "Локальная копия создана в $BACKUP_LOCAL_DIR/"
    fi
}

# Тестирование бэкапа
test_backup() {
    print_status "Тестируем созданный бэкап..."
    
    BACKUP_PATH="$BACKUP_BASE_DIR/$BACKUP_NAME"
    
    # Проверяем основные файлы
    REQUIRED_FILES=(
        "backup-manifest.txt"
        "restore.sh"
        "project/app.py"
        "project/requirements.txt"
        "system/aether-player.service"
    )
    
    for file in "${REQUIRED_FILES[@]}"; do
        if [ ! -f "$BACKUP_PATH/$file" ]; then
            print_error "Отсутствует файл: $file"
            return 1
        fi
    done
    
    # Проверяем архив
    if [ -f "$BACKUP_BASE_DIR/$BACKUP_NAME.tar.gz" ]; then
        if tar -tzf "$BACKUP_BASE_DIR/$BACKUP_NAME.tar.gz" >/dev/null 2>&1; then
            print_success "Архив корректен"
        else
            print_error "Архив поврежден!"
            return 1
        fi
    fi
    
    print_success "Бэкап прошел проверку!"
}

# Главная функция
main() {
    print_header
    
    print_status "Создаем резервную копию Aether Player..."
    echo
    
    create_backup_structure
    create_config_backup
    create_restore_script
    create_backup_archive
    create_local_copy
    cleanup_old_backups
    test_backup
    
    echo
    print_success "🎉 РЕЗЕРВНОЕ КОПИРОВАНИЕ ЗАВЕРШЕНО!"
    echo
    print_status "Созданы файлы:"
    echo "  📁 Папка:  $BACKUP_BASE_DIR/$BACKUP_NAME/"
    echo "  📦 Архив:  $BACKUP_BASE_DIR/$BACKUP_NAME.tar.gz"
    echo "  🔗 Ссылка: $BACKUP_BASE_DIR/latest-backup.tar.gz"
    echo "  💾 Локально: $BACKUP_LOCAL_DIR/latest-backup.tar.gz"
    echo
    print_status "Для восстановления:"
    echo "  1. Распакуйте архив на новом RPi"
    echo "  2. Запустите ./restore.sh"
    echo
}

# Запускаем создание бэкапа
main
