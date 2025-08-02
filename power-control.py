#!/usr/bin/env python3
"""
Система управления питанием периферии Aether Player (v6.0)
Использует библиотеку RPi.GPIO для надежного управления реле 220В
"""

import RPi.GPIO as GPIO
import time
import sys
import os
import signal
import subprocess
import json
from pathlib import Path

# Конфигурация
POWER_GPIO = 18  # GPIO пин для управления реле (BCM нумерация) - ПЕРЕКЛЮЧЕНО НА GPIO18!
PIDFILE = "/home/eu/aether-player/aether-power-gpio.pid"
STATUSFILE = "/home/eu/aether-player/aether-power-status.json"

class PowerControl:
    def __init__(self):
        self.gpio_pin = POWER_GPIO
        self.is_initialized = False
        self.power_state = False
        
    def init_gpio(self):
        """Инициализация GPIO"""
        try:
            # Очистка от предыдущих сессий
            try:
                GPIO.cleanup()
            except:
                pass
            
            # Устанавливаем режим BCM (Broadcom SOC channel)
            GPIO.setmode(GPIO.BCM)
            
            # Отключаем предупреждения о уже используемых пинах
            GPIO.setwarnings(False)
            
            # Настраиваем пин как выход
            GPIO.setup(self.gpio_pin, GPIO.OUT)
            
            # Устанавливаем начальное состояние LOW (выключено)
            GPIO.output(self.gpio_pin, GPIO.LOW)
            
            self.is_initialized = True
            self.power_state = False
            print(f"GPIO {self.gpio_pin} инициализирован успешно")
            return True
            
        except Exception as e:
            print(f"ОШИБКА инициализации GPIO: {e}")
            return False
    
    def power_on(self):
        """Включение питания периферии"""
        if not self.is_initialized:
            if not self.init_gpio():
                return False
        
        try:
            print("=== Включение питания периферии ===")
            print("⚠️  ВНИМАНИЕ: Реле 5В, а RPi выдаёт 3.3В!")
            print("   Убедитесь что используете оптопару или транзистор")
            print("")
            
            # Устанавливаем GPIO в HIGH (3.3V)
            GPIO.output(self.gpio_pin, GPIO.HIGH)
            self.power_state = True
            
            # Проверяем состояние
            time.sleep(0.1)
            actual_state = GPIO.input(self.gpio_pin)
            
            if actual_state:
                print(f"УСПЕХ: GPIO включен")
                print(f"GPIO {self.gpio_pin} = HIGH (3.3V)")
                print("💡 Для реле 5В нужна оптопара для усиления сигнала")
                self.save_status()
                self.log_event("GPIO включен (требует оптопары для реле 5В)")
                return True
            else:
                print(f"ОШИБКА: GPIO {self.gpio_pin} не установился в HIGH")
                return False
                
        except Exception as e:
            print(f"ОШИБКА включения питания: {e}")
            return False
    
    def power_off(self):
        """Выключение питания периферии"""
        if not self.is_initialized:
            if not self.init_gpio():
                return False
        
        try:
            print("=== Выключение питания периферии ===")
            
            # Устанавливаем GPIO в LOW (0V)
            GPIO.output(self.gpio_pin, GPIO.LOW)
            self.power_state = False
            
            # Проверяем состояние
            time.sleep(0.1)
            actual_state = GPIO.input(self.gpio_pin)
            
            if not actual_state:
                print(f"УСПЕХ: Питание выключено")
                print(f"GPIO {self.gpio_pin} = LOW (0V)")
                self.save_status()
                self.log_event("Питание выключено")
                return True
            else:
                print(f"ОШИБКА: GPIO {self.gpio_pin} не установился в LOW")
                return False
                
        except Exception as e:
            print(f"ОШИБКА выключения питания: {e}")
            return False
    
    def status(self):
        """Проверка состояния системы"""
        print("=== Состояние системы ===")
        
        if not self.is_initialized:
            self.init_gpio()
        
        try:
            # Читаем реальное состояние GPIO
            actual_state = GPIO.input(self.gpio_pin)
            
            if actual_state:
                print(f"GPIO: ВКЛЮЧЕН (GPIO {self.gpio_pin} = HIGH)")
                print("Уровень GPIO: 3.3V")
                print("Статус реле: ЗАВИСИТ ОТ ОПТОПАРЫ")
                print("⚠️  Реле 5В требует оптопару для управления!")
            else:
                print(f"GPIO: ВЫКЛЮЧЕН (GPIO {self.gpio_pin} = LOW)")
                print("Уровень GPIO: 0V") 
                print("Статус реле: ВЫКЛЮЧЕНО")
            
            print(f"Инициализирован: {'ДА' if self.is_initialized else 'НЕТ'}")
            print(f"Режим GPIO: BCM")
            print(f"Пин: GPIO {self.gpio_pin} (физический pin 37)")
            
            print("")
            print("🔌 Схема подключения для реле 5В:")
            print("RPi 3.3V → Оптопара → Транзистор → Реле 5В")
            print("")
            print("Управляемые устройства:")
            print("• Усилитель звука")
            print("• Внешний HDD")
            print("• Дополнительная периферия")
            
            return actual_state
            
        except Exception as e:
            print(f"ОШИБКА чтения состояния: {e}")
            return None
    
    def safe_power_off(self):
        """Безопасное выключение с отмонтированием USB"""
        print("=== Безопасное выключение ===")
        
        # Останавливаем Aether Player
        print("Останавливаем Aether Player...")
        try:
            subprocess.run(["sudo", "pkill", "-f", "python.*app"], 
                         timeout=5, capture_output=True)
            subprocess.run(["sudo", "pkill", "-f", "mpv"], 
                         timeout=5, capture_output=True)
            time.sleep(2)
        except subprocess.TimeoutExpired:
            print("Таймаут остановки процессов")
        except Exception as e:
            print(f"Ошибка остановки процессов: {e}")
        
        # Отмонтируем USB накопители
        print("Отмонтирование USB накопителей...")
        try:
            result = subprocess.run(["mount"], capture_output=True, text=True)
            usb_mounts = [line.split()[0] for line in result.stdout.split('\n') 
                         if '/dev/sd' in line]
            
            if usb_mounts:
                for device in usb_mounts:
                    print(f"Отмонтирование {device}...")
                    subprocess.run(["sudo", "umount", device], 
                                 timeout=10, capture_output=True)
                
                # Синхронизация
                subprocess.run(["sync"], timeout=5)
                time.sleep(2)
                print("USB накопители отмонтированы")
            else:
                print("USB накопители не найдены")
                
        except Exception as e:
            print(f"Ошибка отмонтирования: {e}")
        
        # Выключаем питание
        return self.power_off()
    
    def test_relay(self):
        """Тестирование реле"""
        print("=== ТЕСТ РЕЛЕ ===")
        print("")
        
        print("1. Инициализация GPIO:")
        if not self.init_gpio():
            print("ОШИБКА: Не удалось инициализировать GPIO")
            return False
        print("")
        
        print("2. Текущее состояние:")
        self.status()
        print("")
        
        print("3. Тест включения (3 сек):")
        if self.power_on():
            time.sleep(3)
            print("Включение протестировано")
        else:
            print("ОШИБКА включения")
            return False
        print("")
        
        print("4. Состояние после включения:")
        state = self.status()
        print("")
        
        print("5. Тест выключения:")
        if self.power_off():
            time.sleep(1)
            print("Выключение протестировано")
        else:
            print("ОШИБКА выключения")
        print("")
        
        print("6. Финальное состояние:")
        self.status()
        print("")
        
        print("=== ТЕСТ ЗАВЕРШЕН ===")
        print(f"ПРОВЕРЬТЕ мультиметром GPIO {self.gpio_pin} (pin 37):")
        print("• При включении: 3.3V на GPIO")
        print("• При выключении: 0V на GPIO")
        print("")
        print("⚠️  ДЛЯ РЕЛЕ 5В НУЖНА СХЕМА УСИЛЕНИЯ:")
        print("RPi GPIO 3.3V → Оптопара/Транзистор → Реле 5V")
        print("")
        print("Рекомендуемые компоненты:")
        print("• Оптопара PC817 или аналог")
        print("• Транзистор 2N2222 или BC547")
        print("• Резистор 220-330 Ом")
        
        return True
    
    def save_status(self):
        """Сохранение состояния в файл"""
        try:
            status_data = {
                "gpio_pin": self.gpio_pin,
                "power_state": self.power_state,
                "timestamp": time.time(),
                "initialized": self.is_initialized
            }
            
            with open(STATUSFILE, 'w') as f:
                json.dump(status_data, f)
                
        except Exception as e:
            print(f"Ошибка сохранения статуса: {e}")
    
    def log_event(self, message):
        """Логирование события"""
        try:
            subprocess.run(["logger", f"Aether Player: {message} (GPIO {self.gpio_pin})"])
        except:
            pass
    
    def cleanup(self):
        """Очистка GPIO при завершении"""
        try:
            if self.is_initialized:
                # Сначала устанавливаем LOW для безопасности
                GPIO.output(self.gpio_pin, GPIO.LOW)
                time.sleep(0.1)
                GPIO.cleanup()
                print("GPIO очищен")
                
            # Удаляем файлы состояния
            for filepath in [PIDFILE, STATUSFILE]:
                if os.path.exists(filepath):
                    os.remove(filepath)
            
            # Удаляем проблемный lgpio файл если он есть
            lgd_file = "/home/eu/aether-player/.lgd-nfy0"
            if os.path.exists(lgd_file):
                try:
                    os.remove(lgd_file)
                    print("Файл .lgd-nfy0 удален")
                except:
                    pass
                    
        except Exception as e:
            print(f"Ошибка очистки: {e}")

