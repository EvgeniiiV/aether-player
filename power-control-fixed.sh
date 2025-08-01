#!/bin/bash

# Система управления питанием периферии Aether Player (v4.0)
# Управляет реле 220В через GPIO для включения/выключения усилителя, HDD и другой периферии
# Использует libgpiod с фоновым процессом для удержания состояния

# Конфигурация
POWER_GPIO=21          # GPIO пин для управления реле (изменен с 18 на 21 из-за конфликта PWM)
GPIO_CHIP="gpiochip0"
PIDFILE="/tmp/aether-power-gpio.pid"

# Функция проверки состояния GPIO
check_gpio() {
    timeout 2 gpioget $GPIO_CHIP $POWER_GPIO 2>/dev/null
}

# Функция проверки активного процесса GPIO
is_gpio_active() {
    if [ -f "$PIDFILE" ]; then
        PID=$(cat "$PIDFILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            return 0  # Процесс активен
        else
            # Файл PID существует, но процесс мертв
            rm -f "$PIDFILE"
            return 1
        fi
    fi
    return 1  # Файл PID не существует
}

# Функция остановки GPIO процесса
stop_gpio_process() {
    if [ -f "$PIDFILE" ]; then
        PID=$(cat "$PIDFILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            echo "Останавливаем процесс GPIO (PID: $PID)..."
            kill "$PID" 2>/dev/null
            sleep 0.5
        fi
        rm -f "$PIDFILE"
    fi
}

# Функция включения питания с удержанием состояния
power_on() {
    echo "Включение питания периферии..."
    
    # Останавливаем предыдущий процесс если есть
    stop_gpio_process
    
    # Запускаем фоновый процесс для удержания HIGH
    echo "Запуск фонового процесса GPIO..."
    nohup gpioset --mode=signal $GPIO_CHIP $POWER_GPIO=1 > /dev/null 2>&1 &
    GPIO_PID=$!
    echo "$GPIO_PID" > "$PIDFILE"
    
    sleep 0.5
    
    # Проверяем состояние
    STATE=$(check_gpio)
    if [ "$STATE" = "1" ] && is_gpio_active; then
        echo "УСПЕХ: Питание периферии включено"
        echo "Состояние реле: ВКЛЮЧЕНО (GPIO $POWER_GPIO = HIGH)"
        echo "Фоновый процесс: PID $GPIO_PID"
        logger "Aether Player: Питание периферии включено (PID: $GPIO_PID)"
    else
        echo "ОШИБКА: Не удалось включить питание"
        echo "GPIO $POWER_GPIO = $STATE"
        stop_gpio_process
        return 1
    fi
}

# Функция выключения питания
power_off() {
    echo "Выключение питания периферии..."
    
    # Останавливаем процесс GPIO (это автоматически установит LOW)
    stop_gpio_process
    
    sleep 0.5
    
    # Проверяем состояние
    STATE=$(check_gpio)
    if [ "$STATE" = "0" ]; then
        echo "УСПЕХ: Питание периферии выключено"
        echo "Состояние реле: ВЫКЛЮЧЕНО (GPIO $POWER_GPIO = LOW)"
        logger "Aether Player: Питание периферии выключено"
    else
        echo "ОШИБКА: Не удалось выключить питание"
        echo "GPIO $POWER_GPIO = $STATE (ожидалось 0)"
        return 1
    fi
}

# Функция проверки состояния
status() {
    echo "=== Состояние системы управления питанием ==="
    
    STATE=$(check_gpio)
    GPIO_ACTIVE=$(is_gpio_active && echo "да" || echo "нет")
    
    if [ $? -eq 0 ]; then
        case "$STATE" in
            "1")
                echo "Реле: ВКЛЮЧЕНО (GPIO $POWER_GPIO = HIGH)"
                echo "Периферия: ПИТАНИЕ ПОДАНО"
                if is_gpio_active; then
                    PID=$(cat "$PIDFILE")
                    echo "Фоновый процесс: активен (PID: $PID)"
                else
                    echo "ВНИМАНИЕ: GPIO HIGH, но процесс не активен"
                fi
                ;;
            "0")
                echo "Реле: ВЫКЛЮЧЕНО (GPIO $POWER_GPIO = LOW)"
                echo "Периферия: ПИТАНИЕ ОТКЛЮЧЕНО"
                if is_gpio_active; then
                    echo "ВНИМАНИЕ: Фоновый процесс активен при LOW состоянии"
                fi
                ;;
            *)
                echo "Неизвестное состояние: $STATE"
                ;;
        esac
    else
        echo "ОШИБКА чтения GPIO $POWER_GPIO"
        echo "Проверьте доступность GPIO или права доступа"
    fi
    
    echo ""
    echo "Управляемые устройства:"
    echo "  • Усилитель звука"
    echo "  • Внешний HDD"
    echo "  • Дополнительная периферия"
    
    echo ""
    echo "Техническая информация:"
    echo "  GPIO чип: $GPIO_CHIP"
    echo "  GPIO пин: $POWER_GPIO (физический pin 40)"
    echo "  Процесс активен: $GPIO_ACTIVE"
    
    if [ -f "$PIDFILE" ]; then
        echo "  PID файл: $PIDFILE"
        echo "  Процесс PID: $(cat $PIDFILE)"
    fi
}

