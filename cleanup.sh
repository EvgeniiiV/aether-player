#!/bin/bash
# Экстренная очистка всех ресурсов Aether Player

echo "🚨 ЭКСТРЕННАЯ ОЧИСТКА РЕСУРСОВ AETHER PLAYER"
echo "============================================"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

cleanup_step() {
    echo -e "${YELLOW}$1${NC}"
}

success_step() {
    echo -e "${GREEN}✅ $1${NC}"
}

error_step() {
    echo -e "${RED}❌ $1${NC}"
}

# 1. Останавливаем все связанные процессы
cleanup_step "Остановка всех процессов Aether Player..."
pkill -f "python.*app.py" 2>/dev/null && success_step "Python процессы остановлены" || true
pkill -f gunicorn 2>/dev/null && success_step "Gunicorn процессы остановлены" || true
pkill -f "aether" 2>/dev/null && success_step "Aether процессы остановлены" || true

# 2. Освобождаем порт 5000
cleanup_step "Освобождение порта 5000..."
if command -v fuser >/dev/null 2>&1; then
    sudo fuser -k 5000/tcp 2>/dev/null && success_step "fuser: порт 5000 освобожден" || true
else
    error_step "fuser не найден"
fi

if command -v lsof >/dev/null 2>&1; then
    PIDS=$(sudo lsof -t -i:5000 2>/dev/null || true)
    if [ -n "$PIDS" ]; then
        cleanup_step "Найдены процессы на порту 5000: $PIDS"
        sudo kill -9 $PIDS 2>/dev/null && success_step "lsof: процессы завершены принудительно" || error_step "Не удалось завершить процессы"
    else
        success_step "lsof: порт 5000 свободен"
    fi
else
    error_step "lsof не найден"
fi

# 3. Проверяем освобождение порта
cleanup_step "Проверка доступности порта 5000..."
for i in {1..10}; do
    if ! netstat -ln 2>/dev/null | grep -q ":5000 "; then
        success_step "Порт 5000 полностью освобожден!"
        break
    fi
    echo -e "${YELLOW}⏳ Ожидаем освобождения порта... ($i/10)${NC}"
    sleep 1
done

# 4. Очистка временных файлов
cleanup_step "Очистка временных файлов..."
cd /home/eu/aether-player 2>/dev/null || true
rm -f server.log 2>/dev/null && success_step "server.log удален" || true
rm -f nohup.out 2>/dev/null && success_step "nohup.out удален" || true
rm -f *.pid 2>/dev/null && success_step "PID файлы удалены" || true

# 5. Финальная проверка
cleanup_step "Финальная проверка состояния системы..."
if netstat -ln 2>/dev/null | grep -q ":5000 "; then
    error_step "ВНИМАНИЕ: Порт 5000 все еще занят!"
    echo "Проверьте вручную: sudo lsof -i:5000"
    exit 1
else
    success_step "Система полностью очищена!"
fi

# 6. Показываем статистику
cleanup_step "Текущее состояние портов:"
netstat -ln 2>/dev/null | grep ":50[0-9][0-9]" || echo "Порты 5000-5099 свободны"

echo ""
echo -e "${GREEN}🎉 ОЧИСТКА ЗАВЕРШЕНА УСПЕШНО!${NC}"
echo "Теперь можно безопасно запускать сервер командой: ./start_production.sh"
