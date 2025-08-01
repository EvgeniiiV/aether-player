#!/bin/bash

# Система управления питанием периферии Aether Player (v5.0)
# Простое управление GPIO для реле 220В

# Конфигурация
POWER_GPIO=21          # GPIO пин для управления реле
GPIO_CHIP="gpiochip0"
PIDFILE="/tmp/aether-power-gpio.pid"

# Функция проверки состояния GPIO
check_gpio() {
    timeout 1 gpioget $GPIO_CHIP $POWER_GPIO 2>/dev/null
}

# Функция проверки активного процесса
is_gpio_active() {
    if [ -f "$PIDFILE" ]; then
        PID=$(cat "$PIDFILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            return 0
        else
            rm -f "$PIDFILE"
            return 1
        fi
    fi
    return 1
}

# Функция остановки процесса
stop_gpio_process() {
    if [ -f "$PIDFILE" ]; then
        PID=$(cat "$PIDFILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            echo "Останавливаем GPIO процесс (PID: $PID)..."
            kill "$PID" 2>/dev/null
            sleep 0.5
        fi
        rm -f "$PIDFILE"
    fi
}

# Функция включения питания
power_on() {
    echo "=== Включение питания периферии ==="
    
    # Останавливаем предыдущий процесс
    stop_gpio_process
    
    # Простой способ - устанавливаем HIGH в фоне
    echo "Запуск удержания GPIO $POWER_GPIO в HIGH..."
    (
        while true; do
            gpioset $GPIO_CHIP $POWER_GPIO=1 2>/dev/null
            sleep 0.1
        done
    ) &
    
    GPIO_PID=$!
    echo "$GPIO_PID" > "$PIDFILE"
    sleep 1
    
    # Проверяем результат
    STATE=$(check_gpio)
    if [ "$STATE" = "1" ]; then
        echo "УСПЕХ: Питание включено"
        echo "GPIO $POWER_GPIO = HIGH"
        echo "Процесс PID: $GPIO_PID"
        logger "Aether Player: Питание включено (GPIO $POWER_GPIO, PID: $GPIO_PID)"
    else
        echo "ОШИБКА: GPIO $POWER_GPIO = $STATE"
        stop_gpio_process
        return 1
    fi
}

# Функция выключения питания
power_off() {
    echo "=== Выключение питания периферии ==="
    
    # Останавливаем процесс удержания
    stop_gpio_process
    
    # Явно устанавливаем LOW
    gpioset $GPIO_CHIP $POWER_GPIO=0 2>/dev/null
    sleep 0.5
    
    STATE=$(check_gpio)
    if [ "$STATE" = "0" ]; then
        echo "УСПЕХ: Питание выключено"
        echo "GPIO $POWER_GPIO = LOW"
        logger "Aether Player: Питание выключено (GPIO $POWER_GPIO)"
    else
        echo "ОШИБКА: GPIO $POWER_GPIO = $STATE"
        return 1
    fi
}

# Функция проверки состояния
status() {
    echo "=== Состояние системы ==="
    
    STATE=$(check_gpio)
    PROCESS_ACTIVE=$(is_gpio_active && echo "ДА" || echo "НЕТ")
    
    case "$STATE" in
        "1")
            echo "Реле: ВКЛЮЧЕНО (GPIO $POWER_GPIO = HIGH)"
            echo "Статус: ПИТАНИЕ ПОДАНО"
            ;;
        "0")
            echo "Реле: ВЫКЛЮЧЕНО (GPIO $POWER_GPIO = LOW)"
            echo "Статус: ПИТАНИЕ ОТКЛЮЧЕНО"
            ;;
        *)
            echo "Реле: НЕИЗВЕСТНО (GPIO $POWER_GPIO = '$STATE')"
            ;;
    esac
    
    echo "Процесс активен: $PROCESS_ACTIVE"
    
    if [ -f "$PIDFILE" ]; then
        echo "PID файл: $(cat $PIDFILE)"
    fi
    
    echo ""
    echo "Управляемые устройства:"
    echo "• Усилитель звука"
    echo "• Внешний HDD" 
    echo "• Дополнительная периферия"
    
    echo ""
    echo "GPIO информация:"
    echo "• Чип: $GPIO_CHIP"
    echo "• Пин: GPIO $POWER_GPIO (физический pin 40)"
    echo "• Примечание: Изменен с GPIO 18 из-за конфликта PWM"
}

