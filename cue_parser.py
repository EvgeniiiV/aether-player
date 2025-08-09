"""
CUE File Parser для Aether Player
Парсит CUE-файлы и извлекает информацию о треках

UPDATED: 2025-08-09 v2 - исправлена проблема с многофайловыми CUE
"""

import re
import os
import subprocess
import json
from typing import Dict, List, Optional, Tuple

def get_audio_file_duration(file_path: str) -> Optional[float]:
    """Получает длительность аудиофайла через ffprobe в секундах"""
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
        print(f"Ошибка получения длительности файла {file_path}: {e}")
    return None

class CueTrack:
    """Представляет один трек в CUE файле"""
    
    def __init__(self):
        self.number = 0
        self.title = ""
        self.performer = ""
        self.index = ""  # Время в формате mm:ss:ff
        self.file = ""
        self.absolute_time_seconds = 0.0  # Абсолютное время с учетом многофайловых CUE
    
    def get_time_seconds(self) -> float:
        """Возвращает абсолютное время трека в секундах"""
        return self.absolute_time_seconds
    
    def get_time_display(self) -> str:
        """Возвращает время в читаемом формате для отображения"""
        total_seconds = int(self.absolute_time_seconds)
        hours = total_seconds // 3600
        minutes = (total_seconds % 3600) // 60
        seconds = total_seconds % 60
        
        if hours > 0:
            return f"{hours:02d}:{minutes:02d}:{seconds:02d}"
        else:
            return f"{minutes:02d}:{seconds:02d}"
    
    def parse_index_to_seconds(self) -> float:
        """Конвертирует INDEX в секунды (относительно начала файла)"""
        if not self.index:
            return 0.0
        
        try:
            parts = self.index.split(':')
            if len(parts) == 3:
                minutes = int(parts[0])
                seconds = int(parts[1])
                frames = int(parts[2])  # 75 кадров = 1 секунда
                return minutes * 60 + seconds + frames / 75.0
            return 0.0
        except (ValueError, IndexError):
            return 0.0
    
    def __str__(self):
        return f"Track {self.number:02d}: {self.title} [{self.get_time_display()}]"

class CueSheet:
    """Представляет весь CUE файл"""
    
    def __init__(self):
        self.performer = ""
        self.title = ""
        self.genre = ""
        self.date = ""
        self.comment = ""
        self.tracks: List[CueTrack] = []
        self.files: Dict[str, List[CueTrack]] = {}
    
    def add_track(self, track: CueTrack):
        """Добавляет трек в CUE с автоматической перенумерацией"""
        # Назначаем последовательный номер трека независимо от CUE
        track.number = len(self.tracks) + 1
        
        self.tracks.append(track)
        if track.file not in self.files:
            self.files[track.file] = []
        self.files[track.file].append(track)
    
    def calculate_absolute_times(self, cue_dir: str):
        """Вычисляет абсолютные времена для всех треков с учетом многофайловых CUE"""
        if not self.tracks:
            return
            
        file_offset = 0.0  # Смещение для следующего файла
        current_file = None
        
        for track in self.tracks:
            # Если началась новая сторона/файл
            if track.file != current_file:
                if current_file is not None:
                    # Получаем длительность предыдущего файла и добавляем к смещению
                    prev_file_path = os.path.join(cue_dir, current_file)
                    duration = get_audio_file_duration(prev_file_path)
                    if duration:
                        file_offset += duration
                        print(f"Файл {current_file}: длительность {duration:.1f}s, общее смещение: {file_offset:.1f}s")
                    else:
                        print(f"Не удалось получить длительность файла {current_file}")
                
                current_file = track.file
            
            # Вычисляем абсолютное время
            relative_time = track.parse_index_to_seconds()
            track.absolute_time_seconds = file_offset + relative_time
    
    def get_duration_for_track(self, track_num: int) -> Optional[float]:
        """Вычисляет длительность трека"""
        if track_num < 1 or track_num > len(self.tracks):
            return None
            
        current_track = self.tracks[track_num - 1]
        
        # Для последнего трека длительность неизвестна
        if track_num == len(self.tracks):
            return None
        
        next_track = self.tracks[track_num]
        return next_track.absolute_time_seconds - current_track.absolute_time_seconds
    
    def __repr__(self):
        return f"CUE: {self.performer} - {self.title} ({len(self.tracks)} tracks)"

