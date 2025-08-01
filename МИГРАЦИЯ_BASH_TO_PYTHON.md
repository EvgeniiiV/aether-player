# MIGRATION: Bash → Python для управления питанием

## ✅ ВЫПОЛНЕНО

### Переход от Bash к Python
- **Старый**: `power-control.sh` (Bash + libgpiod/sysfs)
- **Новый**: `power-control.py` (Python + RPi.GPIO)

### Причины перехода
1. **Надежность**: RPi.GPIO стабильнее libgpiod
2. **Поддержка реле 5В**: четкие предупреждения и инструкции 
3. **Демон режим**: удержание состояния GPIO
4. **Лучшая интеграция**: с Flask backend

### Что изменилось
- ✅ Flask `app.py` использует `power-control.py`
- ✅ `setup-power-management.sh` обновлен
- ✅ `power-control.sh` → `power-control.sh.backup`

### Команды (новые)
```bash
sudo python3 power-control.py on      # Включить
sudo python3 power-control.py off     # Выключить
sudo python3 power-control.py status  # Статус
sudo python3 power-control.py test    # Тест
```

### Команды (старые - больше не работают)
```bash
./power-control.sh on     # ❌ УСТАРЕЛО
./power-control.sh status # ❌ УСТАРЕЛО
```

## 🔧 Если нужно восстановить Bash версию
```bash
git mv power-control.sh.backup power-control.sh
```

**Рекомендация**: Используйте Python версию - она надежнее и лучше интегрирована!