# Функция безопасного выключения
safe_power_off() {
    echo "=== Безопасное выключение ==="
    
    echo "Останавливаем Aether Player..."
    sudo pkill -f "python.*app" 2>/dev/null || true
    sudo pkill -f mpv 2>/dev/null || true
    sleep 2
    
    echo "Отмонтирование USB накопителей..."
    USB_MOUNTS=$(mount | grep "/dev/sd" | awk '{print $1}' | sort -u)
    if [ ! -z "$USB_MOUNTS" ]; then
        for DEVICE in $USB_MOUNTS; do
            echo "Отмонтирование $DEVICE..."
            sudo umount "$DEVICE" 2>/dev/null || true
        done
        sync
        sleep 2
        echo "USB накопители отмонтированы"
    else
        echo "USB накопители не найдены"
    fi
    
    power_off
    echo "Безопасное выключение завершено"
}

# Функция тестирования
test_relay() {
    echo "=== ТЕСТ РЕЛЕ ==="
    echo ""
    
    echo "1. Проверка GPIO доступности:"
    if check_gpio >/dev/null 2>&1; then
        echo "GPIO $POWER_GPIO доступен"
    else
        echo "ОШИБКА: GPIO $POWER_GPIO недоступен"
        return 1
    fi
    echo ""
    
    echo "2. Текущее состояние:"
    status
    echo ""
    
    echo "3. Тест включения (5 сек):"
    power_on
    sleep 5
    echo ""
    
    echo "4. Состояние после включения:"
    status
    echo ""
    
    echo "5. Тест выключения:"
    power_off
    sleep 2
    echo ""
    
    echo "6. Финальное состояние:"
    status
    echo ""
    
    echo "=== ТЕСТ ЗАВЕРШЕН ==="
    echo "ПРОВЕРЬТЕ мультиметром реальное состояние реле!"
    echo "Реле должно быть подключено к GPIO $POWER_GPIO (pin 40)"
}

# Функция очистки
cleanup() {
    echo "Очистка процессов..."
    stop_gpio_process
    gpioset $GPIO_CHIP $POWER_GPIO=0 2>/dev/null || true
    echo "Очистка завершена"
}

# Основная логика
case "$1" in
    "on"|"start"|"enable")
        power_on
        ;;
    "off"|"stop"|"disable")
        power_off
        ;;
    "safe-off"|"safe-stop")
        safe_power_off
        ;;
    "status"|"check"|"state")
        status
        ;;
    "test"|"debug")
        test_relay
        ;;
    "cleanup"|"clean")
        cleanup
        ;;
    *)
        echo "Система управления питанием Aether Player v5.0"
        echo ""
        echo "ВАЖНО: GPIO изменен с 18 на 21 (pin 40) из-за конфликта PWM"
        echo ""
        echo "Команды:"
        echo "  on, start    - Включить питание"
        echo "  off, stop    - Выключить питание"
        echo "  safe-off     - Безопасно выключить с отмонтированием"
        echo "  status       - Показать состояние"
        echo "  test         - Протестировать реле"
        echo "  cleanup      - Очистить процессы"
        echo ""
        echo "Примеры:"
        echo "  $0 on       # Включить"
        echo "  $0 status   # Проверить"
        echo "  $0 test     # Тестировать"
        echo ""
        echo "Подключение реле:"
        echo "  RPi Pin 40 (GPIO 21) → Оптопара → Реле → 220В"
        echo ""
        ;;
esac
