#!/bin/bash
# Aether Player - Система мониторинга
# Проверяет состояние системы и отправляет уведомления о проблемах

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
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[ВНИМАНИЕ]${NC} $1"
}

print_error() {
    echo -e "${RED}[ПРОБЛЕМА]${NC} $1"
}

print_header() {
    echo -e "${PURPLE}"
    echo "=================================================="
    echo "🔍 AETHER PLAYER - МОНИТОРИНГ СИСТЕМЫ"
    echo "=================================================="
    echo -e "${NC}"
}

# Глобальные переменные для отчета
WARNINGS=0
ERRORS=0
REPORT_FILE="/tmp/aether-monitor-$(date +%Y%m%d-%H%M%S).txt"

# Функция для записи в отчет
write_report() {
    echo "$1" >> "$REPORT_FILE"
}

# Проверка температуры процессора
check_cpu_temperature() {
    print_status "Проверяем температуру процессора..."
    
    if command -v vcgencmd >/dev/null 2>&1; then
        TEMP=$(vcgencmd measure_temp | sed 's/temp=//' | sed 's/°C//')
        TEMP_INT=${TEMP%.*}
        
        write_report "Температура CPU: ${TEMP}°C"
        
        if [ "$TEMP_INT" -gt 75 ]; then
            print_error "Критическая температура: ${TEMP}°C (>75°C)"
            ((ERRORS++))
        elif [ "$TEMP_INT" -gt 65 ]; then
            print_warning "Высокая температура: ${TEMP}°C (>65°C)"
            ((WARNINGS++))
        else
            print_success "Температура в норме: ${TEMP}°C"
        fi
    else
        print_warning "Команда vcgencmd недоступна (не Raspberry Pi?)"
        write_report "Температура CPU: недоступна"
    fi
}

# Проверка использования диска
check_disk_usage() {
    print_status "Проверяем использование дискового пространства..."
    
    # Проверяем корневую файловую систему
    ROOT_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    write_report "Использование корневого диска: ${ROOT_USAGE}%"
    
    if [ "$ROOT_USAGE" -gt 90 ]; then
        print_error "Критически мало места на диске: ${ROOT_USAGE}%"
        ((ERRORS++))
    elif [ "$ROOT_USAGE" -gt 80 ]; then
        print_warning "Мало места на диске: ${ROOT_USAGE}%"
        ((WARNINGS++))
    else
        print_success "Место на диске в норме: ${ROOT_USAGE}%"
    fi
    
    # Проверяем папку медиа
    MEDIA_PATH="/home/$USER/aether-player/media"
    if [ -d "$MEDIA_PATH" ]; then
        MEDIA_SIZE=$(du -sh "$MEDIA_PATH" 2>/dev/null | cut -f1 || echo "неизвестно")
        write_report "Размер медиа папки: $MEDIA_SIZE"
        print_status "Размер медиа библиотеки: $MEDIA_SIZE"
    fi
}

# Проверка использования памяти
check_memory_usage() {
    print_status "Проверяем использование памяти..."
    
    MEM_USAGE=$(free | awk 'NR==2{printf "%.1f", $3*100/$2}')
    MEM_USAGE_INT=${MEM_USAGE%.*}
    
    write_report "Использование памяти: ${MEM_USAGE}%"
    
    if [ "$MEM_USAGE_INT" -gt 90 ]; then
        print_error "Критически мало памяти: ${MEM_USAGE}%"
        ((ERRORS++))
    elif [ "$MEM_USAGE_INT" -gt 80 ]; then
        print_warning "Мало памяти: ${MEM_USAGE}%"
        ((WARNINGS++))
    else
        print_success "Память в норме: ${MEM_USAGE}%"
    fi
}

# Проверка состояния сервиса Aether Player
check_aether_service() {
    print_status "Проверяем состояние сервиса Aether Player..."
    
    if systemctl is-active --quiet aether-player.service; then
        print_success "Сервис Aether Player запущен"
        write_report "Статус сервиса: ЗАПУЩЕН"
        
        # Проверяем доступность веб-интерфейса
        LOCAL_IP=$(hostname -I | awk '{print $1}')
        if curl -s --connect-timeout 5 "http://$LOCAL_IP:5000" >/dev/null; then
            print_success "Веб-интерфейс доступен"
            write_report "Веб-интерфейс: ДОСТУПЕН"
        else
            print_error "Веб-интерфейс недоступен!"
            write_report "Веб-интерфейс: НЕДОСТУПЕН"
            ((ERRORS++))
        fi
    else
        print_error "Сервис Aether Player остановлен!"
        write_report "Статус сервиса: ОСТАНОВЛЕН"
        ((ERRORS++))
    fi
}

# Проверка аудио системы
check_audio_system() {
    print_status "Проверяем аудио систему..."
    
    # Проверяем аудио устройства
    if command -v aplay >/dev/null 2>&1; then
        AUDIO_DEVICES=$(aplay -l 2>/dev/null | grep -c "card" || echo "0")
        write_report "Найдено аудио устройств: $AUDIO_DEVICES"
        
        if [ "$AUDIO_DEVICES" -eq 0 ]; then
            print_error "Аудио устройства не найдены!"
            ((ERRORS++))
        else
            print_success "Найдено аудио устройств: $AUDIO_DEVICES"
        fi
    else
        print_warning "Команда aplay недоступна"
        write_report "Аудио система: недоступна для проверки"
    fi
    
    # Проверяем PulseAudio
    if command -v pulseaudio >/dev/null 2>&1; then
        if pgrep -x pulseaudio >/dev/null; then
            print_success "PulseAudio запущен"
            write_report "PulseAudio: ЗАПУЩЕН"
        else
            print_warning "PulseAudio не запущен"
            write_report "PulseAudio: НЕ ЗАПУЩЕН"
            ((WARNINGS++))
        fi
    fi
}

