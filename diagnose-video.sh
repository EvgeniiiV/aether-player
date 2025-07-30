#!/bin/bash

# Диагностика видео системы Raspberry Pi

echo "🎥 Диагностика видео системы Raspberry Pi..."
echo "============================================="

# Проверяем GPU память
echo "📊 GPU память:"
vcgencmd get_mem gpu

# Проверяем статус дисплея
echo ""
echo "🖥️ Информация о дисплее:"
tvservice -s
tvservice -m CEA
tvservice -m DMT

# Проверяем поддержку аппаратного декодирования
echo ""
echo "🔧 Поддержка кодеков:"
vcgencmd get_config gpu_mem
vcgencmd get_config decode_MPG2
vcgencmd get_config decode_WVC1

# Проверяем видео устройства
echo ""
echo "📹 Видео устройства:"
ls -la /dev/video* 2>/dev/null || echo "Видео устройства не найдены"

# Проверяем DRM устройства
echo ""
echo "🎮 DRM устройства:"
ls -la /dev/dri/* 2>/dev/null || echo "DRM устройства не найдены"

# Проверяем framebuffer
echo ""
echo "🖼️ Framebuffer:"
ls -la /dev/fb* 2>/dev/null || echo "Framebuffer не найден"

# Тестируем MPV с видео
echo ""
echo "🎬 Тест MPV (должен показать информацию о кодеках):"
timeout 5 mpv --vo=help 2>/dev/null | head -10 || echo "MPV не установлен или не отвечает"

echo ""
echo "🔍 Рекомендации:"
echo "1. Убедитесь, что gpu_mem >= 128M в /boot/config.txt"
echo "2. Для лучшей производительности видео добавьте в /boot/config.txt:"
echo "   gpu_mem=128"
echo "   dtoverlay=vc4-kms-v3d"
echo "3. Перезагрузите RPi после изменений"

# Проверяем текущие настройки в config.txt
echo ""
echo "⚙️ Текущие настройки видео в /boot/config.txt:"
grep -E "(gpu_mem|dtoverlay|hdmi_)" /boot/config.txt 2>/dev/null || echo "Настройки не найдены"

echo ""
echo "✅ Диагностика завершена!"
