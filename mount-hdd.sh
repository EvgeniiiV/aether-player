#!/bin/bash

# Скрипт для автоматического монтирования HDD при старте системы
# и перезапуска Aether Player
# UPDATED: 2025-08-06 v2 - Graceful startup без HDD

echo "🔧 Монтирование HDD и запуск Aether Player..."

# Ждем, пока диск станет доступен (важно после включения питания!)
echo "⏳ Ожидание готовности диска..."
for i in {1..30}; do
    if lsblk | grep -q "sda2"; then
        echo "✅ Диск sda2 обнаружен через $i секунд"
        break
    fi
    echo "   Попытка $i/30: диск не готов, ждем..."
    sleep 2
done

# Проверяем, подключен ли диск
if ! lsblk | grep -q "sda2"; then
    echo "⚠️  HDD не подключен (sda2 не найден даже после ожидания)"
    echo "🔍 Доступные диски:"
    lsblk
    echo ""
    echo "🌐 Aether Player запустится в режиме 'HDD не подключен'"
    echo "   Пользователь увидит предупреждение в веб-интерфейсе"
    
    # Создаем файл-флаг для приложения
    echo "HDD_NOT_CONNECTED" > /tmp/aether-hdd-status.txt
    echo "$(date)" >> /tmp/aether-hdd-status.txt
    
    # Не завершаемся с ошибкой - позволяем приложению стартовать!
    exit 0
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

# Создаем файл-флаг об успешном монтировании
echo "HDD_CONNECTED" > /tmp/aether-hdd-status.txt
echo "$(date)" >> /tmp/aether-hdd-status.txt
echo "/mnt/hdd" >> /tmp/aether-hdd-status.txt

echo "✅ HDD готов к работе!"
echo "📁 Доступные папки:"
ls -la /mnt/hdd/ | grep '^d'

echo ""
echo "🌐 Теперь можно открыть http://$(hostname -I | awk '{print $1}'):5000"
