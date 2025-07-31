#!/bin/bash

# Система управления питанием периферии Aether Player
# Управляет реле 220В через GPIO для включения/выключения усилителя, HDD и другой периферии

# Конфигурация
POWER_GPIO=18          # GPIO пин для управления реле (можно изменить)
GPIO_PATH="/sys/class/gpio"
POWER_PIN_PATH="$GPIO_PATH/gpio$POWER_GPIO"

# Функция инициализации GPIO
init_gpio() {
    echo "🔧 Инициализация GPIO пина $POWER_GPIO для управления питанием..."
    
    # Экспортируем GPIO если еще не экспортирован
    if [ ! -d "$POWER_PIN_PATH" ]; then
        echo "$POWER_GPIO" | sudo tee "$GPIO_PATH/export" > /dev/null
        sleep 0.5
    fi
    
    # Устанавливаем направление (выход)
    echo "out" | sudo tee "$POWER_PIN_PATH/direction" > /dev/null
    
    echo "✅ GPIO $POWER_GPIO готов к работе"
}

# Функция включения питания периферии
power_on() {
    echo "⚡ Включение питания периферии..."
    init_gpio
    
    # Включаем реле (HIGH)
    echo "1" | sudo tee "$POWER_PIN_PATH/value" > /dev/null
    
    echo "✅ Питание периферии включено"
    echo "📊 Состояние реле: ВКЛЮЧЕНО (GPIO $POWER_GPIO = HIGH)"
    
    # Логируем событие
    logger "Aether Player: Питание периферии включено"
}

# Функция выключения питания периферии
power_off() {
    echo "⚠️ Выключение питания периферии..."
    
    # Проверяем, инициализирован ли GPIO
    if [ ! -d "$POWER_PIN_PATH" ]; then
        echo "❌ GPIO не инициализирован"
        return 1
    fi
    
    # Выключаем реле (LOW)
    echo "0" | sudo tee "$POWER_PIN_PATH/value" > /dev/null
    
    echo "✅ Питание периферии выключено"
    echo "📊 Состояние реле: ВЫКЛЮЧЕНО (GPIO $POWER_GPIO = LOW)"
    
    # Логируем событие
    logger "Aether Player: Питание периферии выключено"
}

# Функция проверки состояния
status() {
    echo "📊 Состояние системы управления питанием:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ -d "$POWER_PIN_PATH" ]; then
        STATE=$(cat "$POWER_PIN_PATH/value" 2>/dev/null)
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
        echo "❌ GPIO $POWER_GPIO не инициализирован"
    fi
    
    echo ""
    echo "🔧 Управляемые устройства:"
    echo "  • Усилитель звука"
    echo "  • Внешний HDD"
    echo "  • Дополнительная периферия"
}

# Функция безопасного выключения с отмонтированием HDD
safe_power_off() {
    echo "🛡️ Безопасное выключение питания периферии..."
    
    # Останавливаем Aether Player
    echo "🎵 Останавливаем Aether Player..."
    sudo pkill -f "python.*app" 2>/dev/null || true
    sudo pkill -f mpv 2>/dev/null || true
    
    # Отмонтируем HDD
    echo "💾 Отмонтируем HDD..."
    if mountpoint -q /mnt/hdd; then
        sync  # Синхронизируем данные
        sudo umount /mnt/hdd
        if [ $? -eq 0 ]; then
            echo "✅ HDD успешно отмонтирован"
        else
            echo "⚠️ Ошибка отмонтирования HDD"
        fi
    else
        echo "ℹ️ HDD уже отмонтирован"
    fi
    
    # Ждем завершения операций
    echo "⏳ Ожидание завершения операций (3 сек)..."
    sleep 3
    
    # Выключаем питание
    power_off
    
    echo "✅ Безопасное выключение завершено"
}

# Функция тестирования реле
test_relay() {
    echo "🧪 Тестирование реле управления питанием..."
    
    init_gpio
    
    echo "📝 Тест 1: Включение реле на 2 секунды"
    power_on
    sleep 2
    
    echo "📝 Тест 2: Выключение реле на 2 секунды"
    power_off
    sleep 2
    
    echo "📝 Тест 3: Повторное включение"
    power_on
    
    echo "✅ Тестирование завершено"
    echo "🔍 Проверьте работу подключенных устройств"
}

# Основное меню
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
    "status"|"state")
        status
        ;;
    "test")
        test_relay
        ;;
    "init")
        init_gpio
        ;;
    *)
        echo "🔌 Система управления питанием Aether Player"
        echo "════════════════════════════════════════════"
        echo ""
        echo "Использование: $0 [команда]"
        echo ""
        echo "Команды:"
        echo "  on, start, enable    - Включить питание периферии"
        echo "  off, stop, disable   - Выключить питание периферии"
        echo "  safe-off, safe-stop  - Безопасное выключение с отмонтированием HDD"
        echo "  status, state        - Показать состояние системы"
        echo "  test                 - Протестировать работу реле"
        echo "  init                 - Инициализировать GPIO"
        echo ""
        echo "Примеры:"
        echo "  $0 on              # Включить питание"
        echo "  $0 safe-off        # Безопасно выключить"
        echo "  $0 status          # Проверить состояние"
        echo ""
        exit 1
        ;;
esac
