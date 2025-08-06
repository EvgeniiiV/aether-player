#!/bin/bash

# Скрипт корректного завершения работы Aether Player
# UPDATED: 2025-08-06 v1

set -e

echo "🔄 Корректное завершение работы Aether Player..."

# 1. Остановка процессов MPV
echo "⏹️  Останавливаем MPV процессы..."
sudo pkill -f mpv || true

# 2. Остановка Flask приложения  
echo "⏹️  Останавливаем Flask приложение..."
sudo pkill -f "python.*app" || true

# 3. Ожидание завершения процессов
echo "⏳ Ожидание завершения процессов..."
sleep 3

# 4. Синхронизация файловой системы
echo "💾 Синхронизация файловой системы..."
sync

# 5. Отмонтирование HDD если примонтирован
if mount | grep -q "/mnt/hdd"; then
    echo "💿 Отмонтирование HDD..."
    sudo umount /mnt/hdd || {
        echo "⚠️  Принудительное отмонтирование..."
        sudo umount -f /mnt/hdd || true
    }
    echo "✅ HDD отмонтирован"
else
    echo "ℹ️  HDD уже отмонтирован"
fi

# 6. Финальная синхронизация
sync
sleep 1

echo "✅ Aether Player корректно завершён"
