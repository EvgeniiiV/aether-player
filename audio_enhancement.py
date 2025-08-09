#!/usr/bin/env python3
"""
Модуль аудио-улучшений для Aether Player
Реализует виртуальную стереосцену для наушников
"""

import json
import logging
import os

logger = logging.getLogger(__name__)

class AudioEnhancement:
    """Класс для управления аудио-улучшениями"""
    
    # Предустановки виртуальной стереосцены
    PRESETS = {
        'off': {
            'name': 'Выключено',
            'description': 'Оригинальный звук без обработки',
            'filters': []
        },
        'subtle': {
            'name': 'Деликатное',
            'description': 'Легкое расширение стереосцены',
            'filters': [
                'crossfeed=strength=0.5:range=0.7',
                'volume=1.1',  # Компенсация громкости для кроссфида
                'extrastereo=m=1.6'
            ]
        },
        'natural': {
            'name': 'Естественное',
            'description': 'Имитация акустики комнаты',
            'filters': [
                'crossfeed=strength=0.5:range=0.6',
                'volume=1.1',  # Компенсация громкости для кроссфида
                'haas=level_in=1.0:level_out=1.0:side_gain=0.8',
                'extrastereo=m=1.5'
            ]
        },
        'wide': {
            'name': 'Широкое',
            'description': 'Максимальное расширение стереосцены',
            'filters': [
                'crossfeed=strength=0.7:range=0.4',
                'volume=1.15',  # Больше компенсации для сильного кроссфида
                'haas=level_in=1.0:level_out=1.2:side_gain=1.0',
                'extrastereo=m=2.0',
                'surround=chl_out=stereo:chl_in=stereo:level_in=1.0:level_out=1.1'
            ]
        },
        'speakers': {
            'name': 'Имитация колонок',
            'description': 'Максимально близко к реальным колонкам',
            'filters': [
                'crossfeed=strength=0.8:range=0.3',
                'haas=level_in=1.0:level_out=1.3:side_gain=1.2',
                'extrastereo=m=2.5',
                'surround=chl_out=stereo:chl_in=stereo:level_in=1.0:level_out=1.2'
            ]
        },
        'custom': {
            'name': 'Пользовательское',
            'description': 'Настраиваемые параметры',
            'filters': []  # Будет заполнено пользователем
        }
    }
    
    def __init__(self):
        self.current_preset = 'off'
        self.custom_settings = {
            'crossfeed_strength': 0.5,
            'crossfeed_range': 0.6,
            'haas_level_out': 1.0,
            'haas_side_gain': 0.8,
            'extrastereo_multiplier': 1.5,
            'surround_level_out': 1.0
        }
        
    def get_filter_chain(self, preset_name='off'):
        """Получает цепочку фильтров для заданной предустановки"""
        if preset_name not in self.PRESETS:
            preset_name = 'off'
            
        preset = self.PRESETS[preset_name]
        
        if preset_name == 'custom':
            return self._build_custom_filters()
        
        return preset['filters']
    
    def _build_custom_filters(self):
        """Строит пользовательскую цепочку фильтров"""
        filters = []
        
        # Crossfeed (кроссфид) - основа виртуальной стереосцены
        # Добавляем компенсацию громкости для кроссфида
        crossfeed_strength = self.custom_settings['crossfeed_strength']
        crossfeed_range = self.custom_settings['crossfeed_range']
        crossfeed = f"crossfeed=strength={crossfeed_strength}:range={crossfeed_range}"
        filters.append(crossfeed)
        
        # Компенсация громкости для кроссфида (volume boost)
        # Кроссфид уменьшает громкость на ~10-20%, компенсируем это
        if crossfeed_strength > 0.1:
            volume_boost = 1.0 + (crossfeed_strength * 0.2)  # +20% при максимальной силе
            volume_filter = f"volume={volume_boost}"
            filters.append(volume_filter)
        
        # Haas effect (эффект Хааса) - временная задержка для создания ширины
        haas = f"haas=level_in=1.0:level_out={self.custom_settings['haas_level_out']}:side_gain={self.custom_settings['haas_side_gain']}"
        filters.append(haas)
        
        # Extra stereo - усиление стерeo-эффекта
        extrastereo = f"extrastereo=m={self.custom_settings['extrastereo_multiplier']}"
        filters.append(extrastereo)
        
        # Surround upmix - создание объемности
        if self.custom_settings['surround_level_out'] > 0:
            surround = f"surround=chl_out=stereo:chl_in=stereo:level_in=1.0:level_out={self.custom_settings['surround_level_out']}"
            filters.append(surround)
        
        return filters
    
    def get_mpv_af_string(self, preset_name='off'):
        """Получает строку аудиофильтров для MPV"""
        filters = self.get_filter_chain(preset_name)
        
        if not filters:
            return ""
        
        return ",".join(filters)
    
    def get_preset_info(self, preset_name):
        """Получает информацию о предустановке"""
        return self.PRESETS.get(preset_name, self.PRESETS['off'])
    
    def get_all_presets(self):
        """Получает список всех предустановок"""
        return {name: preset for name, preset in self.PRESETS.items() if name != 'custom'}
    
    def update_custom_setting(self, setting_name, value):
        """Обновляет пользовательскую настройку"""
        if setting_name in self.custom_settings:
            # Ограничиваем значения разумными пределами
            if setting_name in ['crossfeed_strength', 'crossfeed_range']:
                value = max(0.0, min(1.0, float(value)))
            elif setting_name in ['haas_level_out', 'haas_side_gain', 'extrastereo_multiplier', 'surround_level_out']:
                value = max(0.0, min(3.0, float(value)))
            
            self.custom_settings[setting_name] = value
            return True
        return False
    
    def get_custom_settings(self):
        """Получает текущие пользовательские настройки"""
        return self.custom_settings.copy()

# Объяснения эффектов для пользователя
EFFECT_EXPLANATIONS = {
    'crossfeed': {
        'name': 'Кроссфид',
        'description': 'Смешивает левый и правый каналы для имитации естественного восприятия звука через колонки. Устраняет "туннельный" эффект наушников.',
        'strength': 'Сила эффекта (0.0-1.0): чем выше, тем больше смешивания каналов',
        'range': 'Частотный диапазон (0.0-1.0): какие частоты обрабатывать'
    },
    'haas': {
        'name': 'Эффект Хааса',
        'description': 'Создает иллюзию расширения стереосцены через микрозадержки между каналами. Имитирует время прихода звука от удаленных источников.',
        'level_out': 'Уровень выхода (0.0-3.0): общая громкость эффекта',
        'side_gain': 'Усиление боковых каналов (0.0-3.0): ширина стереосцены'
    },
    'extrastereo': {
        'name': 'Усиление стерео',
        'description': 'Увеличивает разность между левым и правым каналами, делая звук более "широким".',
        'multiplier': 'Множитель (0.0-3.0): сила усиления стерео-эффекта'
    },
    'surround': {
        'name': 'Объемный звук',
        'description': 'Создает иллюзию многоканального звука из стерео-источника.',
        'level_out': 'Уровень выхода (0.0-3.0): интенсивность объемного эффекта'
    }
}

def get_effect_explanation(effect_name):
    """Получает объяснение эффекта для пользователя"""
    return EFFECT_EXPLANATIONS.get(effect_name, {
        'name': effect_name,
        'description': 'Аудио-эффект для улучшения звучания'
    })
