# 🎛️ CamillaDSP Setup для Aether Player

## 📋 Обзор

CamillaDSP установлен и настроен для работы с Focusrite Scarlett 4i4 USB.
Система поддерживает два режима работы:

1. **Full-Range Stereo** - для текущих широкополосных динамиков (стерео, каналы 1-2)
2. **Altec 601B Bi-Amping** - для будущей системы с кроссовером 3000 Hz (4 канала)

## 🌐 Веб-интерфейс CamillaDSP GUI

**URL:** `http://aether-player.local:5050/gui/index.html`  
или просто: `http://aether-player.local:5050/`

CamillaDSP GUI предоставляет графический интерфейс для:
- Редактирования конфигураций в реальном времени
- Визуализации частотных характеристик фильтров
- Управления громкостью
- Мониторинга уровней сигнала
- Создания и тестирования фильтров эквализации
- Измерения и коррекции АЧХ комнаты

## 🔄 Переключение между конфигурациями

### Команда переключения
```bash
camilladsp-switch [MODE]
```

### Доступные режимы

#### 1. Full-Range (текущая система)
```bash
camilladsp-switch fullrange
```
- **Назначение**: Широкополосные динамики без кроссовера
- **Выходы**: 
  - Каналы 1-2: Стерео L/R
  - Каналы 3-4: Не используются
- **Обработка**: Прямое прохождение сигнала без фильтрации

#### 2. Bi-Amping Altec 601B (будущая система)
```bash
camilladsp-switch biamp
```
- **Назначение**: Двухполосная система Altec 601B
- **Кроссовер**: 3000 Hz, Linkwitz-Riley 4th order (24 dB/oct)
- **Выходы**:
  - Каналы 1-2: НЧ L/R (Low Frequency до 3000 Hz)
  - Каналы 3-4: ВЧ L/R (High Frequency от 3000 Hz)
- **Тип**: Би-ампинг с активным кроссовером

### Проверка текущего статуса
```bash
camilladsp-switch status
# или просто
camilladsp-switch
```

## 📁 Расположение файлов

### Конфигурации
- **Full-Range**: `/etc/camilladsp/configs/fullrange-stereo.yml`
- **Bi-Amping**: `/etc/camilladsp/configs/altec601b-biamp-3000hz.yml`
- **Активная** (симлинк): `/etc/camilladsp/active-config.yml`
- **State file**: `/var/lib/camilladsp/statefile.yml` (сохраняет текущее состояние)

### Системные файлы
- **Бинарник**: `/usr/local/bin/camilladsp`
- **Скрипт переключения**: `/usr/local/bin/camilladsp-switch`
- **Systemd сервис**: `/etc/systemd/system/camilladsp.service`
- **ALSA конфиг**: `~/.asoundrc`
- **CamillaDSP GUI**: `/opt/camillagui-server/`
- **GUI конфигурация**: `/opt/camillagui-server/config/camillagui.yml`

## 🎵 Цепочка обработки звука

```
Aether Player (Python/pygame)
    ↓
ALSA default device
    ↓
ALSA Loopback (hw:Loopback,0,0)
    ↓
CamillaDSP (читает с hw:Loopback,1,0)
    ↓
Фильтры + Кроссовер (если активен)
    ↓
Scarlett 4i4 USB (hw:USB,0)
    ↓
Усилители → Динамики
```

## 🔧 Управление сервисом

### Базовые команды
```bash
# Статус сервиса
sudo systemctl status camilladsp

# Остановка
sudo systemctl stop camilladsp

# Запуск
sudo systemctl start camilladsp

# Перезапуск
sudo systemctl restart camilladsp

# Просмотр логов
sudo journalctl -u camilladsp -f
```

### Автозагрузка
CamillaDSP настроен на автоматический запуск при загрузке системы.

```bash
# Отключить автозагрузку
sudo systemctl disable camilladsp

# Включить автозагрузку
sudo systemctl enable camilladsp
```

