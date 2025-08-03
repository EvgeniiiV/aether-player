# Aether Player - простой медиаплеер на Flask + MPV

try:
    from gevent import monkey
    monkey.patch_all(subprocess=False)
    GEVENT_AVAILABLE = True
except ImportError:
    GEVENT_AVAILABLE = False

import os
import json
import time  
import logging
try:
    import gevent
    GEVENT_AVAILABLE = True
except ImportError:
    GEVENT_AVAILABLE = False
import multiprocessing
from flask import Flask, render_template, request, redirect, url_for, abort, jsonify, send_from_directory

# Импорт модуля аудио-улучшений
from audio_enhancement import AudioEnhancement

try:
    from flask_socketio import SocketIO
    SOCKETIO_AVAILABLE = True
except ImportError:
    SOCKETIO_AVAILABLE = False

from werkzeug.utils import secure_filename

from werkzeug.utils import secure_filename

# Изолированные функции для запуска процессов (сохраняем для совместимости с RPi)
def isolated_popen(command, **kwargs):
    """Запускает subprocess.Popen в отдельном процессе для изоляции от gevent"""
    import subprocess as std_subprocess
    
    def _run_popen(command, kwargs, result_queue):
        try:
            proc = std_subprocess.Popen(command, **kwargs)
            result_queue.put(proc.pid)
        except Exception as e:
            result_queue.put(f"ERROR: {str(e)}")
    
    result_queue = multiprocessing.Queue()
    process = multiprocessing.Process(target=_run_popen, args=(command, kwargs, result_queue))
    process.start()
    process.join(timeout=5)
    
    if not result_queue.empty():
        result = result_queue.get()
        if isinstance(result, str) and result.startswith("ERROR:"):
            raise Exception(result)
        return result
    return None

def isolated_run(command, **kwargs):
    """Запускает subprocess.run в отдельном процессе для изоляции от gevent"""
    import subprocess as std_subprocess
    
    def _run_subprocess(command, kwargs, result_queue):
        try:
            result = std_subprocess.run(command, **kwargs)
            output_data = {'returncode': result.returncode}
            if hasattr(result, 'stdout') and result.stdout:
                output_data['stdout'] = result.stdout
            if hasattr(result, 'stderr') and result.stderr:
                output_data['stderr'] = result.stderr
            result_queue.put(output_data)
        except Exception as e:
            result_queue.put(f"ERROR: {str(e)}")
    
    result_queue = multiprocessing.Queue()
    process = multiprocessing.Process(target=_run_subprocess, args=(command, kwargs, result_queue))
    process.start()
    process.join(timeout=5)
    
    if not result_queue.empty():
        result = result_queue.get()
        if isinstance(result, str) and result.startswith("ERROR:"):
            raise Exception(result)
        return result
    return {'returncode': -1}

# Настройка логирования (сохраняем существующую)
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')

file_handler = logging.FileHandler('aether-player.log')
file_handler.setFormatter(formatter)

error_file_handler = logging.FileHandler('aether-player.error.log')
error_file_handler.setLevel(logging.ERROR)
error_file_handler.setFormatter(formatter)

console_handler = logging.StreamHandler()
console_handler.setFormatter(formatter)

logger = logging.getLogger('aether_player')
logger.setLevel(logging.DEBUG)
logger.addHandler(file_handler)
logger.addHandler(error_file_handler)
logger.addHandler(console_handler)
logger.propagate = False

# Конфигурация
app = Flask(__name__)

if SOCKETIO_AVAILABLE and GEVENT_AVAILABLE:
    socketio = SocketIO(app, async_mode='gevent')
elif SOCKETIO_AVAILABLE:
    socketio = SocketIO(app, async_mode='threading')
else:
    socketio = None

MEDIA_ROOT = "/mnt/hdd"
MPV_SOCKET = "/tmp/mpv_socket"
MEDIA_EXTENSIONS = ['.flac', '.wav', '.wv', '.dsf', '.dff', '.mp3', '.aac', '.ogg', '.m4a', 
                   '.mkv', '.mp4', '.avi', '.mov', '.wmv', '.flv', '.webm', 
                   '.jpg', '.jpeg', '.png', '.bmp', '.gif', '.tiff']

def get_file_type(filepath):
    """Определяет тип медиафайла"""
    ext = os.path.splitext(filepath)[1].lower()
    
    audio_extensions = ['.flac', '.wav', '.wv', '.dsf', '.dff', '.mp3', '.aac', '.ogg', '.m4a']
    video_extensions = ['.mkv', '.mp4', '.avi', '.mov', '.wmv', '.flv', '.webm']
    image_extensions = ['.jpg', '.jpeg', '.png', '.bmp', '.gif', '.tiff']
    
    if ext in audio_extensions:
        return 'audio'
    elif ext in video_extensions:
        return 'video'
    elif ext in image_extensions:
        return 'image'
    else:
        return 'unknown'

def get_best_audio_device():
    """Автоматически определяет лучшее доступное аудио устройство"""
    try:
        # Проверяем доступные аудио карты
        with open('/proc/asound/cards', 'r') as f:
            cards_content = f.read()
        
        logger.debug(f"Доступные ALSA карты:\n{cards_content}")
        
        # Парсим карты для динамического определения номеров
        import re
        card_lines = cards_content.strip().split('\n')
        detected_cards = {}
        
        for line in card_lines:
            # Формат: " 0 [Headphones     ]: bcm2835_headpho - bcm2835 Headphones"
            match = re.match(r'\s*(\d+)\s+\[([^\]]+)\]\s*:\s*(.+)', line)
            if match:
                card_num = int(match.group(1))
                card_name = match.group(2).strip()
                card_desc = match.group(3).strip()
                detected_cards[card_num] = {'name': card_name, 'desc': card_desc}
        
        logger.debug(f"Обнаружены карты: {detected_cards}")
        
        # Приоритет устройств (от лучшего к худшему) - теперь ищем динамически
        audio_priorities = [
            ('Scarlett', 'Focusrite'),     # Focusrite Scarlett (любой номер)
            ('USB', 'USB'),                # Любое USB аудио
            ('vc4hdmi0', 'vc4-hdmi'),      # HDMI выход 1
            ('Headphones', 'Headphones')   # Встроенный 3.5mm
        ]
        
        # Ищем устройства по приоритету
        for priority_name, search_pattern in audio_priorities:
            for card_num, card_info in detected_cards.items():
                card_name = card_info['name']
                card_desc = card_info['desc']
                
                # Проверяем вхождение паттерна в имя или описание карты
                if (search_pattern.lower() in card_name.lower() or 
                    search_pattern.lower() in card_desc.lower()):
                    
                    alsa_device = f"alsa/hw:{card_num},0"
                    logger.info(f"✅ Выбрано аудио устройство: {priority_name} -> {card_name} ({alsa_device})")
                    logger.info(f"📋 Описание карты: {card_desc}")
                    return alsa_device
        
        # Если ничего не найдено, используем по умолчанию
        logger.warning("⚠️ НЕ УДАЛОСЬ определить специфическое аудио устройство!")
        logger.warning(f"📊 Доступные карты: {list(detected_cards.keys())}")
        logger.warning("🔄 Используем 'auto' - MPV выберет устройство сам")
        logger.warning("💡 Если звука нет, проверьте подключение Scarlett 2i2")
        return "auto"
        
    except Exception as e:
        logger.error(f"Ошибка определения аудио устройства: {e}")
        return "auto"

