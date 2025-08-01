#!/bin/bash

# Скрипт синхронизации проекта с Windows
# Использование: ./sync-to-windows.sh [windows-path]

LINUX_PATH="/home/eu/aether-player"
WINDOWS_USER="your-windows-user"
WINDOWS_HOST="your-windows-ip"
WINDOWS_PATH="${1:-/cygdrive/c/Projects/aether-player}"

echo "🔄 Синхронизация Aether Player: Linux → Windows"
echo "Источник: $LINUX_PATH"
echo "Назначение: $WINDOWS_USER@$WINDOWS_HOST:$WINDOWS_PATH"

# Исключаем файлы, специфичные для Linux
rsync -avz --delete \
    --exclude='__pycache__/' \
    --exclude='*.pyc' \
    --exclude='.git/' \
    --exclude='server.pid' \
    --exclude='aether-player.log' \
    --exclude='aether-player.error.log' \
    "$LINUX_PATH/" \
    "$WINDOWS_USER@$WINDOWS_HOST:$WINDOWS_PATH/"

echo "✅ Синхронизация завершена!"
