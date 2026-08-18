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

### Системные файлы
- **Бинарник**: `/usr/local/bin/camilladsp`
- **Скрипт переключения**: `/usr/local/bin/camilladsp-switch`
- **Systemd сервис**: `/etc/systemd/system/camilladsp.service`
- **ALSA конфиг**: `~/.asoundrc`

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
