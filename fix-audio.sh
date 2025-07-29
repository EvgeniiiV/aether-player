#!/bin/bash

# Скрипт для диагностики и настройки звука на Raspberry Pi
# Для Aether Player

echo "🔊 Диагностика звуковой системы Raspberry Pi..."
echo "================================================"

# Проверяем доступные звуковые устройства
echo "📋 Доступные звуковые карты:"
cat /proc/asound/cards
echo

echo "🎧 Детальная информация об устройствах:"
aplay -l
echo

# Проверяем уровни громкости
echo "🔊 Текущие уровни громкости:"
amixer get Master 2>/dev/null || echo "Master контрол недоступен"
echo

# Проверяем PulseAudio
echo "🎵 Статус PulseAudio:"
if command -v pulseaudio >/dev/null 2>&1; then
    if pgrep -x pulseaudio > /dev/null; then
        echo "✅ PulseAudio запущен"
        pactl list short sinks 2>/dev/null || echo "⚠️ Не удалось получить список устройств PulseAudio"
    else
        echo "❌ PulseAudio не запущен"
    fi
else
    echo "❌ PulseAudio не установлен"
fi
echo

# Тестируем звук на разных устройствах
echo "🧪 Тестирование звука на различных устройствах..."
echo "⏱️ Каждый тест длится 2 секунды"
echo

# Тест с помощью speaker-test
for card in 0 1 2 3; do
    if [ -e "/proc/asound/card$card" ]; then
        card_name=$(cat /proc/asound/card$card/id 2>/dev/null)
        echo "🔊 Тестируем карту $card ($card_name)..."
        timeout 2s speaker-test -c 2 -r 48000 -D hw:$card -t wav >/dev/null 2>&1 &
        sleep 2.5
        echo "   Завершено"
    fi
done

echo
echo "🎯 Рекомендации:"
echo "=================="

# Проверяем наличие Scarlett
if grep -q "Scarlett" /proc/asound/cards; then
    echo "✅ Обнаружена Focusrite Scarlett 2i2 USB"
    echo "   Рекомендуется использовать её как основное устройство"
    echo "   Команда для MPV: --audio-device=alsa/hw:1,0"
    scarlett_card=1
elif grep -q "USB" /proc/asound/cards; then
    echo "✅ Обнаружено USB аудио устройство"
    usb_card=$(grep -n "USB" /proc/asound/cards | cut -d: -f1 | head -1)
    echo "   Рекомендуется использовать карту $usb_card"
    echo "   Команда для MPV: --audio-device=alsa/hw:$usb_card,0"
    scarlett_card=$usb_card
else
    echo "📢 USB аудио не найдено, используем встроенное"
    echo "   3.5mm разъем: --audio-device=alsa/hw:0,0"
    echo "   HDMI: --audio-device=alsa/hw:2,0 или --audio-device=alsa/hw:3,0"
    scarlett_card=0
fi

echo
echo "🔧 Команды для настройки:"
echo "========================"
echo "# Установить Scarlett как устройство по умолчанию:"
echo "echo 'defaults.pcm.card $scarlett_card' | sudo tee /etc/asound.conf"
echo
echo "# Тест звука вручную:"
echo "speaker-test -c 2 -r 48000 -D hw:$scarlett_card,0 -t wav"
echo
echo "# Тест с MPV:"
echo "mpv --audio-device=alsa/hw:$scarlett_card,0 /usr/share/sounds/alsa/Noise.wav"
echo

# Предлагаем автоматическое исправление
echo "🚀 Хотите автоматически настроить Scarlett как устройство по умолчанию? (y/n)"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    echo "🔧 Настраиваем звуковую систему..."
    
    # Создаем конфигурацию ALSA
    echo "defaults.pcm.card $scarlett_card" | sudo tee /etc/asound.conf
    echo "defaults.ctl.card $scarlett_card" | sudo tee -a /etc/asound.conf
    
    # Перезапускаем звуковую систему
    sudo systemctl restart alsa-state 2>/dev/null || true
    
    echo "✅ Настройка завершена!"
    echo "🔄 Перезапустите Aether Player для применения изменений"
fi

echo
echo "📞 Если звука всё ещё нет:"
echo "========================="
echo "1. Проверьте подключение к Scarlett 2i2"
echo "2. Убедитесь, что выходы подключены к колонкам/наушникам"
echo "3. Проверьте, что Scarlett включена и индикаторы горят"
echo "4. Попробуйте другие выходы (3.5mm, HDMI)"
echo "5. Перезагрузите Raspberry Pi"