## 🎚️ Настройка конфигураций

### Редактирование Full-Range
```bash
sudo nano /etc/camilladsp/configs/fullrange-stereo.yml
```

**Пример добавления эквализации:**
```yaml
filters:
  # Подъем баса на 100 Hz
  Bass_Boost:
    type: Biquad
    parameters:
      type: Peaking
      freq: 100
      q: 1.0
      gain: 3.0  # +3 dB

pipeline:
  - type: Mixer
    name: stereo_to_4ch
  - type: Filter
    channels: [0, 1]  # Применить к L и R
    names:
      - Bass_Boost
```

### Редактирование Bi-Amping
```bash
sudo nano /etc/camilladsp/configs/altec601b-biamp-3000hz.yml
```

**Изменение частоты кроссовера:**
Найдите секцию `filters` и измените параметр `freq`:
```yaml
filters:
  LPF_3000_stage1:
    type: Biquad
    parameters:
      type: Lowpass
      freq: 3000  # ← Измените здесь
      q: 0.707
```

**После изменений:**
```bash
# Проверить валидность
camilladsp -c /etc/camilladsp/configs/ваш-файл.yml -v

# Перезагрузить конфигурацию
sudo systemctl restart camilladsp
```

## 🔌 Подключение динамиков к Scarlett 4i4

### Режим Full-Range (текущий)
- **Output 1**: Левый канал → Левый динамик
- **Output 2**: Правый канал → Правый динамик
- **Outputs 3-4**: Не используются

### Режим Bi-Amping Altec 601B (будущий)
- **Output 1**: НЧ Left → Усилитель НЧ → НЧ драйвер левой колонки
- **Output 2**: НЧ Right → Усилитель НЧ → НЧ драйвер правой колонки
- **Output 3**: ВЧ Left → Усилитель ВЧ → ВЧ драйвер левой колонки
- **Output 4**: ВЧ Right → Усилитель ВЧ → ВЧ драйвер правой колонки

⚠️ **Важно**: В режиме биампинга необходимо 4 усилителя мощности!

## 🐛 Диагностика проблем

### Нет звука
```bash
# 1. Проверить статус CamillaDSP
sudo systemctl status camilladsp

# 2. Проверить ALSA устройства
aplay -l

# 3. Проверить loopback модуль
lsmod | grep snd_aloop

# 4. Посмотреть логи в реальном времени
sudo journalctl -u camilladsp -f
```

### Перезагрузить loopback модуль
```bash
sudo rmmod snd_aloop
sudo modprobe snd_aloop
sudo systemctl restart camilladsp
```

### Проверка уровня сигнала
В логах CamillaDSP должны быть значения `signal rms`:
```bash
sudo journalctl -u camilladsp -n 10 | grep "signal rms"
```
- `[0.0, 0.0, 0.0, 0.0]` - нет сигнала
- Ненулевые значения - есть сигнал

### ⚠️ Известная проблема: выходы 3-4 "не работают" или играют не то, что должны

**Симптомы:** CamillaDSP по всем признакам (WebSocket API, логи, `signal rms`) корректно
формирует сигнал на всех 4 каналах, но физически:
- выход 4 полностью молчит,
- выход 3 играет что-то постороннее (не ВЧ от CamillaDSP, а прямой микс входов).

**Причина:** У Scarlett 4i4 (и других интерфейсов Focusrite с драйвером `scarlett2`)
физические аналоговые выходы не жёстко привязаны к PCM-каналам USB-потока — у карты
есть собственная внутренняя матрица маршрутизации. Каждый физический выход имеет
ALSA-контрол `Analogue Output 0N Playback Enum`, который выбирает, что именно на него
подавать: `PCM N` (то, что реально пишет CamillaDSP), один из входов (`Analogue N`),
один из внутренних миксов (`Mix A`...`Mix F`, обычно используются для мониторинга входов
"вживую"), либо `Off`.