def parse_cue_file(file_path: str) -> Optional[CueSheet]:
    """Парсит CUE файл и возвращает CueSheet"""
    if not os.path.exists(file_path):
        return None
        
    try:
        cue = CueSheet()
        current_track = None
        current_file = None
        cue_dir = os.path.dirname(file_path)
        
        # Пробуем разные кодировки
        content = None
        encodings = ['utf-8', 'windows-1251', 'iso-8859-1', 'cp1252']
        
        for encoding in encodings:
            try:
                with open(file_path, 'r', encoding=encoding) as f:
                    content = f.read()
                    break
            except UnicodeDecodeError:
                continue
        
        if not content:
            return None
        
        # Нормализуем переводы строк
        content = content.replace('\r\n', '\n').replace('\r', '\n')
        lines = content.split('\n')
        
        for line in lines:
            line = line.strip()
            if not line:
                continue
            
            # Глобальная информация об альбоме
            if line.startswith('PERFORMER '):
                match = re.match(r'PERFORMER\s+"([^"]+)"', line)
                if match:
                    if current_track:
                        current_track.performer = match.group(1)
                    else:
                        cue.performer = match.group(1)
                        
            elif line.startswith('TITLE '):
                match = re.match(r'TITLE\s+"([^"]+)"', line)
                if match:
                    if current_track:
                        current_track.title = match.group(1)
                    else:
                        cue.title = match.group(1)
                        
            elif line.startswith('REM GENRE '):
                match = re.match(r'REM GENRE\s+"([^"]+)"', line)
                if match:
                    cue.genre = match.group(1)
                    
            elif line.startswith('REM DATE '):
                match = re.match(r'REM DATE\s+"([^"]+)"', line)
                if match:
                    cue.date = match.group(1)
                    
            elif line.startswith('REM COMMENT '):
                match = re.match(r'REM COMMENT\s+"([^"]+)"', line)
                if match:
                    cue.comment = match.group(1)
                    
            # Информация о файлах
            elif line.startswith('FILE '):
                match = re.match(r'FILE\s+"([^"]+)"\s+(\w+)', line)
                if match:
                    current_file = match.group(1)
                    
            # Информация о треках
            elif 'TRACK ' in line and 'AUDIO' in line:
                match = re.match(r'\s*TRACK\s+(\d+)\s+AUDIO', line)
                if match:
                    # Сохраняем предыдущий трек
                    if current_track:
                        cue.add_track(current_track)
                    
                    # Создаем новый трек (номер будет назначен автоматически в add_track)
                    current_track = CueTrack()
                    current_track.file = current_file
                    
            elif 'INDEX ' in line:
                match = re.match(r'\s*INDEX\s+01\s+([\d:]+)', line)
                if match and current_track:
                    current_track.index = match.group(1)
        
        # Добавляем последний трек
        if current_track:
            cue.add_track(current_track)
        
        # Наследуем performer от альбома если у треков нет своего
        for track in cue.tracks:
            if not track.performer:
                track.performer = cue.performer
        
        # Вычисляем абсолютные времена с учетом многофайловых CUE
        cue.calculate_absolute_times(cue_dir)
        
        return cue if cue.tracks else None
        
    except Exception as e:
        print(f"Ошибка парсинга CUE файла {file_path}: {e}")
        import traceback
        traceback.print_exc()
        return None

def find_audio_file_for_cue(cue_path: str, referenced_file: str) -> Optional[str]:
    """
    Находит соответствующий аудиофайл для CUE
    """
    cue_dir = os.path.dirname(cue_path)
    
    # Прямой поиск файла как указано в CUE
    direct_path = os.path.join(cue_dir, referenced_file)
    if os.path.exists(direct_path):
        return direct_path
    
    # Поиск файла без учета расширения
    base_name = os.path.splitext(referenced_file)[0]
    audio_extensions = ['.flac', '.wav', '.ape', '.wv', '.mp3', '.m4a', '.ogg']
    
    for ext in audio_extensions:
        test_path = os.path.join(cue_dir, base_name + ext)
        if os.path.exists(test_path):
            return test_path
    
    # Поиск любого аудиофайла в директории с похожим именем
    try:
        files = os.listdir(cue_dir)
        for file in files:
            if any(file.lower().endswith(ext) for ext in audio_extensions):
                file_base = os.path.splitext(file)[0].lower()
                if base_name.lower() in file_base or file_base in base_name.lower():
                    return os.path.join(cue_dir, file)
    except OSError:
        pass
    
    return None

class CueParser:
    """Главный класс для работы с CUE файлами"""
    
    def __init__(self, cue_path: str):
        self.cue_path = cue_path
        self.cue_sheet = parse_cue_file(cue_path)
    
    def get_info(self) -> Dict:
        """Возвращает информацию о CUE в удобном формате"""
        if not self.cue_sheet:
            return {
                'title': None,
                'performer': None,
                'genre': None,
                'date': None,
                'comment': None,
                'file': None,
                'tracks': []
            }
        
        # Находим первый аудиофайл
        audio_file = None
        if self.cue_sheet.files:
            first_file = list(self.cue_sheet.files.keys())[0]
            audio_file = find_audio_file_for_cue(self.cue_path, first_file)
            if audio_file:
                audio_file = os.path.basename(audio_file)
        
        tracks = []
        for track in self.cue_sheet.tracks:
            tracks.append({
                'number': track.number,
                'title': track.title,
                'performer': track.performer,
                'start_time': track.get_time_display(),
                'start_time_seconds': track.get_time_seconds(),
                'file': track.file,  # Добавляем информацию о файле для каждого трека
                'relative_time_seconds': track.parse_index_to_seconds()  # Относительное время в файле
            })
        
        return {
            'title': self.cue_sheet.title,
            'performer': self.cue_sheet.performer,
            'genre': self.cue_sheet.genre,
            'date': self.cue_sheet.date,
            'comment': self.cue_sheet.comment,
            'file': audio_file,
            'tracks': tracks
        }
    
    def get_track_count(self) -> int:
        """Возвращает количество треков"""
        return len(self.cue_sheet.tracks) if self.cue_sheet else 0
    
    def print_info(self):
        """Выводит информацию о CUE на экран"""
        if not self.cue_sheet:
            print("CUE файл не найден или поврежден")
            return
            
        print(repr(self.cue_sheet))
        for track in self.cue_sheet.tracks:
            print(f"  {track}")

# Тестирование
if __name__ == "__main__":
    import sys
    
    if len(sys.argv) > 1:
        cue_path = sys.argv[1]
        parser = CueParser(cue_path)
        parser.print_info()
    else:
        print("Использование: python cue_parser.py <путь_к_cue_файлу>")
