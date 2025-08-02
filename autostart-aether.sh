#!/bin/bash
# Автозапуск Aether Player при загрузке системы

cd /home/eu/aether-player

# Ждём готовности сети
sleep 10

# Убиваем старые процессы если есть
pkill -f "python.*app.py" 2>/dev/null

# Активируем виртуальное окружение если оно есть
if [ -d ".venv" ]; then
    source .venv/bin/activate
fi

# Запускаем сервер
echo "$(date): Запуск Aether Player" >> /home/eu/aether-player/autostart.log
python3 app.py >> /home/eu/aether-player/autostart.log 2>&1 &

echo "$(date): Aether Player запущен с PID $!" >> /home/eu/aether-player/autostart.log
