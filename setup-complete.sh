#!/bin/bash
# Aether Player - МАСТЕР УСТАНОВЩИК
# Полная автоматическая настройка домашнего музыкального центра
# Версия: 1.0 Production Ready

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[ЭТАП]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[ГОТОВО]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[ВНИМАНИЕ]${NC} $1"
}

print_error() {
    echo -e "${RED}[ОШИБКА]${NC} $1"
}

print_step() {
    echo -e "${CYAN}[ШАГ $1]${NC} $2"
}

print_header() {
    clear
    echo -e "${PURPLE}"
    cat << 'EOF'
████████╗██╗  ██╗███████╗████████╗██╗  ██╗███████╗██████╗ 
██╔═══██║██║  ██║██╔════╝╚══██╔══╝██║  ██║██╔════╝██╔══██╗
███████║███████║█████╗     ██║   ███████║█████╗  ██████╔╝
██╔═══██║██╔══██║██╔══╝     ██║   ██╔══██║██╔══╝  ██╔══██╗
██║   ██║██║  ██║███████╗   ██║   ██║  ██║███████╗██║  ██║
╚═╝   ╚═╝╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝

██████╗ ██╗      █████╗ ██╗   ██╗███████╗██████╗ 
██╔══██╗██║     ██╔══██╗╚██╗ ██╔╝██╔════╝██╔══██╗
██████╔╝██║     ███████║ ╚████╔╝ █████╗  ██████╔╝
██╔═══╝ ██║     ██╔══██║  ╚██╔╝  ██╔══╝  ██╔══██╗
██║     ███████╗██║  ██║   ██║   ███████╗██║  ██║
╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝
EOF
    echo -e "${NC}"
    echo -e "${CYAN}🏠 ДОМАШНИЙ МУЗЫКАЛЬНЫЙ ЦЕНТР - ПОЛНАЯ УСТАНОВКА${NC}"
    echo "================================================================="
    echo -e "${GREEN}Автоматическая настройка Raspberry Pi для воспроизведения музыки${NC}"
    echo "================================================================="
    echo
}

# Проверка предварительных условий
check_prerequisites() {
    print_step "1" "Проверяем готовность системы"
    
    # Проверяем Raspberry Pi
    if grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
        print_success "Raspberry Pi обнаружен"
    else
        print_warning "Не удалось определить Raspberry Pi, но продолжаем..."
    fi
    
    # Проверяем права пользователя
    if [[ $EUID -eq 0 ]]; then
        print_error "Запуск от root запрещен! Используйте обычного пользователя."
        exit 1
    fi
    
    # Проверяем интернет соединение
    if ping -c 1 google.com >/dev/null 2>&1; then
        print_success "Интернет соединение работает"
    else
        print_error "Нет интернет соединения! Установка невозможна."
        exit 1
    fi
    
    print_success "Система готова к установке"
}

# Интерактивная настройка
interactive_setup() {
    print_step "2" "Интерактивная настройка"
    
    echo -e "${CYAN}Настроим ваш музыкальный центр:${NC}"
    echo
    
    # Автозапуск
    read -p "🚀 Включить автозапуск при загрузке системы? (Y/n): " -n 1 -r
    echo
    ENABLE_AUTOSTART=true
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        ENABLE_AUTOSTART=false
    fi
    
    # Мониторинг
    read -p "🔍 Включить автоматический мониторинг системы? (Y/n): " -n 1 -r  
    echo
    ENABLE_MONITORING=true
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        ENABLE_MONITORING=false
    fi
    
    # Резервные копии
    read -p "💾 Настроить автоматические резервные копии? (Y/n): " -n 1 -r
    echo
    ENABLE_BACKUP=true
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        ENABLE_BACKUP=false
    fi
    
    # Внешний диск
    echo
    print_warning "⚠️  Обнаружение внешнего диска"
    echo "Если у вас есть внешний USB диск для музыки, подключите его сейчас."
    echo "Система попытается его найти и настроить автоматическое монтирование."
    echo
    read -p "Нажмите Enter для продолжения..." 
    
    print_success "Настройка завершена"
}

# Основная установка
run_main_installation() {
    print_step "3" "Основная установка Aether Player"
    
    if [ -f "./install.sh" ]; then
        print_status "Запускаем базовую установку..."
        ./install.sh
    else
        print_error "Файл install.sh не найден!"
        exit 1
    fi
    
    print_success "Базовая установка завершена"
}

# Настройка автозапуска
setup_autostart() {
    if [ "$ENABLE_AUTOSTART" = true ]; then
        print_step "4" "Настройка автозапуска"
        
        if [ -f "./setup-service.sh" ]; then
            print_status "Настраиваем systemd сервис..."
            ./setup-service.sh
        else
            print_error "Файл setup-service.sh не найден!"
            exit 1
        fi
        
        print_success "Автозапуск настроен"
    else
        print_step "4" "Автозапуск пропущен (по выбору пользователя)"
    fi
}

