#!/bin/bash

# Система управления питанием периферии Aether Player (v3.0)
# Управляет реле 220В через GPIO для включения/выключения усилителя, HDD и другой периферии
# Использует sysfs для постоянного удержания состояния GPIO

# Конфигурация
POWER_GPIO=18
GPIO_PATH="/sys/class/gpio"
POWER_PIN_PATH="$GPIO_PATH/gpio$POWER_GPIO"

# Функция экспорта и инициализации GPIO
init_gpio() {
    # Экспортируем GPIO если еще не экспортирован
    if [ ! -d "$POWER_PIN_PATH" ]; then
        echo "🔧 Экспорт GPIO $POWER_GPIO..."
        echo "$POWER_GPIO" | sudo tee "$GPIO_PATH/export" > /dev/null
        sleep 0.5
    fi
    
    # Устанавливаем направление (выход)
    if [ -f "$POWER_PIN_PATH/direction" ]; then
        echo "📤 Настройка GPIO $POWER_GPIO как выход..."
        echo "out" | sudo tee "$POWER_PIN_PATH/direction" > /dev/null
    else
        echo "❌ Не удалось настроить направление GPIO"
        return 1
    fi
}

# Функция проверки состояния GPIO
check_gpio() {
    if [ -f "$POWER_PIN_PATH/value" ]; then
        cat "$POWER_PIN_PATH/value" 2>/dev/null
    else
        echo "❌ GPIO не инициализирован"
        return 1
    fi
}

# Функция установки GPIO в HIGH (включение реле)
gpio_high() {
    init_gpio
    echo "1" | sudo tee "$POWER_PIN_PATH/value" > /dev/null
}

# Функция установки GPIO в LOW (выключение реле) 
gpio_low() {
    if [ -f "$POWER_PIN_PATH/value" ]; then
        echo "0" | sudo tee "$POWER_PIN_PATH/value" > /dev/null
    fi
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
    
    if [ -d "$POWER_PIN_PATH" ]; then
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
        fi
    else
        echo "❌ GPIO $POWER_GPIO не инициализирован"
        echo "💡 Выполните: $0 init"
    fi
    
    echo ""
    echo "🔧 Управляемые устройства:"
    echo "  • Усилитель звука"
    echo "  • Внешний HDD"
    echo "  • Дополнительная периферия"
    
    echo ""
    echo "💡 Техническая информация:"
    echo "  📂 GPIO путь: $POWER_PIN_PATH"
    echo "  🔌 GPIO пин: $POWER_GPIO (физический pin 12)"
    
    if [ -d "$POWER_PIN_PATH" ]; then
        echo "  📤 Направление: $(cat $POWER_PIN_PATH/direction 2>/dev/null || echo 'не установлено')"
        echo "  📊 Значение: $(cat $POWER_PIN_PATH/value 2>/dev/null || echo 'не доступно')"
    fi
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
    
    echo "1️⃣ Инициализация GPIO:"
    init_gpio
    echo ""
    
    echo "2️⃣ Проверка текущего состояния:"
    status
    echo ""
    
    echo "3️⃣ Тест включения:"
    power_on
    sleep 2
    echo ""
    
    echo "4️⃣ Проверка состояния после включения:"
    STATE=$(check_gpio)
    echo "📊 GPIO $POWER_GPIO = $STATE"
    echo ""
    
    echo "5️⃣ Тест выключения:"
    power_off
    sleep 2
    echo ""
    
    echo "6️⃣ Проверка состояния после выключения:"
    STATE=$(check_gpio)
    echo "📊 GPIO $POWER_GPIO = $STATE"
    echo ""
    
    echo "✅ Тестирование завершено"
    echo "💡 Проверьте мультиметром реальное состояние контактов реле"
}

# Функция инициализации
init() {
    echo "🔧 Инициализация GPIO системы..."
    echo "📌 GPIO пин: $POWER_GPIO (физический pin 12)"
    echo "📂 Системный путь: $POWER_PIN_PATH"
    
    # Инициализируем GPIO
    init_gpio
    
    if [ $? -eq 0 ]; then
        echo "✅ GPIO $POWER_GPIO успешно инициализирован"
        
        # Устанавливаем начальное состояние (выключено)
        gpio_low
        
        echo "🔴 Установлено начальное состояние: ВЫКЛЮЧЕНО"
        echo ""
        status
    else
        echo "❌ Ошибка инициализации GPIO $POWER_GPIO"
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
        echo "🔌 Система управления питанием Aether Player v3.0"
        echo ""
        echo "Использование: $0 {КОМАНДА}"
        echo ""
        echo "Команды:"
        echo "  on, enable, start     - Включить питание периферии"
        echo "  off, disable, stop    - Выключить питание периферии" 
        echo "  safe-off, safe-stop   - Безопасно выключить с отмонтированием HDD"
        echo "  status, state, check  - Показать состояние"
        echo "  test, debug          - Протестировать систему"
        echo "  init, setup          - Инициализировать GPIO"
        echo ""
        echo "Примеры:"
        echo "  $0 init    # Инициализировать GPIO (выполнить первым)"
        echo "  $0 on      # Включить питание"
        echo "  $0 status  # Проверить состояние"
        echo "  $0 test    # Протестировать реле"
        echo ""
        exit 1
        ;;
esac
