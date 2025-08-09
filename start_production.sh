#!/bin/bash
# Производственный запуск Aether Player с автоматической очисткой ресурсов

set -e  # Выход при любой ошибке

cd /home/eu/aether-player

# Функция для полной очистки ресурсов
cleanup_resources() {
    echo "🧹 Выполняется полная очистка ресурсов..."
    
    # Останавливаем все связанные процессы
    pkill -f "python.*app.py" 2>/dev/null || true
    pkill -f gunicorn 2>/dev/null || true
    pkill -f "aether" 2>/dev/null || true
    
    # Принудительно освобождаем порт 5000
    if command -v fuser >/dev/null 2>&1; then
        sudo fuser -k 5000/tcp 2>/dev/null || true
    fi
    
    # Дополнительная проверка через lsof
    if command -v lsof >/dev/null 2>&1; then
        PIDS=$(sudo lsof -t -i:5000 2>/dev/null || true)
        if [ -n "$PIDS" ]; then
            echo "🔫 Принудительно завершаем процессы на порту 5000: $PIDS"
            sudo kill -9 $PIDS 2>/dev/null || true
        fi
    fi
    
    # Ждем освобождения порта
    for i in {1..5}; do
        if ! netstat -ln 2>/dev/null | grep -q ":5000 "; then
            break
        fi
        echo "⏳ Ожидаем освобождения порта 5000... ($i/5)"
        sleep 1
    done
    
    echo "✅ Ресурсы освобождены"
}

# Функция обработки сигналов завершения
handle_exit() {
    echo ""
    echo "🛑 Получен сигнал завершения, останавливаем сервер..."
    cleanup_resources
    echo "👋 Aether Player остановлен"
    exit 0
}

# Устанавливаем обработчики сигналов
trap handle_exit SIGINT SIGTERM EXIT

# Проверяем состояние системы
echo "🔍 Проверяем состояние системы..."

# Активируем виртуальную среду
if [ ! -d ".venv" ]; then
    echo "❌ Виртуальная среда не найдена! Запустите: python3 -m venv .venv"
    exit 1
fi

source .venv/bin/activate

# Проверяем зависимости
if ! python -c "import gunicorn, gevent" 2>/dev/null; then
    echo "❌ Отсутствуют зависимости! Установите: pip install gunicorn gevent"
    exit 1
fi

# Выполняем очистку перед запуском
cleanup_resources

# Финальная проверка доступности порта
if netstat -ln 2>/dev/null | grep -q ":5000 "; then
    echo "❌ Порт 5000 все еще занят! Проверьте: sudo lsof -i:5000"
    exit 1
fi

echo "🚀 Запуск Aether Player в продакшен режиме..."
echo "🌐 Сервер будет доступен по адресу: http://localhost:5000"
echo "🛑 Для остановки нажмите Ctrl+C"
echo ""

# Запускаем с Gunicorn и gevent worker
gunicorn \
    --bind 0.0.0.0:5000 \
    --workers 1 \
    --worker-class gevent \
    --worker-connections 1000 \
    --timeout 120 \
    --keep-alive 2 \
    --max-requests 1000 \
    --max-requests-jitter 100 \
    --access-logfile - \
    --error-logfile - \
    app:app