По какой-то причине (сброс настроек, переустановка, ручная правка) на этой машине
оказалось:
```
Analogue Output 01 → PCM 1   (верно)
Analogue Output 02 → PCM 2   (верно)
Analogue Output 03 → Mix C   (неверно! получал не то, что шлёт CamillaDSP)
Analogue Output 04 → Off     (неверно! выход был программно выключен)
```

**Диагностика (без CamillaDSP, напрямую на железе):**
```bash
# Посмотреть все ALSA-контролы карты, найти "Analogue Output"
amixer -c USB controls | grep -i "Analogue Output"

# Прочитать текущий источник для каждого физического выхода (numid 22-25 на этой карте)
amixer -c USB cget numid=22   # Analogue Output 01
amixer -c USB cget numid=23   # Analogue Output 02
amixer -c USB cget numid=24   # Analogue Output 03
amixer -c USB cget numid=25   # Analogue Output 04
```
Ищите пункт `PCM N`, где N совпадает с номером выхода. Если стоит `Mix X` или `Off` —
это и есть причина немоты/подмены сигнала.

**Исправление:**
```bash
sudo systemctl stop camilladsp        # освободить устройство
amixer -c USB cset numid=24 13        # Analogue Output 03 -> PCM 3 (item #13)
amixer -c USB cset numid=25 14        # Analogue Output 04 -> PCM 4 (item #14)
sudo alsactl store                    # сохранить состояние ALSA, чтобы пережило перезагрузку
sudo systemctl start camilladsp
```
(Значения `numid` и номера пунктов enum могут отличаться на другой карте/прошивке —
всегда проверяйте через `cget` перед `cset`.)

**Проверка результата** — подать тестовый тон напрямую на "сырой" ALSA-канал в обход
CamillaDSP и послушать, из какого физического разъёма звучит:
```bash
# Тон только на канале с индексом 2 (3-й PCM-канал), 20 секунд
ffmpeg -f lavfi -i "sine=frequency=1000:duration=20" \
  -af "pan=4c|c0=0*c0|c1=0*c0|c2=c0|c3=0*c0" -ar 48000 -f s32le - \
  | aplay -D hw:USB,0 -f S32_LE -r 48000 -c 4 -
```
Должен звучать именно физический выход 3.

**На будущее:** если после переустановки/сброса Scarlett или обновления прошивки
кроссовер снова "ломается" по описанным симптомам — в первую очередь проверяйте
именно `Analogue Output 0N Playback Enum`, а не конфиг CamillaDSP.

## 📊 Технические характеристики

### Активный кроссовер Altec 601B
- **Тип**: Linkwitz-Riley 4th order (LR4)
- **Наклон**: 24 dB/октава
- **Частота раздела**: 3000 Hz
- **Q фактор**: 0.707 (Butterworth)
- **Фазировка**: Синфазная на частоте раздела

### Настройки обработки
- **Частота дискретизации**: 48 kHz
- **Размер буфера**: 1024 семпла (~21 мс @ 48 kHz)
- **Формат**: S32_LE (32-bit signed little-endian)
- **Адаптивная синхронизация**: Включена
- **WebSocket порт**: 1234 (для будущего веб-управления)

## 🔮 Планы развития

- [ ] Веб-интерфейс для управления CamillaDSP из Aether Player
- [ ] Управление громкостью через CamillaDSP
- [ ] Сохранение пользовательских пресетов эквализации
- [ ] Room correction (измерение и коррекция акустики комнаты)
- [ ] Динамическая компрессия/лимитер
- [ ] Задержки каналов для time alignment

## 📚 Дополнительные ресурсы

- [CamillaDSP Documentation](https://github.com/HEnquist/camilladsp)
- [CamillaDSP GUI](https://github.com/HEnquist/camillagui)
- [Altec 601B Information](http://www.alteclansingarchivals.com/)

---

*Документ создан: 2026-08-16*  
*Версия CamillaDSP: 4.1.3*  
*Система: Raspberry Pi 4, Debian Bookworm*
