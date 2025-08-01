#!/bin/bash

# Система управления питанием периферии Aether Player (v2.0)
# Управляет реле 220В через GPIO для включения/выключения усилителя, HDD и другой периферии
# Использует современные libgpiod утилиты для Raspberry Pi 4+

# Конфигурация
POWER_GPIO=18          # GPIO пин для управления реле
GPIO_CHIP="gpiochip0"  # GPIO чип (основной на RPi 4)

# Функция проверки состояния GPIO
check_gpio() {
    gpioget $GPIO_CHIP $POWER_GPIO 2>/dev/null
}

# Функция установки GPIO в HIGH (включение реле)
gpio_high() {
    gpioset $GPIO_CHIP $POWER_GPIO=1
}

# Функция установки GPIO в LOW (выключение реле) 
gpio_low() {
    gpioset $GPIO_CHIP $POWER_GPIO=0
}

# Функция включения питания периферии
power_on() {
    echo "⚡ Включение питания периферии..."
    
    # Включаем реле (HIGH)
    gpio_high
    sleep 0.5
    
    # Проверяем состояние
    STATE=$(check_gpio)
    if [ "$STATE" = "1" ]; then
        echo "✅ Питание периферии включено"
        echo "📊 Состояние реле: ВКЛЮЧЕНО (GPIO $POWER_GPIO = HIGH)"
        logger "Aether Player: Питание периферии включено"
    else
        echo "❌ Ошибка: Не удалось включить питание"
        echo "📊 GPIO $POWER_GPIO = $STATE (ожидалось 1)"
        return 1
    fi
}

# Функция выключения питания периферии
power_off() {
    echo "⚠️ Выключение питания периферии..."
    
    # Выключаем реле (LOW)
    gpio_low
    sleep 0.5
    
    # Проверяем состояние
    STATE=$(check_gpio)
    if [ "$STATE" = "0" ]; then
        echo "✅ Питание периферии выключено"
        echo "📊 Состояние реле: ВЫКЛЮЧЕНО (GPIO $POWER_GPIO = LOW)"
        logger "Aether Player: Питание периферии выключено"
    else
        echo "❌ Ошибка: Не удалось выключить питание"
        echo "📊 GPIO $POWER_GPIO = $STATE (ожидалось 0)"
        return 1
    fi
}

# Функция проверки состояния
status() {
    echo "📊 Состояние системы управления питанием:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    STATE=$(check_gpio)
    if [ $? -eq 0 ]; then
        case "$STATE" in
            "1")
                echo "🟢 Реле: ВКЛЮЧЕНО (GPIO $POWER_GPIO = HIGH)"
                echo "⚡ Периферия: ПИТАНИЕ ПОДАНО"
                ;;
            "0")
                echo "🔴 Реле: ВЫКЛЮЧЕНО (GPIO $POWER_GPIO = LOW)"
                echo "🚫 Периферия: ПИТАНИЕ ОТКЛЮЧЕНО"
                ;;
            *)
                echo "❓ Неизвестное состояние: $STATE"
                ;;
        esac
    else
        echo "❌ Ошибка чтения GPIO $POWER_GPIO"
        echo "🔧 Проверьте доступность GPIO или права доступа"
    fi
    
    echo ""
    echo "🔧 Управляемые устройства:"
    echo "  • Усилитель звука"
    echo "  • Внешний HDD"
    echo "  • Дополнительная периферия"
    
    echo ""
    echo "💡 Информация о GPIO:"
    gpioinfo | grep "line.*$POWER_GPIO:" || echo "❌ GPIO $POWER_GPIO недоступен"
}

# Функция безопасного выключения с отмонтированием HDD
safe_power_off() {
    echo "🛡️ Безопасное выключение питания периферии..."
    
    # Останавливаем Aether Player
    echo "🎵 Останавливаем Aether Player..."
    sudo pkill -f "python.*app" 2>/dev/null || true
    sudo pkill -f mpv 2>/dev/null || true
    sleep 2
    
    # Отмонтируем HDD
    echo "💾 Отмонтирование внешних накопителей..."
    
    # Ищем примонтированные USB накопители
    USB_MOUNTS=$(mount | grep "/dev/sd" | awk '{print $1}' | sort -u)
    if [ ! -z "$USB_MOUNTS" ]; then
        for DEVICE in $USB_MOUNTS; do
            echo "📤 Отмонтирование $DEVICE..."
            sudo umount "$DEVICE" 2>/dev/null || true
        done
        
        # Синхронизация файловой системы
        echo "🔄 Синхронизация файловой системы..."
        sync
        sleep 2
    else
        echo "ℹ️ Внешние накопители не обнаружены"
    fi
    
    # Выключаем питание
    power_off
    
    echo "✅ Безопасное выключение завершено"
}

# Функция тестирования реле
test_relay() {
    echo "🧪 Тестирование системы управления питанием..."
    echo ""
    
    echo "1️⃣ Проверка текущего состояния:"
    status
    echo ""
    
    echo "2️⃣ Тест включения:"
    power_on
    sleep 2
    echo ""
    
    echo "3️⃣ Проверка состояния после включения:"
    status
    echo ""
    
    echo "4️⃣ Тест выключения:"
    power_off
    sleep 2
    echo ""
    
    echo "5️⃣ Проверка состояния после выключения:"
    status
    echo ""
    
    echo "✅ Тестирование завершено"
    echo "💡 Проверьте мультиметром реальное состояние контактов реле"
}

# Функция инициализации (для совместимости)
init() {
    echo "🔧 Проверка GPIO системы..."
    echo "📡 Используется современная система libgpiod"
    echo "🎯 GPIO чип: $GPIO_CHIP"
    echo "📌 GPIO пин: $POWER_GPIO"
    
    # Проверяем доступность GPIO
    STATE=$(check_gpio)
    if [ $? -eq 0 ]; then
        echo "✅ GPIO $POWER_GPIO доступен (текущее состояние: $STATE)"
    else
        echo "❌ GPIO $POWER_GPIO недоступен"
        echo "🔧 Убедитесь, что пользователь входит в группу 'gpio'"
        echo "   Выполните: sudo usermod -a -G gpio $USER"
        return 1
    fi
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
    *)
        echo "🔌 Система управления питанием Aether Player v2.0"
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
        echo ""
        echo "Примеры:"
        echo "  $0 on      # Включить питание"
        echo "  $0 status  # Проверить состояние"
        echo "  $0 test    # Протестировать реле"
        echo ""
        exit 1
        ;;
esac
