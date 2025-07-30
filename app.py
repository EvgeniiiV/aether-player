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
MPV_SOCKET = "/tmp/mpvsocket"
MEDIA_EXTENSIONS = ['.flac', '.wav', '.wv', '.dsf', '.dff', '.mp3', '.aac', '.ogg', '.m4a', 
                   '.mkv', '.mp4', '.avi', '.mov', '.wmv', '.flv', '.webm', 
                   '.jpg', '.jpeg', '.png', '.bmp', '.gif', '.tiff']

def get_file_type(filepath):
    """Определяет тип медиафайла"""
    ext = os.path.splitext(filepath)[1].lower()
    
    audio_extensions = ['.flac', '.wav', '.wv', '.mp3', '.aac', '.ogg', '.m4a']
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
            cards = f.read()
        
        # Приоритет устройств (от лучшего к худшему)
        audio_priorities = [
            ('Scarlett', 'alsa/hw:1,0'),  # Focusrite Scarlett 2i2
            ('USB', 'alsa/hw:1,0'),       # Любое USB аудио
            ('vc4hdmi0', 'alsa/hw:2,0'),  # HDMI выход 1
            ('Headphones', 'alsa/hw:0,0') # Встроенный 3.5mm
        ]
        
        for device_name, alsa_device in audio_priorities:
            if device_name in cards:
                logger.info(f"Выбрано аудио устройство: {device_name} ({alsa_device})")
                return alsa_device
        
        # Если ничего не найдено, используем по умолчанию
        logger.warning("Не удалось определить аудио устройство, используем по умолчанию")
        return "auto"
        
    except Exception as e:
        logger.error(f"Ошибка определения аудио устройства: {e}")
        return "auto"

# Глобальные переменные
player_process = None
last_position_update = time.time()

# Состояние плеера
player_state = {
    'status': 'stopped',
    'track': '',
    'position': 0.0,
    'duration': 0.0,
    'volume': 100,
    'playlist': [],
    'playlist_index': -1
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
        
        # Запускаем MPV с оптимальными настройками аудио и видео
        audio_device = get_best_audio_device()
        command = [
            "mpv", 
            "--idle", 
            f"--input-ipc-server={MPV_SOCKET}", 
            "--fs",                            # Полноэкранный режим
            "--geometry=100%:100%",            # Растянуть на весь экран
            "--osd-level=1",                   # Минимальный OSD
            "--really-quiet",                  # Убираем лишние сообщения
            f"--audio-device={audio_device}",  # Автоматически определенное устройство
            "--volume=80",                     # Начальная громкость 80%
            "--audio-channels=stereo",         # Стерео режим
            "--audio-samplerate=48000",        # Высокое качество звука
            "--hwdec=auto-safe",               # Безопасное аппаратное декодирование
            "--vo=gpu,drm,fbdev",              # Варианты видео вывода (по приоритету)
            "--profile=sw-fast"                # Профиль для программного декодирования
        ]
        from subprocess import DEVNULL
        mpv_pid = isolated_popen(command, stdout=DEVNULL, stderr=DEVNULL)
        
        # Создаем обёртку процесса
        class DummyProcess:
            def __init__(self, pid):
                self.pid = pid
            
            def poll(self):
                try:
                    os.kill(self.pid, 0)
                    return None
                except ProcessLookupError:
                    return 1
                except:
                    return 1
            
            def kill(self):
                try:
                    os.kill(self.pid, 9)  # SIGKILL
                except:
                    pass
        
        player_process = DummyProcess(mpv_pid)
        
        # Ждём создания сокета
        for _ in range(15):  # 3 секунды
            if os.path.exists(MPV_SOCKET):
                break
            time.sleep(0.2)
        
        time.sleep(0.5)
        logger.info("MPV запущен")

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
        
        # Получаем duration
        raw_duration = None
        for _ in range(5):  # Исправлено: используем _ вместо неиспользуемой переменной attempt
            raw_duration = get_mpv_property("duration")
            if raw_duration and raw_duration > 0:
                break
            time.sleep(0.2)
        
        if not raw_duration:
            raw_duration = 100.0
            logger.warning(f"Не удалось получить duration для {filepath}, используем {raw_duration}")
        
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
        'volume': player_state['volume']
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
    
    # Дополнительные настройки для видео
    if file_type == 'video':
        logger.info(f"Воспроизведение видео: {os.path.basename(full_path)}")
        # Включаем полноэкранный режим для видео
        mpv_command({"command": ["set_property", "fullscreen", True]})
    else:
        logger.info(f"Воспроизведение аудио: {os.path.basename(full_path)}")
    
    # СИНХРОНИЗАЦИЯ С MPV - получаем duration и volume
    time.sleep(0.5)
    
    # Получаем duration
    raw_duration = None
    for _ in range(5):  # Исправлено: используем _ вместо неиспользуемой переменной attempt
        raw_duration = get_mpv_property("duration")
        if raw_duration and raw_duration > 0:
            break
        time.sleep(0.2)
    
    if not raw_duration:
        raw_duration = 100.0
        logger.warning(f"Не удалось получить duration, используем {raw_duration}")
    
    volume = get_mpv_property("volume") or 100
    
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
        'volume': volume,
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
    """Установка громкости"""
    volume = request.form.get('volume', 100, type=int)
    mpv_command({"command": ["set_property", "volume", volume]})
    player_state['volume'] = volume
    return jsonify({'status': 'ok'})

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
            else:
                service_status = "Остановлен"
        except:
            pass  # Сервис не настроен
            
    except Exception as e:
        logger.error(f"Ошибка получения данных мониторинга: {e}")
        temp_celsius = 0
        disk_usage = "Ошибка"
        memory_usage = "Ошибка"
        service_status = "Ошибка"
    
    # Получаем последние отчеты
    reports = []
    try:
        report_files = glob.glob('/tmp/aether-monitor-*.txt')
        report_files.sort(key=os.path.getmtime, reverse=True)
        for report_file in report_files[:5]:  # Последние 5 отчетов
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
            else:
                service_status = "Остановлен"
        except:
            pass  # Сервис не настроен
            
    except Exception as e:
        logger.error(f"Ошибка получения данных мониторинга: {e}")
        temp_celsius = 0
        disk_usage = "Ошибка"
        memory_usage = "Ошибка"
        service_status = "Ошибка"
    
    # Получаем последние отчеты
    reports = []
    try:
        report_files = glob.glob('/tmp/aether-monitor-*.txt')
        report_files.sort(key=os.path.getmtime, reverse=True)
        for report_file in report_files[:5]:  # Последние 5 отчетов
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
    
    return jsonify(monitor_data)

@app.route("/monitor/report/<filename>")
def view_report(filename):
    """Просмотр конкретного отчета"""
    import os
    
    # Проверяем безопасность имени файла
    if not filename.startswith('aether-monitor-') or '..' in filename:
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
        socketio.run(app, host='0.0.0.0', port=5000, debug=False)
    else:
        app.run(host='0.0.0.0', port=5000, debug=False)
