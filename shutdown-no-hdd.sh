#!/bin/bash

# Скрипт безопасного выключения RPi без HDD и Scarlett

echo "🛡️ Безопасное выключение Raspberry Pi (без HDD)..."

# Останавливаем Aether Player если запущен
echo "🛑 Останавливаем сервисы..."
sudo systemctl stop aether-player 2>/dev/null || echo "Сервис aether-player не найден"
sudo pkill -f "python.*app" 2>/dev/null || echo "Python процессы не найдены"
sudo killall mpv 2>/dev/null || echo "MPV процессы не найдены"

# Синхронизируем файловую систему
echo "💾 Синхронизируем данные..."
sync

# Завершаем активные процессы записи
echo "📝 Завершаем процессы записи..."
sudo fuser -km /var/log/ 2>/dev/null || true

# Финальная синхронизация
sync

echo "✅ Система готова к отключению!"
echo "⚡ Выключаем через 5 секунд..."

# Отключение через 5 секунд
sudo shutdown -h +0.1

echo "🔌 Можно отключать питание через 10 секунд после исчезновения активности LED"
