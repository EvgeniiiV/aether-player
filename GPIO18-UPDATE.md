# Переход на GPIO18 для управления реле

## Проблема с GPIO21
- GPIO21 на данной системе не может быть установлен в режим output
- Системная ошибка "export_store: invalid GPIO 21" в dmesg
- Неизвестная блокировка на уровне ядра или железа

## Решение: GPIO18
- ✅ GPIO18 успешно переключается между 0V и 3.3V (проверено мультиметром)
- ✅ Реле физически срабатывает при переключении GPIO18
- ✅ power-control.py обновлен для использования GPIO18
- ✅ Все API функции работают корректно

## Обновленная схема подключения
```
RPi GPIO18 (физический pin 37) → Оптопара → Транзистор → Реле 5В → Периферия
```

## Файлы обновлены
- `power-control.py`: POWER_GPIO = 18
- Все остальные файлы работают без изменений

## Тестирование
1. **Прямой тест GPIO**: ✅ Успешно
2. **Физическое переключение реле**: ✅ Успешно  
3. **API управление**: ✅ Успешно
4. **Статус мониторинг**: ✅ Успешно

## Команды для управления
```bash
# Статус
python3 /home/eu/aether-player/power-control.py status

# Включить
python3 /home/eu/aether-player/power-control.py on

# Выключить
python3 /home/eu/aether-player/power-control.py off

# Безопасное выключение
python3 /home/eu/aether-player/power-control.py safe-off
```

## Web API
```bash
# Статус
curl -X POST http://localhost:5000/system/power -d "action=status"

# Включить
curl -X POST http://localhost:5000/system/power -d "action=on"

# Выключить  
curl -X POST http://localhost:5000/system/power -d "action=off"
```

## Результат
🎉 **Система управления питанием полностью функциональна с GPIO18**

Дата обновления: 2 августа 2025
