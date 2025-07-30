#!/bin/bash

# Временное тестирование видео без перезагрузки

echo "🎬 Тестирование видео воспроизведения..."

# Остановим старые процессы
sudo pkill -f mpv 2>/dev/null
sudo pkill -f python.*app 2>/dev/null

echo "🔧 Тестируем MPV с разными настройками видео..."

# Найдем тестовый видео файл
TEST_VIDEO=$(find /mnt/hdd -name "*.mp4" -o -name "*.mkv" -o -name "*.avi" | head -1)

if [ -z "$TEST_VIDEO" ]; then
    echo "❌ Видео файлы не найдены в /mnt/hdd"
    exit 1
fi

echo "📹 Найден тестовый файл: $TEST_VIDEO"

# Тест 1: Программное декодирование
echo ""
echo "🧪 Тест 1: Программное декодирование (fbdev)"
timeout 5 mpv "$TEST_VIDEO" \
    --vo=fbdev \
    --hwdec=no \
    --volume=50 \
    --really-quiet \
    --loop=no \
    --no-audio 2>/dev/null &

PID1=$!
sleep 3
kill $PID1 2>/dev/null

# Тест 2: DRM вывод
echo ""
echo "🧪 Тест 2: DRM вывод"
timeout 5 mpv "$TEST_VIDEO" \
    --vo=drm \
    --hwdec=auto-safe \
    --volume=50 \
    --really-quiet \
    --loop=no \
    --no-audio 2>/dev/null &

PID2=$!
sleep 3
kill $PID2 2>/dev/null

# Тест 3: GPU вывод (если доступен)
echo ""
echo "🧪 Тест 3: GPU вывод"
timeout 5 mpv "$TEST_VIDEO" \
    --vo=gpu \
    --hwdec=auto-safe \
    --volume=50 \
    --really-quiet \
    --loop=no \
    --no-audio 2>/dev/null &

PID3=$!
sleep 3
kill $PID3 2>/dev/null

echo ""
echo "✅ Тестирование завершено!"
echo "📋 Рекомендация: Перезагрузите RPi для применения настроек GPU:"
echo "   sudo reboot"