# Настройка мониторинга
setup_monitoring() {
    if [ "$ENABLE_MONITORING" = true ]; then
        print_step "5" "Настройка мониторинга"
        
        if [ -f "./setup-monitoring.sh" ]; then
            print_status "Настраиваем систему мониторинга..."
            ./setup-monitoring.sh
        else
            print_error "Файл setup-monitoring.sh не найден!"
            exit 1
        fi
        
        print_success "Мониторинг настроен"
    else
        print_step "5" "Мониторинг пропущен (по выбору пользователя)"
    fi
}

# Создание первого бэкапа
create_initial_backup() {
    if [ "$ENABLE_BACKUP" = true ]; then
        print_step "6" "Создание первого резервного копия"
        
        if [ -f "./backup.sh" ]; then
            print_status "Создаем начальный бэкап конфигурации..."
            ./backup.sh
        else
            print_error "Файл backup.sh не найден!"
            exit 1
        fi
        
        print_success "Первый бэкап создан"
    else
        print_step "6" "Резервное копирование пропущено (по выбору пользователя)"
    fi
}

# Финальная проверка системы
final_system_check() {
    print_step "7" "Финальная проверка системы"
    
    sleep 3  # Даем время системе стабилизироваться
    
    # Проверяем сервис
    if systemctl is-active --quiet aether-player.service 2>/dev/null; then
        print_success "Сервис Aether Player запущен"
    else
        print_warning "Сервис не запущен (возможно, автозапуск отключен)"
    fi
    
    # Проверяем веб-интерфейс
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    if curl -s --connect-timeout 5 "http://$LOCAL_IP:5000" >/dev/null 2>&1; then
        print_success "Веб-интерфейс доступен"
    else
        if [ "$ENABLE_AUTOSTART" = false ]; then
            print_warning "Веб-интерфейс недоступен (сервис не автозапущен)"
        else
            print_error "Веб-интерфейс недоступен!"
        fi
    fi
    
    # Запускаем диагностику если доступна
    if [ -f "./monitor.sh" ] && [ "$ENABLE_MONITORING" = true ]; then
        print_status "Запускаем диагностику системы..."
        ./monitor.sh --silent
    fi
    
    print_success "Проверка системы завершена"
}

# Создание документации пользователя
create_user_guide() {
    print_step "8" "Создание руководства пользователя"
    
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    
    cat > "/home/$USER/aether-player/РУКОВОДСТВО.txt" << EOF
🎵 AETHER PLAYER - РУКОВОДСТВО ПОЛЬЗОВАТЕЛЯ
===========================================

ДОСТУП К ПЛЕЕРУ:
================
🌐 Веб-интерфейс: http://$LOCAL_IP:5000
📱 QR-код: отсканируйте с любого устройства для быстрого доступа
🔗 Локальная сеть: http://$(hostname).local:5000 (если поддерживается mDNS)

УПРАВЛЕНИЕ:
===========
▶️  ./start.sh          - Запустить плеер вручную
⏹️  ./stop.sh           - Остановить плеер  
🔄 ./restart.sh         - Перезапустить плеер
📊 ./status.sh          - Показать статус и логи

МОНИТОРИНГ:
===========
🔍 ./monitor.sh         - Проверить состояние системы
📈 ./reports.sh         - Просмотр отчетов мониторинга

РЕЗЕРВНЫЕ КОПИИ:
================
💾 ./backup.sh          - Создать резервную копию
📁 ~/aether-player/backups/ - Локальные копии
📁 /mnt/music/aether-backups/ - Копии на внешнем диске (если подключен)

МЕДИА ФАЙЛЫ:
============
📂 ~/aether-player/media/ - Основная папка для музыки
🎵 Поддерживаемые форматы: MP3, WAV, FLAC, M4A, OGG
🖼️ Изображения: JPG, PNG, GIF, BMP

Для загрузки файлов:
- Скопируйте через SSH/SCP
- Используйте веб-интерфейс (кнопка Upload)
- Подключите USB диск к RPi

СИСТЕМНЫЕ КОМАНДЫ:
==================
sudo systemctl status aether-player    - Статус сервиса
sudo systemctl start aether-player     - Запустить
sudo systemctl stop aether-player      - Остановить  
sudo systemctl restart aether-player   - Перезапустить
sudo journalctl -u aether-player -f    - Просмотр логов

УСТРАНЕНИЕ ПРОБЛЕМ:
===================
❓ Нет звука: проверьте подключение динамиков и ./monitor.sh
❓ Не загружается: sudo systemctl restart aether-player
❓ Медленно работает: ./monitor.sh (проверьте температуру и память)
❓ Потерян IP: ./monitor.sh покажет текущий адрес

ОБНОВЛЕНИЕ:
===========
cd ~/aether-player
git pull origin main
./restart.sh

Создано: $(date)
Версия: Aether Player v2.0.0 Production
EOF
    
    print_success "Руководство создано: ~/aether-player/РУКОВОДСТВО.txt"
}

