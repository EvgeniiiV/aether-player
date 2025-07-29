#!/bin/bash
# Просмотр отчетов мониторинга

# Цвета
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}📊 ОТЧЕТЫ МОНИТОРИНГА AETHER PLAYER${NC}"
echo "======================================"

# Показываем последний ежедневный отчет
if [ -f "/tmp/aether-daily-report.txt" ]; then
    echo -e "${GREEN}📋 Последний ежедневный отчет:${NC}"
    echo "------------------------------"
    cat /tmp/aether-daily-report.txt
    echo
fi

# Показываем список всех отчетов
echo -e "${YELLOW}📁 Доступные отчеты:${NC}"
ls -la /tmp/aether-monitor-*.txt 2>/dev/null | tail -10 || echo "Отчеты не найдены"

echo
echo "Команды:"
echo "  ./monitor.sh          - Запустить проверку сейчас"
echo "  ./monitor.sh --silent - Тихая проверка"
echo "  crontab -l            - Показать расписание"