def get_file_duration_ffprobe(filepath):
    """
    Получает длительность аудио файла через ffprobe как fallback для DSF/DSD файлов
    """
    try:
        import subprocess
        cmd = [
            'ffprobe', 
            '-v', 'quiet', 
            '-print_format', 'json', 
            '-show_format', 
            filepath
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        if result.returncode == 0:
            import json
            probe_data = json.loads(result.stdout)
            duration = float(probe_data.get('format', {}).get('duration', 0))
            if duration > 0:
                logger.info(f"📊 FFprobe определил duration: {duration:.1f}s для {os.path.basename(filepath)}")
                return duration
        else:
            logger.warning(f"FFprobe error: {result.stderr}")
    except Exception as e:
        logger.warning(f"Ошибка ffprobe для {filepath}: {e}")
    
    return None

def save_volume_setting(volume):
    """Сохраняет настройку громкости в файл"""
    try:
        volume_file = '/tmp/aether-player-volume.txt'
        with open(volume_file, 'w') as f:
            f.write(str(int(volume)))
        logger.debug(f"💾 Громкость сохранена: {volume}%")
    except Exception as e:
        logger.warning(f"Не удалось сохранить громкость: {e}")

def save_audio_enhancement_setting(preset):
    """Сохраняет настройку предустановки аудио в файл"""
    try:
        preset_file = '/tmp/aether-player-audio-enhancement.txt'
        with open(preset_file, 'w') as f:
            f.write(str(preset))
        logger.debug(f"💾 Предустановка аудио сохранена: {preset}")
    except Exception as e:
        logger.warning(f"Не удалось сохранить предустановку аудио: {e}")

def load_volume_setting():
    """Загружает сохраненную настройку громкости"""
    try:
        volume_file = '/tmp/aether-player-volume.txt'
        if os.path.exists(volume_file):
            with open(volume_file, 'r') as f:
                saved_volume = int(f.read().strip())
                # Безопасное ограничение: не более 70% при запуске
                safe_volume = min(saved_volume, 70)
                if saved_volume > 70:
                    logger.info(f"🔒 Громкость ограничена для безопасности: {saved_volume}% -> {safe_volume}%")
                else:
                    logger.info(f"📂 Загружена сохраненная громкость: {safe_volume}%")
                return safe_volume
    except Exception as e:
        logger.warning(f"Не удалось загрузить громкость: {e}")
    
    # По умолчанию - безопасные 50%
    logger.info("🔊 Установлена громкость по умолчанию: 50%")
    return 50

def load_audio_enhancement_setting():
    """Загружает сохраненную предустановку виртуальной стереосцены"""
    try:
        preset_file = '/tmp/aether-player-audio-enhancement.txt'
        if os.path.exists(preset_file):
            with open(preset_file, 'r') as f:
                saved_preset = f.read().strip()
                # Проверяем, что предустановка корректна
                if saved_preset in audio_enhancer.PRESETS:
                    logger.info(f"📂 Загружена сохраненная предустановка аудио: {saved_preset}")
                    return saved_preset
                else:
                    logger.warning(f"Некорректная сохраненная предустановка: {saved_preset}")
    except Exception as e:
        logger.warning(f"Не удалось загрузить предустановку аудио: {e}")
    
    # По умолчанию - выключено
    logger.info("🎵 Установлена предустановка аудио по умолчанию: off")
    return 'off'

def save_audio_enhancement_setting(preset):
    """Сохраняет предустановку виртуальной стереосцены в файл"""
    try:
        preset_file = '/tmp/aether-player-audio-enhancement.txt'
        with open(preset_file, 'w') as f:
            f.write(str(preset))
        logger.debug(f"💾 Предустановка аудио сохранена: {preset}")
    except Exception as e:
        logger.warning(f"Не удалось сохранить предустановку аудио: {e}")

def load_audio_enhancement_setting():
    """Загружает сохраненную предустановку виртуальной стереосцены"""
    try:
        preset_file = '/tmp/aether-player-audio-enhancement.txt'
        if os.path.exists(preset_file):
            with open(preset_file, 'r') as f:
                saved_preset = f.read().strip()
                if saved_preset in audio_enhancer.PRESETS:
                    logger.info(f"📂 Загружена сохраненная предустановка аудио: {saved_preset}")
                    return saved_preset
                else:
                    logger.warning(f"Неизвестная предустановка аудио: {saved_preset}, используем 'off'")
    except Exception as e:
        logger.warning(f"Не удалось загрузить предустановку аудио: {e}")
    
    # По умолчанию - выключено
    logger.info("🎵 Установлена предустановка аудио по умолчанию: off")
    return 'off'

# Глобальные переменные
player_process = None
last_position_update = time.time()

# Инициализация модуля аудио-улучшений
audio_enhancer = AudioEnhancement()

# Состояние плеера
player_state = {
    'status': 'stopped',
    'track': '',
    'position': 0.0,
    'duration': 0.0,
    'volume': load_volume_setting(),  # Загружаем сохраненную громкость
    'playlist': [],
    'playlist_index': -1,
    'audio_enhancement': load_audio_enhancement_setting()  # Загружаем сохраненную предустановку
}

def update_position_if_playing():
    """Обновляет позицию если трек играет"""
    global player_state, last_position_update
    
    current_time = time.time()
    
    if player_state['status'] == 'playing':
        time_elapsed = current_time - last_position_update
        
        # Обновляем позицию на основе прошедшего времени
        if time_elapsed >= 0.1:  # Более частые обновления
            player_state['position'] += time_elapsed
            last_position_update = current_time
            
            # Проверяем конец трека
            if player_state['position'] >= player_state['duration'] - 0.5:
                if player_state['playlist'] and player_state['playlist_index'] < len(player_state['playlist']) - 1:
                    handle_playlist_change('next')
                else:
                    player_state['status'] = 'stopped'
                    player_state['track'] = ''
                    player_state['position'] = 0.0
                    player_state['playlist'] = []
                    player_state['playlist_index'] = -1

# MPV управление
def mpv_command(command):
    """Отправляет команду в MPV через IPC сокет"""
    if not player_process or player_process.poll() is not None:
        ensure_mpv_is_running()
        if not player_process or player_process.poll() is not None:
            return {"status": "error", "message": "mpv не удалось запустить"}
    
    try:
        json_command = json.dumps(command) + '\n'
        logger.debug(f"Отправка команды MPV: {json_command.strip()}")
        
        if not os.path.exists(MPV_SOCKET):
            logger.error(f"Сокет {MPV_SOCKET} не существует")
            return {"status": "error", "message": "MPV сокет не существует"}
        
        proc_result = isolated_run(
            ['socat', '-t', '2', '-', MPV_SOCKET],
            input=json_command, text=True, check=True, capture_output=True, timeout=2.0
        )
        stdout = proc_result.get('stdout', '')
        
        if stdout:
            try:
                return json.loads(stdout)
            except json.JSONDecodeError as e:
                logger.error(f"Ошибка JSON в ответе MPV: {e}")
                return {"status": "error", "message": f"JSON error: {e}"}
        return {"status": "ok"}
    except Exception as e:
        logger.error(f"Ошибка команды MPV: {e}")
        return {"status": "error", "message": str(e)}

def get_mpv_property(prop):
    """Получает свойство из MPV"""
    response = mpv_command({"command": ["get_property", prop]})
    if response.get("status") == "error":
        return None
    return response.get("data")

def ensure_mpv_is_running():
    """Обеспечивает работу процесса MPV"""
    global player_process
    
    if not player_process or player_process.poll() is not None:
        logger.debug("Запуск MPV процесса")
        
        # Завершаем старые процессы
        try:
            isolated_run(["killall", "mpv"], check=False)
            time.sleep(0.3)
        except:
            pass
        
        # Удаляем старый сокет
        try:
            if os.path.exists(MPV_SOCKET):
                os.remove(MPV_SOCKET)
        except:
            pass
        
        # Запускаем MPV с базовыми настройками (без --no-video для поддержки видео)
        audio_device = get_best_audio_device()
        
        # Получаем безопасную стартовую громкость
        safe_startup_volume = int(player_state['volume'] * 1.3)  # Преобразуем в MPV формат
        
        # Получаем цепочку аудиофильтров для виртуальной стереосцены
        enhancement_preset = player_state.get('audio_enhancement', 'off')
        af_string = audio_enhancer.get_mpv_af_string(enhancement_preset)
        
        # ВАЖНО: НЕ КОММЕНТИРОВАТЬ --audio-device! 
        # Эта строка обеспечивает направление звука на правильное устройство.
        # Если звука нет - проблема в номере карты, а не в этом параметре!
        command = [
            "mpv", 
            "--idle", 
            f"--input-ipc-server={MPV_SOCKET}", 
            f"--audio-device={audio_device}",  # ⚠️ КРИТИЧЕСКИ ВАЖНО - НЕ УДАЛЯТЬ!
            f"--volume={safe_startup_volume}", # Безопасная стартовая громкость
            "--softvol-max=200",               # Максимальная программная громкость 200% для плавной регулировки
            "--vo=gpu",                        # Видео вывод через GPU для HDMI
            "--hwdec=auto",                    # Аппаратное декодирование видео
            # Минимальные параметры для поддержки и аудио, и видео
        ]
        
        # Добавляем аудиофильтры если они есть
        if af_string:
            command.append(f"--af={af_string}")
            logger.info(f"🎵 Применены аудиофильтры: {af_string}")
        else:
            logger.info("🎵 Аудиофильтры отключены")
        
        # Простой запуск MPV без изоляции - исправление проблемы запуска
        try:
            import subprocess
            player_process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            logger.info(f"MPV запущен с PID {player_process.pid}")
            
            # Ждем создания сокета
            for i in range(50):  # максимум 5 секунд
                if os.path.exists(MPV_SOCKET):
                    break
                time.sleep(0.1)
            
            if not os.path.exists(MPV_SOCKET):
                logger.error("MPV запущен, но сокет не создан")
                return False
                
        except Exception as e:
            logger.error(f"Ошибка запуска MPV: {e}")
            return False
        
    return True

def apply_audio_enhancement(preset_name='off'):
    """Применяет аудиофильтры для виртуальной стереосцены"""
    global player_state, audio_enhancer
    
    try:
        # Получаем цепочку фильтров
        af_string = audio_enhancer.get_mpv_af_string(preset_name)
        
        # Обновляем состояние ВСЕГДА (даже если MPV не запущен)
        player_state['audio_enhancement'] = preset_name
        audio_enhancer.current_preset = preset_name
        
        # Сохраняем настройку
        save_audio_enhancement_setting(preset_name)
        
        # Проверяем, запущен ли MPV
        if not player_process or player_process.poll() is not None:
            logger.info(f"🎵 Предустановка '{preset_name}' сохранена (MPV не запущен, будет применена при воспроизведении)")
            return True
        
        # Если MPV запущен, пытаемся применить фильтры
        if af_string:
            # Применяем фильтры через MPV команду set_property af
            response = mpv_command({"command": ["set_property", "af", af_string]})
            logger.debug(f"MPV response for af set: {response}")
            if response and response.get("status") != "error":
                logger.info(f"🎵 Применены аудиофильтры '{preset_name}': {af_string}")
                return True
            else:
                logger.warning(f"MPV вернул ошибку при применении фильтров: {response}")
                return True
        else:
            # Очищаем фильтры - устанавливаем пустую строку
            response = mpv_command({"command": ["set_property", "af", ""]})
            logger.debug(f"MPV response for af clear: {response}")
            if response and response.get("status") != "error":
                logger.info(f"🎵 Аудиофильтры очищены (preset: {preset_name})")
                return True
            else:
                logger.warning(f"MPV вернул ошибку при очистке фильтров: {response}")
                return True
        
    except Exception as e:
        logger.error(f"Ошибка применения аудиофильтров: {e}")
        # Даже при ошибке, сохраняем настройку для следующего запуска
        try:
            player_state['audio_enhancement'] = preset_name
            audio_enhancer.current_preset = preset_name
            save_audio_enhancement_setting(preset_name)
            logger.info(f"🎵 Предустановка '{preset_name}' сохранена несмотря на ошибку")
            return True
        except:
            return False

def stop_mpv_internal():
    """Останавливает MPV процесс"""
    global player_process
    
    if player_process and player_process.poll() is None:
        try:
            mpv_command({"command": ["stop"]})
        except:
            pass
        
        try:
            player_process.kill()
        except:
            pass
        
        player_process = None
    
    # Завершаем все процессы
    try:
        isolated_run(["killall", "mpv"], check=False)
        isolated_run(["sudo", "killall", "fbi"], check=False)
    except:
        pass

def emit_status_update():
    """Отправляет обновление статуса клиентам"""
    status_data = {
        'state': player_state['status'],
        'track': player_state['track'],
        'position': round(player_state['position'], 1),
        'duration': round(player_state['duration'], 1),
        'volume': player_state['volume']
    }
    if socketio:
        socketio.emit('status_update', status_data)
def status_update_task():
    """Отключённая фоновая задача"""
    pass

def handle_playlist_change(direction):
    """Обработка смены трека в плейлисте"""
    global player_state
    
    if not player_state['playlist']:
        return
    
    current_index = player_state['playlist_index']
    
    if direction == 'next':
        if current_index < len(player_state['playlist']) - 1:
            new_index = current_index + 1
        else:
            return  # Конец плейлиста
    elif direction == 'previous':
        if player_state['position'] > 3.0 or current_index == 0:
            # Перемотка в начало текущего трека
            mpv_command({"command": ["seek", 0, "absolute"]})
            player_state['position'] = 0.0
            return
        else:
            new_index = current_index - 1
    else:
        return
    
    # Загружаем новый трек
    filepath = player_state['playlist'][new_index]
    mpv_result = mpv_command({"command": ["loadfile", filepath, "replace"]})
    
    if mpv_result.get("status") != "error":
        # Синхронизируемся с MPV для получения duration
        time.sleep(0.5)
        
        # Получаем duration с улучшенной поддержкой DSF файлов
        raw_duration = None
        is_dsf_file = filepath.lower().endswith(('.dsf', '.dff'))
        
        # Для DSF файлов используем более агрессивный подход
        retry_count = 10 if is_dsf_file else 5
        sleep_interval = 0.5 if is_dsf_file else 0.2
        
        for attempt in range(retry_count):
            raw_duration = get_mpv_property("duration")
            if raw_duration and raw_duration > 0:
                logger.info(f"🎵 MPV duration получен на попытке {attempt+1}: {raw_duration:.1f}s")
                break
            time.sleep(sleep_interval)
        
        # Fallback для DSF файлов: используем ffprobe
        if not raw_duration and is_dsf_file:
            logger.info("🔍 MPV не смог получить duration для DSF, пробуем ffprobe...")
            raw_duration = get_file_duration_ffprobe(filepath)
            if raw_duration:
                logger.info(f"✅ FFprobe успешно определил duration: {raw_duration:.1f}s")
        
        if not raw_duration:
            raw_duration = 100.0
            logger.warning(f"⚠️ Не удалось получить duration для {filepath}, используем fallback: {raw_duration}s")
        
        player_state.update({
            'status': 'playing',
            'track': os.path.basename(filepath),
            'position': 0.0,
            'duration': raw_duration,
            'playlist_index': new_index
        })
        
        # Обновляем время последнего изменения позиции
        global last_position_update
        last_position_update = time.time()
        
        logger.info(f"Переключен на трек: {player_state['track']} (duration: {raw_duration})")

# API маршруты
@app.route("/")
def index():
    return redirect(url_for('browse'))

@app.route("/audio-settings")
def audio_settings():
    """Страница настроек виртуальной стереосцены"""
    return render_template("audio_settings.html")

@app.route("/browse/")
@app.route("/browse/<path:subpath>")
def browse(subpath=""):
    current_path = os.path.join(MEDIA_ROOT, subpath)
    if not os.path.realpath(current_path).startswith(os.path.realpath(MEDIA_ROOT)):
        abort(403)
    if not os.path.isdir(current_path):
        abort(404)
    
    items = os.listdir(current_path)
    folders = sorted([i for i in items if os.path.isdir(os.path.join(current_path, i))])
    files = sorted([i for i in items if os.path.isfile(os.path.join(current_path, i))])
    parent_path = os.path.dirname(subpath) if subpath else None
    
    return render_template("index.html", 
                         current_subpath=subpath, 
                         folders=folders, 
                         files=files, 
                         parent_path=parent_path)

@app.route('/media/<path:filepath>')
def media_file(filepath):
    return send_from_directory(MEDIA_ROOT, filepath)

@app.route('/get_status')
def get_status():
    """Возвращает текущий статус плеера"""
    update_position_if_playing()
    
    return jsonify({
        'state': player_state['status'],
        'track': player_state['track'],
        'position': round(player_state['position'], 1),
        'duration': round(player_state['duration'], 1),
        'volume': player_state['volume'],
        'audio_enhancement': player_state.get('audio_enhancement', 'off')
    })

@app.route("/play", methods=['POST'])
def play():
    """Начать воспроизведение файла"""
    global player_state
    
    file_subpath = request.form.get('filepath')
    logger.info(f"Запрос воспроизведения: {file_subpath}")
    
    full_path = os.path.join(MEDIA_ROOT, file_subpath)
    file_type = get_file_type(full_path)
    
    # Для изображений используем fbi
    if file_type == 'image':
        logger.info(f"Отображение изображения: {file_subpath}")
        isolated_run(["sudo", "killall", "fbi"], check=False)
        command = ["sudo", "fbi", "-T", "1", "-a", "--noverbose", full_path]
        from subprocess import DEVNULL
        isolated_popen(command, stdout=DEVNULL, stderr=DEVNULL)
        return jsonify({'status': 'ok', 'message': 'Изображение отображено'})
    
    # Для аудио и видео используем MPV
    if file_type not in ['audio', 'video']:
        return jsonify({'status': 'error', 'message': 'Неподдерживаемый тип файла'})
    
    # Подготавливаем MPV
    ensure_mpv_is_running()
    isolated_run(["sudo", "killall", "fbi"], check=False)  # Закрываем изображения
    
    # Формируем плейлист только из аудио/видео файлов
    current_dir = os.path.dirname(full_path)
    all_files = os.listdir(current_dir)
    playlist = []
    
    for f in sorted(all_files):
        file_path = os.path.join(current_dir, f)
        if get_file_type(file_path) in ['audio', 'video']:
            playlist.append(file_path)
    
    try:
        playlist_index = playlist.index(full_path)
    except ValueError:
        playlist = [full_path]
        playlist_index = 0
    
    # Загружаем файл в MPV
    mpv_result = mpv_command({"command": ["loadfile", full_path, "replace"]})
    if mpv_result.get("status") == "error":
        logger.error(f"Ошибка загрузки файла: {mpv_result}")
        return jsonify({'status': 'error', 'message': 'Ошибка загрузки файла'})
    
    # Настройки в зависимости от типа файла
    if file_type == 'video':
        logger.info(f"Воспроизведение видео: {os.path.basename(full_path)}")
        # Включаем видео вывод и полноэкранный режим для видео
        mpv_command({"command": ["set_property", "vid", "auto"]})  # Включаем видео
        mpv_command({"command": ["set_property", "fullscreen", True]})
        mpv_command({"command": ["set_property", "vo", "gpu"]})  # GPU вывод для HDMI
    else:
        logger.info(f"Воспроизведение аудио: {os.path.basename(full_path)}")
        # Для аудио файлов отключаем видео вывод
        mpv_command({"command": ["set_property", "vid", "no"]})
    
    # СИНХРОНИЗАЦИЯ С MPV - получаем duration и volume
    time.sleep(0.5)
    
    # Получаем duration с улучшенной поддержкой DSF файлов
    raw_duration = None
    is_dsf_file = full_path.lower().endswith(('.dsf', '.dff'))
    
    # Для DSF файлов используем более агрессивный подход
    retry_count = 10 if is_dsf_file else 5
    sleep_interval = 0.5 if is_dsf_file else 0.2
    
    for attempt in range(retry_count):
        raw_duration = get_mpv_property("duration")
        if raw_duration and raw_duration > 0:
            logger.info(f"🎵 MPV duration получен на попытке {attempt+1}: {raw_duration:.1f}s")
            break
        time.sleep(sleep_interval)
    
    # Fallback для DSF файлов: используем ffprobe
    if not raw_duration and is_dsf_file:
        logger.info("🔍 MPV не смог получить duration для DSF, пробуем ffprobe...")
        raw_duration = get_file_duration_ffprobe(full_path)
        if raw_duration:
            logger.info(f"✅ FFprobe успешно определил duration: {raw_duration:.1f}s")
    
    if not raw_duration:
        raw_duration = 100.0
        logger.warning(f"⚠️ Не удалось получить duration, используем fallback: {raw_duration}s")
    
    # Получаем громкость от MPV и преобразуем обратно для пользователя
    mpv_volume = get_mpv_property("volume") or int(player_state['volume'] * 1.3)
    user_volume = int(mpv_volume / 1.3)  # Обратное преобразование
    user_volume = max(0, min(100, user_volume))  # Ограничиваем диапазон
    
    # Снимаем паузу если нужно
    pause_state = get_mpv_property("pause")
    if pause_state:
        mpv_command({"command": ["set_property", "pause", False]})
    
    # Обновляем состояние
    player_state.update({
        'status': 'playing',
        'track': os.path.basename(full_path),
        'position': 0.0,
        'duration': raw_duration,
        'volume': user_volume,  # Используем пользовательское значение громкости
        'playlist': playlist,
        'playlist_index': playlist_index
    })
    
    # Обновляем время последнего изменения позиции
    global last_position_update
    last_position_update = time.time()
    
    logger.info(f"Воспроизведение запущено: {player_state['track']}")
    emit_status_update()
    
    return jsonify({'status': 'ok'})

@app.route("/toggle_pause", methods=['POST'])
def toggle_pause():
    """Переключить паузу"""
    global player_state
    
    if player_state['status'] == 'stopped':
        return jsonify({'status': 'error', 'message': 'Плеер остановлен'})
    
    if not player_process or player_process.poll() is not None:
        return jsonify({'status': 'error', 'message': 'MPV не запущен'})
    
    # Отправляем команду в MPV
    mpv_result = mpv_command({"command": ["cycle", "pause"]})
    if mpv_result.get("status") == "error":
        return jsonify({'status': 'error', 'message': 'Ошибка команды MPV'})
    
    # СИНХРОНИЗАЦИЯ С MPV - получаем реальное состояние паузы
    time.sleep(0.1)
    pause_state = get_mpv_property("pause")
    
    if pause_state is not None:
        if pause_state:
            # Переход в паузу - синхронизируем позицию с MPV
            current_position = get_mpv_property("time-pos")
            if current_position is not None and current_position >= 0:
                player_state['position'] = float(current_position)
            player_state['status'] = 'paused'
        else:
            # Снятие паузы - обновляем время последнего изменения
            global last_position_update
            last_position_update = time.time()
            player_state['status'] = 'playing'
    else:
        # Если не можем получить состояние, переключаем вручную
        if player_state['status'] == 'playing':
            player_state['status'] = 'paused'
        else:
            player_state['status'] = 'playing'
            last_position_update = time.time()
    
    logger.debug(f"Пауза переключена: {player_state['status']}")
    emit_status_update()
    
    return jsonify({'status': 'ok'})

@app.route("/stop", methods=['POST'])
def stop():
    """Остановить воспроизведение"""
    global player_state
    
    stop_mpv_internal()
    
    # Сбрасываем состояние
    player_state.update({
        'status': 'stopped',
        'track': '',
        'position': 0.0,
        'duration': 0.0,
        'playlist': [],
        'playlist_index': -1
    })
    
    logger.info("воспроизведение остановлено")
    emit_status_update()
    
    return jsonify({'status': 'ok'})

@app.route("/seek", methods=['POST'])
def seek():
    """Перемотка на указанную позицию"""
    global player_state
    
    position = request.form.get('position', type=float)
    if position is None:
        return jsonify({'status': 'error', 'message': 'Позиция не указана'})
    
    # Проверяем корректность позиции
    if position < 0:
        position = 0
    if position > player_state['duration']:
        position = player_state['duration']
    
    logger.debug(f"Перемотка на позицию: {position:.1f}")
    
    # Отправляем команду в MPV
    mpv_result = mpv_command({"command": ["seek", position, "absolute"]})
    if mpv_result.get("status") == "error":
        return jsonify({'status': 'error', 'message': 'Ошибка команды MPV'})
    
    # Устанавливаем позицию
    player_state['position'] = position
    
    # Обновляем время последнего изменения позиции
    global last_position_update
    last_position_update = time.time()
    
    emit_status_update()
    return jsonify({'status': 'ok'})

@app.route("/playlist_change", methods=['POST'])
def playlist_change():
    """Смена трека в плейлисте"""
    direction = request.form.get('direction')
    logger.info(f"Смена трека: {direction}")
    handle_playlist_change(direction)
    return jsonify({'status': 'ok'})

@app.route("/set_volume", methods=['POST'])
def set_volume():
    """Установка громкости с использованием встроенных возможностей MPV"""
    user_volume = request.form.get('volume', 50, type=int)
    
    # Ограничиваем диапазон для безопасности
    user_volume = max(0, min(100, user_volume))
    
    # Преобразуем 0-100% пользователя в 0-200% MPV для более плавной регулировки
    # При пользовательских 0% -> MPV 0%, при 100% -> MPV 130% (комфортный максимум)
    mpv_volume = int(user_volume * 1.3)  # Простое линейное масштабирование
    
    logger.debug(f"Громкость: пользователь {user_volume}% -> MPV {mpv_volume}%")
    
    # Отправляем значение в MPV
    mpv_command({"command": ["set_property", "volume", mpv_volume]})
    
    # Сохраняем пользовательское значение
    player_state['volume'] = user_volume
    
    # Сохраняем настройку для следующего запуска
    save_volume_setting(user_volume)
    
    return jsonify({'status': 'ok', 'user_volume': user_volume, 'mpv_volume': mpv_volume})

@app.route("/view_image", methods=['POST'])
def view_image():
    """Просмотр изображения"""
    file_subpath = request.form.get('filepath')
    logger.info(f"Просмотр изображения: {file_subpath}")
    
    full_path = os.path.join(MEDIA_ROOT, file_subpath)
    if os.path.isfile(full_path):
        command = ["sudo", "fbi", "-T", "1", "-a", "--noverbose", full_path]
        isolated_run(["sudo", "killall", "fbi"], check=False)
        from subprocess import DEVNULL
        isolated_popen(command, stdout=DEVNULL, stderr=DEVNULL)
        logger.info(f"Изображение отображено: {os.path.basename(full_path)}")
    
    return jsonify({'status': 'ok'})

@app.route('/upload', methods=['POST'])
def upload_file():
    """Загрузка файлов"""
    current_subpath = request.form.get('current_path', '')
    target_folder = os.path.join(MEDIA_ROOT, current_subpath)
    
    if not os.path.realpath(target_folder).startswith(os.path.realpath(MEDIA_ROOT)):
        abort(403)
    
    if 'files_to_upload' not in request.files:
        return jsonify({'status': 'error', 'message': 'No file part'}), 400
    
    files = request.files.getlist('files_to_upload')
    for file in files:
        if file and file.filename:
            filename = secure_filename(file.filename)
            save_path = os.path.join(target_folder, filename)
            file.save(save_path)
            if socketio:
                socketio.emit('file_uploaded', {'path': current_subpath, 'filename': filename})
    
    return jsonify({'status': 'success'})

@app.route('/create_folder', methods=['POST'])
def create_folder():
    """Создание папки"""
    current_subpath = request.form.get('current_path', '')
    new_folder_name = request.form.get('folder_name', '')
    
    if not new_folder_name:
        abort(400)
    
    folder_name = secure_filename(new_folder_name)
    target_folder = os.path.join(MEDIA_ROOT, current_subpath, folder_name)
    
    if not os.path.realpath(os.path.dirname(target_folder)).startswith(os.path.realpath(MEDIA_ROOT)):
        abort(403)
    
    try:
        os.makedirs(target_folder)
        if socketio:
            socketio.emit('folder_created', {'path': current_subpath, 'foldername': folder_name})
        return jsonify({'status': 'success'})
    except FileExistsError:
        return jsonify({'status': 'error', 'message': 'Папка уже существует'}), 409
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500

def get_power_status():
    """Получает статус управления питанием периферии"""
    try:
        # Используем Python скрипт для получения статуса
        result = isolated_run(['python3', '/home/eu/aether-player/power-control.py', 'status'], check=False)
        
        if result.get('returncode') == 0:
            output = result.get('stdout', '')
            # Парсим вывод для определения состояния
            if "ВКЛЮЧЕНО" in output or "HIGH" in output:
                return "Включено"
            else:
                return "Выключено"
        else:
            return "Ошибка проверки"
    except Exception as e:
        logger.error(f"Ошибка получения статуса питания: {e}")
        return "Ошибка"

# Маршрут мониторинга
@app.route("/monitor")
def monitor_page():
    """Страница мониторинга системы"""
    import subprocess
    import glob
    import os
    
    # Получаем текущие параметры системы
    try:
        # Температура CPU
        temp_result = subprocess.run(['cat', '/sys/class/thermal/thermal_zone0/temp'], capture_output=True, text=True)
        temp_celsius = float(temp_result.stdout.strip()) / 1000 if temp_result.returncode == 0 else 0
        
        # Использование диска
        disk_result = subprocess.run(['df', '-h', '/'], capture_output=True, text=True)
        disk_usage = "Неизвестно"
        if disk_result.returncode == 0:
            lines = disk_result.stdout.strip().split('\n')
            if len(lines) > 1:
                disk_usage = lines[1].split()[4]  # Процент использования
        
        # Использование память
        mem_result = subprocess.run(['free', '-m'], capture_output=True, text=True)
        memory_usage = "Неизвестно"
        if mem_result.returncode == 0:
            lines = mem_result.stdout.strip().split('\n')
            if len(lines) > 1:
                mem_data = lines[1].split()
                total_mem = int(mem_data[1])
                used_mem = int(mem_data[2])
                memory_usage = f"{round(used_mem/total_mem*100, 1)}%"
        
        # Статус сервиса
        service_status = "Работает (ручной запуск)"
        try:
            service_result = subprocess.run(['systemctl', 'is-active', 'aether-player.service'], 
                                          capture_output=True, text=True)
            if service_result.returncode == 0 and service_result.stdout.strip() == 'active':
                service_status = "Работает (systemd)"
            elif service_result.returncode != 0 and service_result.stdout.strip() in ['inactive', 'failed']:
                # Сервис настроен, но неактивен - приложение запущено вручную
                service_status = "Работает (ручной запуск)"
            else:
                service_status = "Остановлен"
        except:
            pass  # Сервис не настроен, остается "Работает (ручной запуск)"
            
    except Exception as e:
        logger.error(f"Ошибка получения данных мониторинга: {e}")
        temp_celsius = 0
        disk_usage = "Ошибка"
        memory_usage = "Ошибка"
        service_status = "Ошибка"
    
    # Получаем последние отчеты
    reports = []
    try:
        # Собираем отчеты мониторинга и памяти
        report_files = []
        report_files.extend(glob.glob('/tmp/aether-monitor-*.txt'))
        report_files.extend(glob.glob('/tmp/memory-report-*.txt'))
        
        report_files.sort(key=os.path.getmtime, reverse=True)
        for report_file in report_files[:10]:  # Последние 10 отчетов
            mtime = os.path.getmtime(report_file)
            reports.append({
                'file': os.path.basename(report_file),
                'time': subprocess.run(['date', '-d', f'@{mtime}', '+%d.%m.%Y %H:%M'], 
                                     capture_output=True, text=True).stdout.strip()
            })
    except Exception as e:
        logger.error(f"Ошибка получения отчетов: {e}")
    
    monitor_data = {
        'temperature': temp_celsius,
        'disk_usage': disk_usage,
        'memory_usage': memory_usage,
        'service_status': service_status,
        'reports': reports
    }
    
    return render_template('monitor.html', **monitor_data)

@app.route("/api/monitor")
def api_monitor():
    """API для получения данных мониторинга в JSON формате"""
    import subprocess
    import glob
    import os
    
    # Получаем текущие параметры системы (повторяем логику из monitor_page)
    try:
        # Температура CPU
        temp_result = subprocess.run(['cat', '/sys/class/thermal/thermal_zone0/temp'], capture_output=True, text=True)
        temp_celsius = float(temp_result.stdout.strip()) / 1000 if temp_result.returncode == 0 else 0
        
        # Использование диска
        disk_result = subprocess.run(['df', '-h', '/'], capture_output=True, text=True)
        disk_usage = "Неизвестно"
        if disk_result.returncode == 0:
            lines = disk_result.stdout.strip().split('\n')
            if len(lines) > 1:
                disk_usage = lines[1].split()[4]  # Процент использования
        
        # Использование память
        mem_result = subprocess.run(['free', '-m'], capture_output=True, text=True)
        memory_usage = "Неизвестно"
        if mem_result.returncode == 0:
            lines = mem_result.stdout.strip().split('\n')
            if len(lines) > 1:
                mem_data = lines[1].split()
                total_mem = int(mem_data[1])
                used_mem = int(mem_data[2])
                memory_usage = f"{round(used_mem/total_mem*100, 1)}%"
        
        # Статус сервиса
        service_status = "Работает (ручной запуск)"
        try:
            service_result = subprocess.run(['systemctl', 'is-active', 'aether-player.service'], 
                                          capture_output=True, text=True)
            if service_result.returncode == 0 and service_result.stdout.strip() == 'active':
                service_status = "Работает (systemd)"
            elif service_result.returncode != 0 and service_result.stdout.strip() in ['inactive', 'failed']:
                # Сервис настроен, но неактивен - приложение запущено вручную
                service_status = "Работает (ручной запуск)"
            else:
                service_status = "Остановлен"
        except:
            pass  # Сервис не настроен, остается "Работает (ручной запуск)"
            
    except Exception as e:
        logger.error(f"Ошибка получения данных мониторинга: {e}")
        temp_celsius = 0
        disk_usage = "Ошибка"
        memory_usage = "Ошибка"
        service_status = "Ошибка"
    
    # Получаем последние отчеты
    reports = []
    try:
        # Собираем отчеты мониторинга и памяти
        report_files = []
        report_files.extend(glob.glob('/tmp/aether-monitor-*.txt'))
        report_files.extend(glob.glob('/tmp/memory-report-*.txt'))
        
        report_files.sort(key=os.path.getmtime, reverse=True)
        for report_file in report_files[:10]:  # Последние 10 отчетов
            mtime = os.path.getmtime(report_file)
            reports.append({
                'file': os.path.basename(report_file),
                'time': subprocess.run(['date', '-d', f'@{mtime}', '+%d.%m.%Y %H:%M'], 
                                     capture_output=True, text=True).stdout.strip()
            })
    except Exception as e:
        logger.error(f"Ошибка получения отчетов: {e}")
    
    # Получаем статус питания периферии
    power_status = get_power_status()
    
    monitor_data = {
        'temperature': temp_celsius,
        'disk_usage': disk_usage,
        'memory_usage': memory_usage,
        'service_status': service_status,
        'power_status': power_status,
        'reports': reports
    }
    
    return jsonify(monitor_data)

@app.route("/monitor/report/<filename>")
def view_report(filename):
    """Просмотр конкретного отчета"""
    import os
    
    # Проверяем безопасность имени файла
    # Разрешаем файлы, которые начинаются с aether-monitor- или memory-report- и заканчиваются на .txt
    if not ((filename.startswith('aether-monitor-') or filename.startswith('memory-report-')) and 
            filename.endswith('.txt')) or '..' in filename:
        return "Недопустимое имя файла", 400
    
    report_path = f'/tmp/{filename}'
    if not os.path.exists(report_path):
        return "Отчет не найден", 404
    
    try:
        with open(report_path, 'r', encoding='utf-8') as f:
            content = f.read()
        return f"<pre style='font-family: monospace; background: #f5f5f5; padding: 20px;'>{content}</pre>"
    except Exception as e:
        return f"Ошибка чтения отчета: {e}", 500

@app.route("/api/memory-analysis", methods=['POST'])
def memory_analysis():
    """Запуск детального анализа памяти"""
    # Генерируем отчет о памяти
    logger.info("Запуск анализа памяти")
    try:
        import subprocess
        result = subprocess.run(
            ['python3', '/home/eu/aether-player/memory-monitor.py', '--save'], 
            capture_output=True, text=True, timeout=10
        )
        
        logger.info(f"Результат выполнения скрипта: returncode={result.returncode}")
        logger.info(f"stdout: {result.stdout}")
        logger.info(f"stderr: {result.stderr}")
        
        if result.returncode == 0:
            output = result.stdout.strip()
            if 'Отчет сохранен:' in output:
                filename = output.split('Отчет сохранен: ')[1].strip()
                return jsonify({
                    'status': 'success', 
                    'message': 'Отчет о памяти создан',
                    'report_path': filename
                })
            else:
                logger.warning(f"Неожиданный вывод скрипта: {output}")
                return jsonify({'status': 'error', 'error': 'Ошибка создания отчета'})
        else:
            logger.error(f"Ошибка выполнения скрипта: returncode={result.returncode}, stderr={result.stderr}")
            return jsonify({'status': 'error', 'error': f'Ошибка выполнения анализа памяти: {result.stderr}'})
    except Exception as e:
        logger.error(f"Исключение при выполнении анализа памяти: {e}")
        return jsonify({'status': 'error', 'error': f'Ошибка: {str(e)}'})

# ===== API для управления виртуальной стереосценой =====

@app.route("/api/audio-enhancement/presets", methods=['GET'])
def get_audio_enhancement_presets():
    """Получить список всех предустановок виртуальной стереосцены"""
    try:
        presets = audio_enhancer.get_all_presets()
        current_preset = player_state.get('audio_enhancement', 'off')
        
        return jsonify({
            'status': 'success',
            'presets': presets,
            'current': current_preset,
            'custom_settings': audio_enhancer.get_custom_settings()
        })
    except Exception as e:
        logger.error(f"Ошибка получения предустановок: {e}")
        return jsonify({'status': 'error', 'error': str(e)})

@app.route("/api/audio-enhancement/apply", methods=['POST'])
def apply_audio_enhancement_api():
    """Применить предустановку виртуальной стереосцены"""
    try:
        preset_name = request.json.get('preset', 'off')
        
        if preset_name not in audio_enhancer.PRESETS:
            return jsonify({'status': 'error', 'error': 'Неизвестная предустановка'})
        
        success = apply_audio_enhancement(preset_name)
        
        if success:
            preset_info = audio_enhancer.get_preset_info(preset_name)
            # Проверяем, воспроизводится ли что-то
            is_playing = player_state.get('status') in ['playing', 'paused']
            
            if is_playing:
                message = f'Применена предустановка: {preset_info["name"]}'
            else:
                message = f'Предустановка "{preset_info["name"]}" сохранена и будет применена при воспроизведении'
            
            # Отправляем обновление всем подключенным клиентам
            if socketio:
                socketio.emit('audio_enhancement_changed', {
                    'preset': preset_name,
                    'preset_info': preset_info
                })
            
            return jsonify({
                'status': 'success',
                'message': message,
                'preset': preset_name,
                'preset_info': preset_info,
                'applied_immediately': is_playing
            })
        else:
            return jsonify({'status': 'error', 'error': 'Ошибка применения фильтров'})
            
    except Exception as e:
        logger.error(f"Ошибка применения аудио-улучшений: {e}")
        return jsonify({'status': 'error', 'error': str(e)})

@app.route("/api/audio-enhancement/custom", methods=['POST'])
def update_custom_audio_enhancement():
    """Обновить пользовательские настройки аудио-улучшений"""
    try:
        settings = request.json.get('settings', {})
        
        updated = False
        for setting_name, value in settings.items():
            if audio_enhancer.update_custom_setting(setting_name, value):
                updated = True
        
        if updated:
            # Если активна пользовательская предустановка, применяем изменения
            if player_state.get('audio_enhancement') == 'custom':
                apply_audio_enhancement('custom')
            
            return jsonify({
                'status': 'success',
                'message': 'Пользовательские настройки обновлены',
                'custom_settings': audio_enhancer.get_custom_settings()
            })
        else:
            return jsonify({'status': 'error', 'error': 'Не удалось обновить настройки'})
            
    except Exception as e:
        logger.error(f"Ошибка обновления пользовательских настроек: {e}")
        return jsonify({'status': 'error', 'error': str(e)})

@app.route("/api/audio-enhancement/info/<preset_name>", methods=['GET'])
def get_audio_enhancement_info(preset_name):
    """Получить детальную информацию о предустановке"""
    try:
        if preset_name not in audio_enhancer.PRESETS:
            return jsonify({'status': 'error', 'error': 'Неизвестная предустановка'})
        
        preset_info = audio_enhancer.get_preset_info(preset_name)
        filters = audio_enhancer.get_filter_chain(preset_name)
        
        from audio_enhancement import EFFECT_EXPLANATIONS
        
        return jsonify({
            'status': 'success',
            'preset_info': preset_info,
            'filters': filters,
            'explanations': EFFECT_EXPLANATIONS
        })
        
    except Exception as e:
        logger.error(f"Ошибка получения информации о предустановке: {e}")
        return jsonify({'status': 'error', 'error': str(e)})

@app.route("/system/shutdown", methods=['POST'])
def system_shutdown():
    """Безопасное отключение Raspberry Pi"""
    action = request.form.get('action', 'shutdown')
    
    if action == 'shutdown':
        logger.info("Запрос безопасного отключения системы")
        # Останавливаем плеер
        stop_mpv_internal()
        # Синхронизируем файловую систему
        isolated_run(['sync'], check=False)
        # Размонтируем внешний диск
        isolated_run(['sudo', 'umount', '/mnt/hdd'], check=False)
        # Запускаем отключение через 1 минуту
        isolated_run(['sudo', 'shutdown', '-h', '+1'], check=False)
        return jsonify({'status': 'ok', 'message': 'Система будет отключена через 1 минуту'})
    
    elif action == 'reboot':
        logger.info("Запрос перезагрузки системы")
        # Останавливаем плеер
        stop_mpv_internal()
        # Синхронизируем файловую систему
        isolated_run(['sync'], check=False)
        # Запускаем перезагрузку через 30 секунд
        isolated_run(['sudo', 'shutdown', '-r', '+1'], check=False)
        return jsonify({'status': 'ok', 'message': 'Система будет перезагружена через 1 минуту'})
    
    elif action == 'umount_hdd':
        logger.info("Размонтирование внешнего диска")
        # Останавливаем плеер
        stop_mpv_internal()
        # Синхронизируем данные
        isolated_run(['sync'], check=False)
        # Размонтируем диск
        result = isolated_run(['sudo', 'umount', '/mnt/hdd'], check=False)
        if result.get('returncode') == 0:
            return jsonify({'status': 'ok', 'message': 'Внешний диск безопасно отключен'})
        else:
            return jsonify({'status': 'error', 'message': 'Ошибка отключения диска'})
    
    else:
        return jsonify({'status': 'error', 'message': 'Неизвестное действие'}), 400

@app.route("/system/power", methods=['POST'])
def system_power():
    """Управление питанием периферии"""
    action = request.form.get('action', '')
    
    if action == 'on':
        logger.info("Включение питания периферии")
        result = isolated_run(['python3', '/home/eu/aether-player/power-control.py', 'on'], check=False)
        if result.get('returncode') == 0:
            return jsonify({'status': 'ok', 'message': 'Питание периферии включено'})
        else:
            return jsonify({'status': 'error', 'message': 'Ошибка включения питания'})
    
    elif action == 'off':
        logger.info("Выключение питания периферии")
        result = isolated_run(['python3', '/home/eu/aether-player/power-control.py', 'safe-off'], check=False)
        if result.get('returncode') == 0:
            return jsonify({'status': 'ok', 'message': 'Питание периферии безопасно выключено'})
        else:
            return jsonify({'status': 'error', 'message': 'Ошибка выключения питания'})
    
    elif action == 'status':
        power_status = get_power_status()
        return jsonify({'status': 'ok', 'power_status': power_status})
    
    else:
        return jsonify({'status': 'error', 'message': 'Неизвестное действие'}), 400

@app.route("/system/cancel-shutdown", methods=['POST'])
def cancel_shutdown():
    """Отмена запланированного отключения"""
    logger.info("Отмена запланированного отключения")
    isolated_run(['sudo', 'shutdown', '-c'], check=False)
    return jsonify({'status': 'ok', 'message': 'Отключение отменено'})

# WebSocket обработчики
if socketio:
    @socketio.on('connect')
    def handle_connect():
        logger.info('Клиент подключился')
        emit_status_update()

# Запуск сервера
if __name__ == "__main__":
    logger.info("Запуск Aether Player (простая архитектура)")
    
    # Восстанавливаем ALSA
    try:
        isolated_run(["sudo", "alsactl", "restore"], check=True)
        logger.info("ALSA восстановлено")
    except Exception as e:
        logger.error(f"Ошибка восстановления ALSA: {e}")
    
    # Запускаем MPV
    ensure_mpv_is_running()
    
    # Фоновая задача отключена - используем HTTP-механизм обновления
    # socketio.start_background_task(target=status_update_task)
    
    # Запускаем сервер
    logger.info("Запуск веб-сервера на порту 5000")
    if socketio:
        socketio.run(app, host='0.0.0.0', port=5000, debug=False, allow_unsafe_werkzeug=True)
    else:
        app.run(host='0.0.0.0', port=5000, debug=False)