# Проверка сетевого подключения
check_network() {
    print_status "Проверяем сетевое подключение..."
    
    # Получаем IP адрес
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    if [ -n "$LOCAL_IP" ]; then
        print_success "IP адрес: $LOCAL_IP"
        write_report "IP адрес: $LOCAL_IP"
    else
        print_error "IP адрес не получен!"
        write_report "IP адрес: НЕ ПОЛУЧЕН"
        ((ERRORS++))
    fi
    
    # Проверяем интернет соединение
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        print_success "Интернет соединение работает"
        write_report "Интернет: ДОСТУПЕН"
    else
        print_warning "Нет интернет соединения"
        write_report "Интернет: НЕДОСТУПЕН"
        ((WARNINGS++))
    fi
}

# Проверка логов на ошибки
check_logs() {
    print_status "Проверяем логи на ошибки..."
    
    # Проверяем логи systemd за последний час
    ERROR_COUNT=$(journalctl -u aether-player.service --since "1 hour ago" --no-pager | grep -i error | wc -l)
    write_report "Ошибок в логах за час: $ERROR_COUNT"
    
    if [ "$ERROR_COUNT" -gt 10 ]; then
        print_error "Много ошибок в логах: $ERROR_COUNT за час"
        ((ERRORS++))
    elif [ "$ERROR_COUNT" -gt 0 ]; then
        print_warning "Найдены ошибки в логах: $ERROR_COUNT за час"
        ((WARNINGS++))
    else
        print_success "Ошибок в логах не найдено"
    fi
}

# Проверка внешнего HDD (если подключен)
check_external_hdd() {
    print_status "Проверяем внешние накопители..."
    
    HDD_MOUNTED=false
    
    # Проверяем смонтированные USB устройства
    USB_MOUNTS=$(mount | grep -c "/dev/sd" 2>/dev/null || echo "0")
    write_report "Подключено USB дисков: $USB_MOUNTS"
    
    if [ "$USB_MOUNTS" -gt 0 ]; then
        print_success "Подключено USB дисков: $USB_MOUNTS"
        HDD_MOUNTED=true
        
        # Проверяем конкретные точки монтирования
        if [ -d "/mnt/music" ] && mountpoint -q "/mnt/music"; then
            HDD_USAGE=$(df /mnt/music | awk 'NR==2 {print $5}' | sed 's/%//')
            print_success "Медиа диск смонтирован, использовано: ${HDD_USAGE}%"
            write_report "Медиа диск: СМОНТИРОВАН (${HDD_USAGE}%)"
        fi
    else
        print_warning "Внешние USB диски не обнаружены"
        write_report "USB диски: НЕ ОБНАРУЖЕНЫ"
    fi
}

# Создание сводного отчета
generate_summary() {
    echo >> "$REPORT_FILE"
    echo "=== СВОДКА ===" >> "$REPORT_FILE"
    echo "Дата проверки: $(date)" >> "$REPORT_FILE"
    echo "Предупреждений: $WARNINGS" >> "$REPORT_FILE"
    echo "Ошибок: $ERRORS" >> "$REPORT_FILE"
    
    echo
    print_header
    echo -e "${BLUE}Дата проверки:${NC} $(date)"
    
    if [ "$ERRORS" -gt 0 ]; then
        echo -e "${RED}Статус: ТРЕБУЕТ ВНИМАНИЯ${NC}"
        echo -e "${RED}Критических проблем: $ERRORS${NC}"
    elif [ "$WARNINGS" -gt 0 ]; then
        echo -e "${YELLOW}Статус: ЕСТЬ ПРЕДУПРЕЖДЕНИЯ${NC}"
        echo -e "${YELLOW}Предупреждений: $WARNINGS${NC}"
    else
        echo -e "${GREEN}Статус: ВСЕ В ПОРЯДКЕ${NC}"
    fi
    
    echo
    print_status "Подробный отчет сохранен: $REPORT_FILE"
    
    # Предлагаем показать отчет
    if [ "$1" != "--silent" ]; then
        echo
        read -p "Показать подробный отчет? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cat "$REPORT_FILE"
        fi
    fi
}

# Функция отправки уведомлений (для будущего расширения)
send_notifications() {
    if [ "$ERRORS" -gt 0 ]; then
        # Здесь можно добавить отправку email, Telegram, etc.
        echo "КРИТИЧЕСКИЕ ПРОБЛЕМЫ: $ERRORS" > "/tmp/aether-alert.txt"
        echo "Требуется немедленное внимание!" >> "/tmp/aether-alert.txt"
    fi
}

# Главная функция
main() {
    # Если запущено с --silent, не показываем заголовок
    if [ "$1" != "--silent" ]; then
        print_header
        print_status "Начинаем диагностику системы..."
        echo
    fi
    
    # Создаем файл отчета
    echo "=== ОТЧЕТ МОНИТОРИНГА AETHER PLAYER ===" > "$REPORT_FILE"
    echo "Генерация: $(date)" >> "$REPORT_FILE"
    echo >> "$REPORT_FILE"
    
    # Выполняем все проверки
    check_cpu_temperature
    check_disk_usage
    check_memory_usage
    check_aether_service
    check_audio_system
    check_network
    check_logs
    check_external_hdd
    
    # Генерируем сводку
    generate_summary "$1"
    
    # Отправляем уведомления при критических проблемах
    send_notifications
    
    # Возвращаем код ошибки для использования в cron
    if [ "$ERRORS" -gt 0 ]; then
        exit 1
    elif [ "$WARNINGS" -gt 0 ]; then
        exit 2
    else
        exit 0
    fi
}

# Запускаем мониторинг
main "$@"
