#!/bin/bash
# Настройка sudo прав для безопасного отключения системы

set -e

USER=$(whoami)

echo "🔧 Настройка sudo прав для безопасного отключения..."

# Создаем файл sudoers для Aether Player
sudo tee /etc/sudoers.d/aether-player > /dev/null << EOF
# Aether Player - права для безопасного управления системой
$USER ALL=(ALL) NOPASSWD: /sbin/shutdown
$USER ALL=(ALL) NOPASSWD: /bin/umount /mnt/hdd
$USER ALL=(ALL) NOPASSWD: /bin/sync
$USER ALL=(ALL) NOPASSWD: /usr/bin/alsactl restore
$USER ALL=(ALL) NOPASSWD: /usr/bin/killall fbi
$USER ALL=(ALL) NOPASSWD: /usr/bin/killall mpv
EOF

# Проверяем синтаксис sudoers
if sudo visudo -c -f /etc/sudoers.d/aether-player; then
    echo "✅ Права sudo настроены успешно!"
    echo ""
    echo "Теперь доступны команды:"
    echo "  🔄 Перезагрузка через веб-интерфейс"
    echo "  ⚡ Выключение через веб-интерфейс"  
    echo "  💾 Безопасное отключение HDD"
    echo "  ❌ Отмена запланированного отключения"
else
    echo "❌ Ошибка в конфигурации sudoers!"
    sudo rm -f /etc/sudoers.d/aether-player
    exit 1
fi
