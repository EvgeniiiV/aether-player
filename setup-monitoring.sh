#!/bin/bash
# Настройка автоматического мониторинга Aether Player

# Цвета для вывода
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[УСПЕХ]${NC} $1"
}

print_header() {
    echo -e "${PURPLE}"
    echo "=================================================="
    echo "⏰ НАСТРОЙКА АВТОМАТИЧЕСКОГО МОНИТОРИНГА"
    echo "=================================================="
    echo -e "${NC}"
}

# Настройка cron задач для мониторинга
setup_monitoring_cron() {
    print_status "Настраиваем автоматический мониторинг..."
    
    AETHER_PATH="/home/$USER/aether-player"
    
    # Создаем временный файл с cron задачами
    TEMP_CRON=$(mktemp)
    
    # Сохраняем существующие cron задачи
    crontab -l 2>/dev/null > "$TEMP_CRON" || true
    
    # Удаляем старые задачи Aether Player (если есть)
    sed -i '/aether-player/d' "$TEMP_CRON"
    
    # Добавляем новые задачи
    cat >> "$TEMP_CRON" << EOF

# Aether Player - Автоматический мониторинг
# Проверка каждые 15 минут
*/15 * * * * $AETHER_PATH/monitor.sh --silent >/dev/null 2>&1

# Ежедневный отчет в 9:00
0 9 * * * $AETHER_PATH/monitor.sh > /tmp/aether-daily-report.txt 2>&1

# Еженедельная очистка старых логов (воскресенье в 2:00)
0 2 * * 0 find /tmp -name "aether-monitor-*.txt" -mtime +7 -delete 2>/dev/null

EOF
    
    # Устанавливаем новый crontab
    crontab "$TEMP_CRON"
    rm "$TEMP_CRON"
    
    print_success "Автоматический мониторинг настроен!"
    echo "  - Проверка системы каждые 15 минут"
    echo "  - Ежедневный отчет в 9:00"
    echo "  - Автоочистка старых отчетов"
}

# Создание скрипта для просмотра отчетов
create_report_viewer() {
    print_status "Создаем скрипт для просмотра отчетов..."
    
    cat > "/home/$USER/aether-player/reports.sh" << 'EOF'
#!/bin/bash
# Просмотр отчетов мониторинга

# Цвета
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}📊 ОТЧЕТЫ МОНИТОРИНГА AETHER PLAYER${NC}"
echo "======================================"

# Показываем последний ежедневный отчет
if [ -f "/tmp/aether-daily-report.txt" ]; then
    echo -e "${GREEN}📋 Последний ежедневный отчет:${NC}"
    echo "------------------------------"
    cat /tmp/aether-daily-report.txt
    echo
fi

# Показываем список всех отчетов
echo -e "${YELLOW}📁 Доступные отчеты:${NC}"
ls -la /tmp/aether-monitor-*.txt 2>/dev/null | tail -10 || echo "Отчеты не найдены"

echo
echo "Команды:"
echo "  ./monitor.sh          - Запустить проверку сейчас"
echo "  ./monitor.sh --silent - Тихая проверка"
echo "  crontab -l            - Показать расписание"
EOF
    
    chmod +x "/home/$USER/aether-player/reports.sh"
    print_success "Скрипт просмотра отчетов создан!"
}

# Главная функция
main() {
    print_header
    
    print_status "Настраиваем систему мониторинга..."
    echo
    
    setup_monitoring_cron
    create_report_viewer
    
    echo
    print_success "🎉 МОНИТОРИНГ НАСТРОЕН!"
    echo
    print_status "Управление мониторингом:"
    echo "  ./monitor.sh    - Запустить проверку вручную"
    echo "  ./reports.sh    - Просмотр отчетов"
    echo "  crontab -e      - Редактировать расписание"
    echo
    print_status "Мониторинг будет автоматически:"
    echo "  - Проверять систему каждые 15 минут"
    echo "  - Создавать ежедневные отчеты"
    echo "  - Очищать старые файлы"
    echo
}

# Запускаем настройку
main