def signal_handler(signum, frame):
    """Обработчик сигналов для корректного завершения"""
    print("\nПолучен сигнал завершения...")
    power_control.cleanup()
    sys.exit(0)

def daemon_mode():
    """Режим демона для удержания состояния GPIO"""
    # Регистрируем обработчики сигналов
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Сохраняем PID
    with open(PIDFILE, 'w') as f:
        f.write(str(os.getpid()))
    
    print(f"Демон запущен (PID: {os.getpid()})")
    print("Для остановки используйте: power-control.py off")
    
    try:
        # Бесконечный цикл для удержания процесса
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        pass
    finally:
        power_control.cleanup()

def main():
    global power_control
    power_control = PowerControl()
    
    if len(sys.argv) < 2:
        print("Система управления питанием Aether Player v6.0 (Python)")
        print("")
        print("Использует библиотеку RPi.GPIO для надежного управления GPIO")
        print("⚠️  ВНИМАНИЕ: Для реле 5В требуется оптопара/транзистор!")
        print("")
        print("Команды:")
        print("  on, start    - Включить GPIO (3.3V)")
        print("  off, stop    - Выключить GPIO (0V)")
        print("  safe-off     - Безопасно выключить с отмонтированием")
        print("  status       - Показать состояние GPIO")
        print("  test         - Протестировать GPIO")
        print("  daemon       - Запустить в режиме демона")
        print("  cleanup      - Очистить GPIO")
        print("")
        print("Примеры:")
        print("  sudo python3 power-control.py on")
        print("  sudo python3 power-control.py status")
        print("  sudo python3 power-control.py test")
        print("")
        print(f"Подключение: RPi Pin 37 (GPIO {POWER_GPIO}) → Оптопара → Реле 5В")
        print("Схема: RPi 3.3V → PC817 → 2N2222 → Реле 5V")
        print("")
        return
    
    command = sys.argv[1].lower()
    
    try:
        if command in ['on', 'start', 'enable']:
            success = power_control.power_on()
            # НЕ запускаем демон - GPIO держит состояние сам по себе
            sys.exit(0 if success else 1)
            
        elif command in ['off', 'stop', 'disable']:
            # Останавливаем демон если запущен
            if os.path.exists(PIDFILE):
                with open(PIDFILE, 'r') as f:
                    pid = int(f.read().strip())
                try:
                    os.kill(pid, signal.SIGTERM)
                    time.sleep(0.5)
                except ProcessLookupError:
                    pass
            
            success = power_control.power_off()
            sys.exit(0 if success else 1)
            
        elif command in ['safe-off', 'safe-stop']:
            success = power_control.safe_power_off()
            sys.exit(0 if success else 1)
            
        elif command in ['status', 'check', 'state']:
            power_control.status()
            
        elif command in ['test', 'debug']:
            success = power_control.test_relay()
            sys.exit(0 if success else 1)
            
        elif command == 'daemon':
            power_control.init_gpio()
            daemon_mode()
            
        elif command in ['cleanup', 'clean']:
            power_control.cleanup()
            
        else:
            print(f"Неизвестная команда: {command}")
            sys.exit(1)
            
    except KeyboardInterrupt:
        print("\nПрервано пользователем")
        power_control.cleanup()
        sys.exit(1)
    except Exception as e:
        print(f"ОШИБКА: {e}")
        power_control.cleanup()
        sys.exit(1)

if __name__ == "__main__":
    main()
