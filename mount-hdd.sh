#!/bin/bash

# Скрипт для автоматического монтирования HDD при старте системы
# и перезапуска Aether Player

echo "🔧 Монтирование HDD и запуск Aether Player..."

# Проверяем, подключен ли диск
if ! lsblk | grep -q "sda2"; then
    echo "❌ HDD не подключен (sda2 не найден)"
    exit 1
fi

# Создаем точку монтирования
sudo mkdir -p /mnt/hdd

# Проверяем, не смонтирован ли уже диск
if ! mountpoint -q /mnt/hdd; then
    echo "📀 Монтируем HDD..."
    if sudo mount /dev/sda2 /mnt/hdd; then
        echo "✅ HDD успешно смонтирован"
    else
        echo "❌ Ошибка монтирования HDD"
        exit 1
    fi
else
    echo "✅ HDD уже смонтирован"
fi

# Проверяем доступ к папке с музыкой
if [ -d "/mnt/hdd/MUSIC" ]; then
    echo "🎵 Папка MUSIC найдена"
    ls -la /mnt/hdd/MUSIC | head -3
else
    echo "⚠️ Папка MUSIC не найдена, создаем..."
    sudo mkdir -p /mnt/hdd/MUSIC
fi

# Устанавливаем права доступа
sudo chmod 755 /mnt/hdd
sudo chmod -R 755 /mnt/hdd/MUSIC 2>/dev/null || true

echo "✅ HDD готов к работе!"
echo "📁 Доступные папки:"
ls -la /mnt/hdd/ | grep '^d'

echo ""
echo "🌐 Теперь можно открыть http://$(hostname -I | awk '{print $1}'):5000"