# Финальный отчет
generate_final_report() {
    print_step "9" "Генерация финального отчета"
    
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    
    echo
    echo -e "${PURPLE}=================================================================${NC}"
    echo -e "${GREEN}🎉 УСТАНОВКА AETHER PLAYER ЗАВЕРШЕНА УСПЕШНО! 🎉${NC}"
    echo -e "${PURPLE}=================================================================${NC}"
    echo
    echo -e "${CYAN}📡 ДОСТУП К ПЛЕЕРУ:${NC}"
    echo -e "   🌐 Веб-адрес: ${GREEN}http://$LOCAL_IP:5000${NC}"
    echo -e "   📱 С телефона: откройте браузер → введите адрес выше"
    echo -e "   💻 С компьютера: откройте любой браузер → введите адрес"
    echo
    echo -e "${CYAN}📁 РАСПОЛОЖЕНИЕ ФАЙЛОВ:${NC}"
    echo -e "   🎵 Музыка: ${GREEN}/home/$USER/aether-player/media/${NC}"
    echo -e "   📋 Руководство: ${GREEN}/home/$USER/aether-player/РУКОВОДСТВО.txt${NC}"
    echo -e "   💾 Бэкапы: ${GREEN}/home/$USER/aether-player/backups/${NC}"
    echo
    echo -e "${CYAN}🎛️ УПРАВЛЕНИЕ:${NC}"
    if [ "$ENABLE_AUTOSTART" = true ]; then
        echo -e "   ✅ Автозапуск: ${GREEN}включен${NC} (запустится при включении RPi)"
    else
        echo -e "   ⏸️ Автозапуск: ${YELLOW}отключен${NC} (запускайте вручную: ./start.sh)"
    fi
    
    if [ "$ENABLE_MONITORING" = true ]; then
        echo -e "   ✅ Мониторинг: ${GREEN}включен${NC} (проверка каждые 15 мин)"
    else
        echo -e "   📊 Мониторинг: ${YELLOW}отключен${NC}"
    fi
    
    if [ "$ENABLE_BACKUP" = true ]; then
        echo -e "   ✅ Бэкапы: ${GREEN}настроены${NC} (первый бэкап создан)"
    else
        echo -e "   💾 Бэкапы: ${YELLOW}не настроены${NC}"
    fi
    
    echo
    echo -e "${CYAN}🚀 БЫСТРЫЙ СТАРТ:${NC}"
    echo -e "   1. Скопируйте музыкальные файлы в папку media/"
    echo -e "   2. Откройте браузер на телефоне/компьютере"
    echo -e "   3. Перейдите по адресу: ${GREEN}http://$LOCAL_IP:5000${NC}"
    echo -e "   4. Наслаждайтесь музыкой! 🎵"
    echo
    echo -e "${CYAN}📖 ДОПОЛНИТЕЛЬНО:${NC}"
    echo -e "   📚 Полное руководство: ${GREEN}cat ~/aether-player/РУКОВОДСТВО.txt${NC}"
    echo -e "   🔧 Управление скрипты: ${GREEN}ls ~/aether-player/*.sh${NC}"
    echo -e "   💬 Поддержка: ${GREEN}https://github.com/EvgeniiiV/aether-player${NC}"
    echo
    echo -e "${PURPLE}=================================================================${NC}"
    echo -e "${GREEN}Спасибо за использование Aether Player! 🙏${NC}"
    echo -e "${PURPLE}=================================================================${NC}"
    echo
}

# Главная функция
main() {
    print_header
    
    # Проверяем, что мы в правильной папке
    if [ ! -f "install.sh" ]; then
        print_error "Мастер-установщик должен запускаться из папки с проектом!"
        echo "Сначала клонируйте репозиторий:"
        echo "git clone https://github.com/EvgeniiiV/aether-player.git"
        echo "cd aether-player"
        echo "./setup-complete.sh"
        exit 1
    fi
    
    print_status "Начинаем полную установку домашнего музыкального центра..."
    echo
    
    # Последовательно выполняем все этапы
    check_prerequisites
    interactive_setup
    run_main_installation
    setup_autostart
    setup_monitoring  
    create_initial_backup
    final_system_check
    create_user_guide
    generate_final_report
    
    # Сохраняем отчет
    echo "Установка завершена: $(date)" > "/home/$USER/aether-player/.install-complete"
    echo "IP адрес: $LOCAL_IP" >> "/home/$USER/aether-player/.install-complete"
    echo "Автозапуск: $ENABLE_AUTOSTART" >> "/home/$USER/aether-player/.install-complete"
    echo "Мониторинг: $ENABLE_MONITORING" >> "/home/$USER/aether-player/.install-complete"
    echo "Бэкапы: $ENABLE_BACKUP" >> "/home/$USER/aether-player/.install-complete"
}

# Обработка сигналов для корректного завершения
trap 'print_error "Установка прервана пользователем"; exit 1' INT TERM

# Запускаем мастер-установщик
main "$@"
