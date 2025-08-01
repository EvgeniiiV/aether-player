#!/bin/bash

# Тестовая версия управления GPIO через sysfs
POWER_GPIO=21
SYSFS_GPIO_PATH="/sys/class/gpio/gpio$POWER_GPIO"

# Функция экспорта GPIO
export_gpio() {
    if [ ! -d "$SYSFS_GPIO_PATH" ]; then
        echo "Экспорт GPIO $POWER_GPIO..."
        echo "$POWER_GPIO" | sudo tee /sys/class/gpio/export > /dev/null 2>&1
        sleep 0.5
    fi
    
    if [ -d "$SYSFS_GPIO_PATH" ]; then
        echo "Настройка как выход..."
        echo "out" | sudo tee "$SYSFS_GPIO_PATH/direction" > /dev/null 2>&1
        return 0
    else
        return 1
    fi
}

# Функция установки GPIO
set_gpio() {
    local value=$1
    if [ -f "$SYSFS_GPIO_PATH/value" ]; then
        echo "$value" | sudo tee "$SYSFS_GPIO_PATH/value" > /dev/null 2>&1
        echo "GPIO $POWER_GPIO установлен в $value"
        return 0
    else
        echo "ОШИБКА: файл $SYSFS_GPIO_PATH/value не найден"
        return 1
    fi
}

# Функция чтения GPIO
get_gpio() {
    if [ -f "$SYSFS_GPIO_PATH/value" ]; then
        local state=$(cat "$SYSFS_GPIO_PATH/value" 2>/dev/null)
        echo "Текущее состояние GPIO $POWER_GPIO: $state"
        return 0
    else
        echo "ОШИБКА: не удается прочитать GPIO $POWER_GPIO"
        return 1
    fi
}

# Тест
case "$1" in
    "init")
        echo "=== Инициализация GPIO ==="
        export_gpio
        ;;
    "on")
        echo "=== Включение GPIO ==="
        export_gpio && set_gpio 1 && get_gpio
        ;;
    "off")
        echo "=== Выключение GPIO ==="
        set_gpio 0 && get_gpio
        ;;
    "status")
        echo "=== Статус GPIO ==="
        get_gpio
        ;;
    "test")
        echo "=== Полный тест ==="
        export_gpio
        echo "Включение..."
        set_gpio 1 && get_gpio
        sleep 2
        echo "Выключение..."
        set_gpio 0 && get_gpio
        ;;
    *)
        echo "Использование: $0 {init|on|off|status|test}"
        ;;
esac
