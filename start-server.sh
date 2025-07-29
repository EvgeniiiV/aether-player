#!/bin/bash

# Скрипт для запуска Aether Player сервера
# Использовать после включения Raspberry Pi

echo "🚀 Запуск Aether Player сервера..."

# Переходим в директорию проекта
cd "$(dirname "$0")"

# Проверяем и монтируем HDD
echo "🔧 Проверяем HDD..."
if [ -f "./mount-hdd.sh" ]; then
    ./mount-hdd.sh
else
    echo "⚠️ Скрипт mount-hdd.sh не найден, монтируем вручную..."
    sudo mkdir -p /mnt/hdd
    sudo mount /dev/sda2 /mnt/hdd 2>/dev/null || echo "HDD уже смонтирован или недоступен"
fi

# Останавливаем старые процессы
echo "🛑 Останавливаем старые процессы..."
sudo pkill -f "python.*app" 2>/dev/null || true

# Ждем завершения процессов
sleep 2

# Проверяем, свободен ли порт 5000
if netstat -tln | grep -q ":5000 "; then
    echo "⚠️ Порт 5000 занят, пытаемся освободить..."
    sudo fuser -k 5000/tcp 2>/dev/null || true
    sleep 2
fi

# Запускаем сервер
echo "🌐 Запускаем Flask сервер..."
python3 -c "
import sys
sys.path.insert(0, '.')
from app import app
print('🎵 Aether Player запущен!')
print('🌐 Доступен по адресу: http://{}:5000'.format('$(hostname -I | awk \"{print \$1}\")'))
print('🎛️ Мониторинг: http://{}:5000/monitor'.format('$(hostname -I | awk \"{print \$1}\")'))
app.run(host='0.0.0.0', port=5000, debug=False)
" > server.log 2>&1 &

# Сохраняем PID процесса
SERVER_PID=$!
echo $SERVER_PID > server.pid

# Ждем запуска
sleep 3

# Проверяем, запустился ли сервер
if ps -p $SERVER_PID > /dev/null; then
    echo "✅ Сервер успешно запущен (PID: $SERVER_PID)"
    echo "🌐 Адрес: http://$(hostname -I | awk '{print $1}'):5000"
    echo "🎛️ Мониторинг: http://$(hostname -I | awk '{print $1}'):5000/monitor"
    echo ""
    echo "📋 Управление сервером:"
    echo "  - Остановить: kill $SERVER_PID"
    echo "  - Логи: tail -f server.log"
    echo "  - Статус: ps -p $SERVER_PID"
else
    echo "❌ Ошибка запуска сервера!"
    echo "📋 Проверьте логи: tail server.log"
    exit 1
fi
