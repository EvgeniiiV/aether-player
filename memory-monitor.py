#!/usr/bin/env python3
"""
Скрипт мониторинга памяти для Aether Player
Показывает детальную информацию о потреблении памяти
"""

import subprocess
import os
from datetime import datetime

def get_memory_info():
    """Получает информацию о памяти"""
    try:
        # Общая память
        result = subprocess.run(['free', '-m'], capture_output=True, text=True)
        lines = result.stdout.strip().split('\n')
        mem_line = lines[1].split()
        
        total_mem = int(mem_line[1])
        used_mem = int(mem_line[2])
        free_mem = int(mem_line[3])
        available_mem = int(mem_line[6])
        
        return {
            'total': total_mem,
            'used': used_mem,
            'free': free_mem,
            'available': available_mem,
            'used_percent': round(used_mem / total_mem * 100, 1)
        }
    except Exception as e:
        print(f"Ошибка получения информации о памяти: {e}")
        return None

def get_top_processes():
    """Получает топ процессов по памяти"""
    try:
        result = subprocess.run(['ps', 'aux', '--sort=-%mem'], capture_output=True, text=True)
        lines = result.stdout.strip().split('\n')[1:11]  # Топ 10
        
        processes = []
        for line in lines:
            parts = line.split(None, 10)
            if len(parts) >= 11:
                processes.append({
                    'pid': parts[1],
                    'mem_percent': float(parts[3]),
                    'mem_mb': int(float(parts[5]) / 1024),  # RSS в MB
                    'command': parts[10][:60]  # Обрезаем длинные команды
                })
        
        return processes
    except Exception as e:
        print(f"Ошибка получения процессов: {e}")
        return []

def get_aether_processes():
    """Получает процессы, связанные с Aether Player"""
    try:
        result = subprocess.run(['ps', 'aux'], capture_output=True, text=True)
        lines = result.stdout.strip().split('\n')
        
        aether_processes = []
        for line in lines:
            if any(keyword in line.lower() for keyword in ['app.py', 'mpv', 'python3']):
                if 'grep' not in line and ('aether' in line or 'mpv' in line):
                    parts = line.split(None, 10)
                    if len(parts) >= 11:
                        aether_processes.append({
                            'pid': parts[1],
                            'mem_percent': float(parts[3]),
                            'mem_mb': int(float(parts[5]) / 1024),
                            'command': parts[10][:80]
                        })
        
        return aether_processes
    except Exception as e:
        print(f"Ошибка получения Aether процессов: {e}")
        return []

def format_memory_report():
    """Форматирует отчет о памяти"""
    timestamp = datetime.now().strftime("%d.%m.%Y %H:%M:%S")
    
    # Заголовок
    report = f"\n{'='*80}\n"
    report += f"ОТЧЕТ О ПАМЯТИ AETHER PLAYER - {timestamp}\n"
    report += f"{'='*80}\n\n"
    
    # Общая информация о памяти
    mem_info = get_memory_info()
    if mem_info:
        report += f"📊 ОБЩАЯ ПАМЯТЬ:\n"
        report += f"   Всего:     {mem_info['total']:4d} MB\n"
        report += f"   Используется: {mem_info['used']:4d} MB ({mem_info['used_percent']:5.1f}%)\n"
        report += f"   Свободно:  {mem_info['free']:4d} MB\n"
        report += f"   Доступно:  {mem_info['available']:4d} MB\n\n"
        
        # Предупреждения
        if mem_info['used_percent'] > 85:
            report += f"⚠️  КРИТИЧЕСКОЕ использование памяти: {mem_info['used_percent']}%\n\n"
        elif mem_info['used_percent'] > 75:
            report += f"⚠️  Высокое использование памяти: {mem_info['used_percent']}%\n\n"
    
    # Топ процессов по памяти
    top_processes = get_top_processes()
    if top_processes:
        report += f"🔝 ТОП-10 ПРОЦЕССОВ ПО ПАМЯТИ:\n"
        report += f"{'PID':<8} {'МЕМ %':<8} {'МЕМ MB':<8} {'КОМАНДА':<60}\n"
        report += f"{'-'*8} {'-'*8} {'-'*8} {'-'*60}\n"
        
        for proc in top_processes:
            report += f"{proc['pid']:<8} {proc['mem_percent']:<8.1f} {proc['mem_mb']:<8} {proc['command']:<60}\n"
        report += "\n"
    
    # Процессы Aether Player
    aether_processes = get_aether_processes()
    if aether_processes:
        report += f"🎵 ПРОЦЕССЫ AETHER PLAYER:\n"
        report += f"{'PID':<8} {'МЕМ %':<8} {'МЕМ MB':<8} {'КОМАНДА':<80}\n"
        report += f"{'-'*8} {'-'*8} {'-'*8} {'-'*80}\n"
        
        total_aether_mem = 0
        for proc in aether_processes:
            report += f"{proc['pid']:<8} {proc['mem_percent']:<8.1f} {proc['mem_mb']:<8} {proc['command']:<80}\n"
            total_aether_mem += proc['mem_mb']
        
        report += f"\n💾 Общее потребление Aether Player: {total_aether_mem} MB\n\n"
    
    # Рекомендации
    if mem_info and mem_info['used_percent'] > 80:
        report += f"💡 РЕКОМЕНДАЦИИ:\n"
        report += f"   • Перезапустить VSCode для освобождения памяти\n"
        report += f"   • Закрыть ненужные файлы в редакторе\n"
        report += f"   • Отключить неиспользуемые расширения VSCode\n"
        report += f"   • Перезагрузить систему если память не освобождается\n\n"
    
    report += f"{'='*80}\n"
    
    return report

def main():
    """Основная функция"""
    if len(os.sys.argv) > 1 and os.sys.argv[1] == '--save':
        # Сохраняем отчет в файл
        report = format_memory_report()
        filename = f"/tmp/memory-report-{datetime.now().strftime('%Y%m%d-%H%M%S')}.txt"
        
        try:
            with open(filename, 'w', encoding='utf-8') as f:
                f.write(report)
            print(f"Отчет сохранен: {filename}")
        except Exception as e:
            print(f"Ошибка сохранения отчета: {e}")
    else:
        # Выводим в консоль
        report = format_memory_report()
        print(report)

if __name__ == "__main__":
    main()
