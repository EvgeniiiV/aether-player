#!/usr/bin/env python3
"""
Простой тест CUE парсера с исправлением многофайловых CUE
"""

import subprocess
import json
import os
import re

def get_duration(file_path):
    """Получает длительность файла"""
    try:
        result = subprocess.run([
            'ffprobe', '-v', 'quiet', '-print_format', 'json', 
            '-show_format', file_path
        ], capture_output=True, text=True, timeout=30)
        
        if result.returncode == 0:
            data = json.loads(result.stdout)
            duration = data.get('format', {}).get('duration')
            if duration:
                return float(duration)
    except Exception as e:
        print(f"Ошибка получения длительности: {e}")
    return None

def parse_time(time_str):
    """Парсит время в формате mm:ss:ff в секунды"""
    if not time_str:
        return 0.0
    try:
        parts = time_str.split(':')
        if len(parts) == 3:
            minutes = int(parts[0])
            seconds = int(parts[1])
            frames = int(parts[2])  # 75 кадров = 1 секунда
            return minutes * 60 + seconds + frames / 75.0
    except:
        pass
    return 0.0

def test_cue_parser():
    """Тестируем исправление CUE"""
    cue_file = "/mnt/hdd/MUSIC/ELO/ELO – Time [LP] - 1981 (lossless)/03. ELO – Time (1981).cue"
    cue_dir = os.path.dirname(cue_file)
    
    # Читаем CUE файл
    encodings = ['utf-8', 'windows-1251', 'iso-8859-1', 'cp1252']
    content = None
    
    for encoding in encodings:
        try:
            with open(cue_file, 'r', encoding=encoding) as f:
                content = f.read()
                print(f"Файл прочитан в кодировке: {encoding}")
                break
        except UnicodeDecodeError:
            continue
    
    if not content:
        print("Не удалось прочитать файл")
        return
    
    print("=== ИСХОДНЫЕ ДАННЫЕ ===")
    
    # Находим файлы и их длительности
    file_durations = {}
    files = ["01. Side 1.flac", "02. Side 2.flac"]
    
    for file in files:
        file_path = os.path.join(cue_dir, file)
        duration = get_duration(file_path)
        file_durations[file] = duration
        print(f"{file}: {duration:.1f}s ({duration/60:.1f} мин)")
    
    # Парсим треки
    tracks = []
    current_file = None
    track_num = 0
    
    for line in content.split('\n'):
        line = line.strip()
        
        if line.startswith('FILE '):
            match = re.match(r'FILE\s+"([^"]+)"', line)
            if match:
                current_file = match.group(1)
        
        elif 'TRACK ' in line and 'AUDIO' in line:
            track_num += 1
            
        elif line.startswith('TITLE ') and track_num > 0:
            match = re.match(r'TITLE\s+"([^"]+)"', line)
            if match:
                title = match.group(1)
                tracks.append({
                    'number': track_num,
                    'title': title,
                    'file': current_file,
                    'index': None
                })
        
        elif line.startswith('INDEX 01'):
            match = re.match(r'INDEX\s+01\s+([\d:]+)', line)
            if match and tracks:
                tracks[-1]['index'] = match.group(1)
    
    print(f"\n=== НАЙДЕНО ТРЕКОВ: {len(tracks)} ===")
    
    # Вычисляем абсолютные времена
    file_offset = 0.0
    current_file = None
    
    print("\n=== ПРАВИЛЬНЫЕ АБСОЛЮТНЫЕ ВРЕМЕНА ===")
    
    for track in tracks:
        # Если началась новая сторона
        if track['file'] != current_file:
            if current_file is not None:
                # Добавляем длительность предыдущего файла к смещению
                prev_duration = file_durations.get(current_file, 0)
                file_offset += prev_duration
                print(f"[Переход к файлу {track['file']}, смещение: {file_offset:.1f}s]")
            current_file = track['file']
        
        # Вычисляем абсолютное время
        relative_time = parse_time(track['index'])
        absolute_time = file_offset + relative_time
        
        mins = int(absolute_time // 60)
        secs = int(absolute_time % 60)
        
        print(f"Track {track['number']:02d}: {track['title']} [{mins:02d}:{secs:02d}] ({absolute_time:.1f}s)")

if __name__ == "__main__":
    test_cue_parser()