# Функция безопасного выключения с отмонтированием HDD
safe_power_off() {
    echo "Безопасное выключение питания периферии..."
    
    # Останавливаем Aether Player
    echo "Останавливаем Aether Player..."
    sudo pkill -f "python.*app" 2>/dev/null || true
    sudo pkill -f mpv 2>/dev/null || true
    sleep 2
    
    # Отмонтируем HDD
    echo "Отмонтирование внешних накопителей..."
    
    # Ищем примонтированные USB накопители
    USB_MOUNTS=$(mount | grep "/dev/sd" | awk '{print $1}' | sort -u)
    if [ ! -z "$USB_MOUNTS" ]; then
        for DEVICE in $USB_MOUNTS; do
            echo "Отмонтирование $DEVICE..."
            sudo umount "$DEVICE" 2>/dev/null || true
        done
        
        # Синхронизация файловой системы
        echo "Синхронизация файловой системы..."
        sync
        sleep 2
    else
        echo "Внешние накопители не обнаружены"
    fi
    
    # Выключаем питание
    power_off
    
    echo "Безопасное выключение завершено"
}

# Функция тестирования реле
test_relay() {
    echo "=== Тестирование системы управления питанием ==="
    echo ""
    
    echo "1. Проверка доступности GPIO:"
    gpioinfo | grep "line.*$POWER_GPIO:" || echo "ОШИБКА: GPIO $POWER_GPIO недоступен"
    echo ""
    
    echo "2. Проверка текущего состояния:"
    status
    echo ""
    
    echo "3. Тест включения:"
    power_on
    sleep 3
    echo ""
    
    echo "4. Проверка состояния после включения:"
    status
    echo ""
    
    echo "5. Тест выключения:"
    power_off
    sleep 2
    echo ""
    
    echo "6. Проверка состояния после выключения:"
    status
    echo ""
    
    echo "Тестирование завершено"
    echo "ВАЖНО: Проверьте мультиметром реальное состояние контактов реле"
    echo "Убедитесь, что реле подключено к GPIO $POWER_GPIO (pin 40)"
}

# Функция инициализации
init() {
    echo "Инициализация GPIO системы..."
    echo "Используется современная система libgpiod"
    echo "GPIO чип: $GPIO_CHIP"
    echo "GPIO пин: $POWER_GPIO (физический pin 40 - ИЗМЕНЕН с pin 12 из-за конфликта)"
    
    # Проверяем доступность GPIO
    STATE=$(check_gpio)
    if [ $? -eq 0 ]; then
        echo "УСПЕХ: GPIO $POWER_GPIO доступен (текущее состояние: $STATE)"
        
        # Останавливаем любые активные процессы
        stop_gpio_process
        
        echo "Установлено начальное состояние: ВЫКЛЮЧЕНО"
        echo ""
        status
    else
        echo "ОШИБКА: GPIO $POWER_GPIO недоступен"
        echo "Убедитесь, что пользователь входит в группу 'gpio'"
        echo "Выполните: sudo usermod -a -G gpio $USER"
        echo "И перезайдите в систему"
        return 1
    fi
}

# Функция очистки (для отладки)
cleanup() {
    echo "Очистка GPIO процессов..."
    stop_gpio_process
    echo "Очистка завершена"
}

# Основная логика
case "$1" in
    "on"|"enable"|"start")
        power_on
        ;;
    "off"|"disable"|"stop")
        power_off
        ;;
    "safe-off"|"safe-stop")
        safe_power_off
        ;;
    "status"|"state"|"check")
        status
        ;;
    "test"|"debug")
        test_relay
        ;;
    "init"|"setup")
        init
        ;;
    "cleanup"|"clean")
        cleanup
        ;;
    *)
        echo "Система управления питанием Aether Player v4.0"
        echo ""
        echo "Использование: $0 {КОМАНДА}"
        echo ""
        echo "Команды:"
        echo "  on, enable, start     - Включить питание периферии"
        echo "  off, disable, stop    - Выключить питание периферии" 
        echo "  safe-off, safe-stop   - Безопасно выключить с отмонтированием HDD"
        echo "  status, state, check  - Показать состояние"
        echo "  test, debug          - Протестировать систему"
        echo "  init, setup          - Проверить инициализацию GPIO"
        echo "  cleanup, clean       - Очистить GPIO процессы"
        echo ""
        echo "Примеры:"
        echo "  $0 init    # Проверить GPIO систему"
        echo "  $0 on      # Включить питание"
        echo "  $0 status  # Проверить состояние"
        echo "  $0 test    # Протестировать реле"
        echo ""
        exit 1
        ;;
esac
