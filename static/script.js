document.addEventListener('DOMContentLoaded', () => {
    console.log("[STARTUP] Простая архитектура загружена");
    console.log("[STARTUP] Версия: 2.0.0 - Simple (28.07.2025)");
    
    // Глобальные переменные
    let player_status = null;
    let isUserDragging = false; // Флаг для отслеживания взаимодействия с прогресс-баром
    let lastUpdateTime = 0; // Для отслеживания интервалов обновления
    
    // Функции для управления индикацией активного трека
    function clearActiveTrackIndicators() {
        document.querySelectorAll('.play-button.playing').forEach(button => {
            button.classList.remove('playing');
        });
    }

    function setActiveTrackIndicator(trackPath, fromClick = false, startTime = null) {
        console.log('[INDICATOR] setActiveTrackIndicator:', trackPath, 'startTime:', startTime);

        let targetButton = null;

        // Если есть время начала, ищем ТОЛЬКО CUE трек с таким же файлом и временем
        if (startTime !== null) {
            console.log('[INDICATOR] CUE mode - searching for track with startTime:', startTime);
            const allButtons = document.querySelectorAll('.play-button');
            allButtons.forEach((btn) => {
                if (btn.dataset.filepath === trackPath &&
                    btn.dataset.startTime &&
                    Math.abs(parseFloat(btn.dataset.startTime) - parseFloat(startTime)) < 1) {
                    targetButton = btn;
                    console.log('[INDICATOR] Found matching CUE track button');
                }
            });

            if (!targetButton) {
                console.log('[INDICATOR] CUE track button NOT found - skipping indicator (strict mode)');
                return; // Не устанавливаем индикацию, если не нашли конкретный CUE трек
            }
        } else {
            console.log('[INDICATOR] Normal mode - searching for file without startTime');
            // Для обычных файлов ищем кнопку БЕЗ startTime
            const candidates = document.querySelectorAll(`.play-button[data-filepath="${trackPath}"]`);
            candidates.forEach(btn => {
                if (!btn.dataset.startTime && !targetButton) {
                    targetButton = btn;
                    console.log('[INDICATOR] Found exact match button without startTime');
                }
            });

            // Fallback: поиск по имени файла ТОЛЬКО для обычных файлов (не CUE)
            if (!targetButton) {
                console.log('[INDICATOR] Exact match not found, trying basename fallback');
                const trackBasename = trackPath.split('/').pop().replace(/\.[^/.]+$/, "");
                const allButtons = document.querySelectorAll('.play-button');
                allButtons.forEach((btn) => {
                    const btnBasename = btn.dataset.filepath.split('/').pop().replace(/\.[^/.]+$/, "");
                    if (btnBasename.includes(trackBasename) || trackBasename.includes(btnBasename)) {
                        if (!btn.dataset.startTime && !targetButton) {
                            targetButton = btn;
                            console.log('[INDICATOR] Found button via basename fallback');
                        }
                    }
                });
            }
        }

        // Очищаем ВСЕ кнопки
        console.log('[INDICATOR] Clearing all button states');
        document.querySelectorAll('.play-button').forEach(button => {
            button.classList.remove('playing');
        });

        // Устанавливаем индикацию на целевую кнопку
        if (targetButton) {
            console.log('[INDICATOR] Setting active state on target button');
            targetButton.classList.add('playing');
        } else {
            console.log('[INDICATOR] No target button found');
        }
    }
    
    // Детектор проблем и восстановление
    function detectAndRecover(data) {
        // Детектируем неожиданную остановку при том же треке
        if (data.state === 'stopped' && 
            player_status && 
            player_status.state === 'playing' && 
            player_status.track === data.track &&
            data.track !== '') {
            
            console.warn("[RECOVERY] Детектирована неожиданная остановка! Попытка восстановления...");
            console.warn(`[RECOVERY] Было: ${player_status.state} "${player_status.track}"`);
            console.warn(`[RECOVERY] Стало: ${data.state} "${data.track}"`);
            
            // Пробуем реактивировать плеер
            fetch('/toggle_pause', { method: 'POST' })
                .then(response => response.json())
                .then(result => {
                    console.log("[RECOVERY] Результат попытки восстановления:", result);
                    // Запрашиваем статус через секунду для проверки
                    setTimeout(fetchStatus, 1000);
                })
                .catch(error => {
                    console.error("[RECOVERY] Ошибка восстановления:", error);
                });
                
            return false; // Не обновляем UI с "плохими" данными
        }
        
        return true; // Данные в порядке, можно обновлять UI
    }
    
    // Элементы DOM
    const nowPlayingInfo = document.getElementById('now-playing-info');
    const playPauseButton = document.getElementById('play-pause-button');
    const stopButton = document.getElementById('stop-button');
    let progressBar = document.getElementById('progress-bar'); // let вместо const для перепривязки
    const currentTimeSpan = document.getElementById('current-time');
    const totalTimeSpan = document.getElementById('total-time');
    const createFolderForm = document.getElementById('create-folder-form');
    const newFolderNameInput = document.getElementById('new-folder-name');
    const uploadForm = document.getElementById('upload-form');
    const fileInput = document.getElementById('file-input');
    const volumeSlider = document.getElementById('volume-slider');
    const volumePercent = document.getElementById('volume-percent');
    const prevButton = document.getElementById('prev-button');
    const nextButton = document.getElementById('next-button');

    // Форматирование времени с ЗАЩИТОЙ ОТ ЗМЕИ
    function formatTime(seconds) {
        // ЗАЩИТА: проверяем входное значение
        if (isNaN(seconds) || seconds === null || seconds === undefined) {
            console.warn(`[ЗАЩИТА ЗМЕИ] formatTime: некорректное значение ${seconds} -> 0`);
            seconds = 0;
        }
        
        if (seconds < 0) {
            console.warn(`[ЗАЩИТА ЗМЕИ] formatTime: отрицательное значение ${seconds} -> 0`);
            seconds = 0;
        }
        
        if (seconds > 999999) { // Защита от сверх больших значений
            console.warn(`[ЗАЩИТА ЗМЕИ] formatTime: слишком большое значение ${seconds} -> 999999`);
            seconds = 999999;
        }
        
        const mins = Math.floor(seconds / 60);
        const secs = Math.floor(seconds % 60);
        return `${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
    }

    // Обновление информации о предустановке виртуальной стереосцены
    function updateAudioEnhancementInfo(currentPreset) {
        const presetElement = document.getElementById('current-preset');
        if (!presetElement || !currentPreset) {
            return;
        }
        
        const presetNames = {
            'off': 'Выключено',
            'subtle': 'Деликатное',
            'natural': 'Естественное',
            'wide': 'Широкое',
            'speakers': 'Имитация колонок',
            'custom': 'Пользовательское'
        };
        
        const displayName = presetNames[currentPreset] || currentPreset;
        presetElement.textContent = displayName;
        
        // Меняем цвет в зависимости от предустановки
        const presetContainer = document.getElementById('audio-enhancement-info');
        if (presetContainer) {
            if (currentPreset === 'off') {
                presetContainer.style.color = '#666';
            } else {
                presetContainer.style.color = '#8af';
            }
        }
    }

    // ПРОСТОЕ обновление UI - один в один что прислал backend
    function updateUI(data) {
        const currentTime = Date.now();
        const timeSinceLastUpdate = lastUpdateTime ? currentTime - lastUpdateTime : 0;
        lastUpdateTime = currentTime;
        
        console.log(`[UI] Обновление UI (Δt=${timeSinceLastUpdate}ms):`, data);
        
        if (!data) {
            console.error("[ERROR] Пустые данные статуса");
            return;
        }
        
        // ПРОВЕРКА: Детектируем проблемы и пытаемся восстановиться
        if (!detectAndRecover(data)) {
            console.log("[UI] Обновление UI пропущено из-за детектированной проблемы");
            return;
        }
        
        player_status = data;
        
        // Обновляем информацию о треке
        if (data.state === 'stopped') {
            nowPlayingInfo.innerHTML = '<strong>Статус:</strong> Остановлено';
            playPauseButton.textContent = '▶️';
            nowPlayingInfo.classList.remove('playing-indicator');

            // Убираем индикацию активного трека при остановке
            clearActiveTrackIndicators();

            // Сбрасываем прогресс-бар
            progressBar.value = 0;
            progressBar.max = 100;
            currentTimeSpan.textContent = "00:00";
            totalTimeSpan.textContent = "00:00";
        } else {
            const stateText = data.state === 'playing' ? 'Воспроизведение' : 'Пауза';
            let trackInfo = data.track || 'Нет данных';

            // Если есть информация о CUE треке, показываем её
            if (data.cue_track_title) {
                trackInfo = `${String(data.cue_track_number || '').padStart(2, '0')}. ${data.cue_track_title}`;
                if (data.cue_track_performer) {
                    trackInfo += ` - ${data.cue_track_performer}`;
                }
            }

            nowPlayingInfo.innerHTML = `<strong>Статус:</strong> ${stateText}<br><strong>Трек:</strong> ${trackInfo}`;

            // Устанавливаем индикацию активного трека для playing и paused
            if (data.track) {
                // Для CUE треков используем cue_track_start_time, для обычных - start_time
                const indicatorStartTime = data.cue_track_start_time !== undefined ? data.cue_track_start_time : data.start_time;
                setActiveTrackIndicator(data.track, false, indicatorStartTime);
            }

            if (data.state === 'playing') {
                nowPlayingInfo.classList.add('playing-indicator');
                playPauseButton.textContent = '⏸️';
                playPauseButton.title = 'Пауза';
            } else {
                nowPlayingInfo.classList.remove('playing-indicator');
                playPauseButton.textContent = '▶️';
                playPauseButton.title = 'Воспроизведение';
            }
        }
        
        // АГРЕССИВНАЯ ЗАЩИТА ОТ "ЗМЕИ" - валидация входных данных
        let position = parseFloat(data.position) || 0;
        let duration = parseFloat(data.duration) || 1;
        
        // Проверяем корректность данных
        if (isNaN(position) || position < 0) {
            console.warn(`[ЗАЩИТА ЗМЕИ] Некорректная позиция: ${data.position} -> 0`);
            position = 0;
        }
        
        if (isNaN(duration) || duration < 1) {
            console.warn(`[ЗАЩИТА ЗМЕИ] Некорректная длительность: ${data.duration} -> 1`);
            duration = 1;
        }
        
        // ГЛАВНАЯ ЗАЩИТА: позиция НИКОГДА не может превышать длительность
        if (position > duration) {
            console.warn(`[ЗАЩИТА ЗМЕИ] Позиция превышает длительность: ${position.toFixed(1)} > ${duration.toFixed(1)}, зажимаем`);
            position = duration;
        }
        
        // Дополнительная защита: если длительность меньше позиции, увеличиваем её
        if (duration < position) {
            console.warn(`[ЗАЩИТА ЗМЕИ] Длительность меньше позиции: ${duration.toFixed(1)} < ${position.toFixed(1)}, увеличиваем`);
            duration = position + 1;
        }
        
        // Обновляем тексты времени (всегда используем защищённые значения)
        currentTimeSpan.textContent = formatTime(position);
        totalTimeSpan.textContent = formatTime(duration);
        
        // Обновляем прогресс-бар ТОЛЬКО если пользователь его не перетаскивает
        if (progressBar && !isUserDragging) {
            // ДЕТАЛЬНОЕ ЛОГИРОВАНИЕ для отладки "змеи"
            const oldMax = parseFloat(progressBar.max) || 0;
            const oldValue = parseFloat(progressBar.value) || 0;
            
            console.log(`[DEBUG] Прогресс-бар: old(${oldValue.toFixed(1)}/${oldMax.toFixed(1)}) -> new(${position.toFixed(1)}/${duration.toFixed(1)})`);
            
            // ПРОСТОЕ ОБНОВЛЕНИЕ - сервер обновляет только когда пользователь НЕ взаимодействует
            progressBar.max = duration;
            progressBar.value = Math.min(position, duration);
            
            const finalValue = parseFloat(progressBar.value);
            const finalMax = parseFloat(progressBar.max);
            
            if (finalValue > finalMax) {
                console.error(`[ЗАЩИТА ЗМЕИ] КОРРЕКЦИЯ: ${finalValue} -> ${finalMax}`);
                progressBar.value = finalMax;
            }
            
            console.log(`[DEBUG] Обновлено: ${finalValue.toFixed(1)}/${finalMax.toFixed(1)}`);
        }
        
        // Обновляем громкость
        if (typeof data.volume === 'number') {
            volumeSlider.value = data.volume;
            volumePercent.textContent = `${Math.round(data.volume)}%`;
        }
        
        // Обновляем информацию о предустановке аудио
        updateAudioEnhancementInfo(data.audio_enhancement);
    }
    
    // Функция обновления информации о предустановке аудио
    function updateAudioEnhancementInfo(preset) {
        const currentPresetSpan = document.getElementById('current-preset');
        if (!currentPresetSpan) return;
        
        const presetNames = {
            'off': 'Выключено',
            'subtle': 'Деликатное',
            'natural': 'Естественное', 
            'wide': 'Широкое',
            'speakers': 'Колонки',
            'custom': 'Пользовательское'
        };
        
        const displayName = presetNames[preset] || 'Неизвестно';
        currentPresetSpan.textContent = displayName;
        
        // Меняем цвет в зависимости от предустановки
        const audioEnhancementInfo = document.getElementById('audio-enhancement-info');
        if (audioEnhancementInfo) {
            if (preset === 'off') {
                audioEnhancementInfo.style.color = '#666';
            } else {
                audioEnhancementInfo.style.color = '#8af';
            }
        }
    }
    
    // ПРОСТОЙ HTTP polling - 1 раз в секунду
    let statusPollingInterval;
    
    function startStatusPolling() {
        console.log("[SYSTEM] Запуск простого polling (500ms)");
        
        if (statusPollingInterval) {
            clearInterval(statusPollingInterval);
        }
        
        // Немедленно запрашиваем статус
        fetchStatus();
        
        // Устанавливаем интервал 500 миллисекунд для более плавного обновления
        statusPollingInterval = setInterval(fetchStatus, 500);
    }
    
    function fetchStatus() {
        const url = '/get_status?nocache=' + Math.random();
        const requestTime = Date.now();
        
        fetch(url)
            .then(response => {
                if (!response.ok) {
                    throw new Error(`HTTP ${response.status}`);
                }
                return response.json();
            })
            .then(data => {
                const responseTime = Date.now();
                const requestDuration = responseTime - requestTime;
                console.log(`[NETWORK] Статус: ${data.state}, pos=${data.position?.toFixed(1)}, dur=${data.duration?.toFixed(1)} (запрос: ${requestDuration}ms)`);
                updateUI(data);
            })
            .catch(error => {
                console.error("[ERROR] Ошибка получения статуса:", error);
            });
    }
    
    // Начальная загрузка
    console.log("[NETWORK] Запрашиваем начальный статус");
    
    fetch('/get_status')
        .then(response => response.json())
        .then(data => {
            console.log("[NETWORK] Начальный статус:", data);
            updateUI(data);
            startStatusPolling();
        })
        .catch(error => {
            console.error("[ERROR] Ошибка начального статуса:", error);
            setTimeout(startStatusPolling, 3000);
        });

    // --- Обработчики событий ---
    
    // Кнопки воспроизведения файлов
    document.querySelectorAll('.play-button').forEach(button => {
        button.addEventListener('click', function() {
            const filepath = this.dataset.filepath;
            const startTime = this.dataset.startTime; // Время начала в секундах для CUE-треков
            
            // Устанавливаем индикацию от клика с передачей времени начала для CUE треков
            setActiveTrackIndicator(filepath, true, startTime ? parseFloat(startTime) : null);
            
            // Готовим данные для отправки
            let requestBody = `filepath=${encodeURIComponent(filepath)}`;
            if (startTime) {
                requestBody += `&start_time=${startTime}`;
            }
            
            fetch('/play', {
                method: 'POST',
                headers: {'Content-Type': 'application/x-www-form-urlencoded'},
                body: requestBody
            });
        });
    });

        // Кнопки просмотра изображений
    document.querySelectorAll('.view-button').forEach(button => {
        button.addEventListener('click', function() {
            const filepath = this.dataset.filepath;
            console.log("[ACTION] Просмотр изображения:", filepath);
            window.open(`/media/${encodeURIComponent(filepath)}`, '_blank');
        });
    });

    // Кнопки чтения текстовых файлов
    document.querySelectorAll('.text-button').forEach(button => {
        button.addEventListener('click', function() {
            const filepath = this.dataset.filepath;
            console.log("[ACTION] Просмотр текстового файла:", filepath);
            window.open(`/view_text/${encodeURIComponent(filepath)}`, '_blank');
        });
    });

    // Управление плеером
    playPauseButton.addEventListener('click', () => {
        console.log("[ACTION] Play/Pause");
        fetch('/toggle_pause', { method: 'POST' })
            .then(response => response.json())
            .then(data => console.log("Результат toggle_pause:", data))
            .catch(error => console.error("Ошибка toggle_pause:", error));
    });
    
    stopButton.addEventListener('click', () => {
        console.log("[ACTION] Stop");
        fetch('/stop', { method: 'POST' })
            .then(response => response.json())
            .then(data => console.log("Результат stop:", data))
            .catch(error => console.error("Ошибка stop:", error));
    });

    // Кнопки плейлиста
    nextButton.addEventListener('click', () => {
        console.log("[ACTION] Next");
        fetch('/playlist_change', { 
            method: 'POST', 
            headers: {'Content-Type': 'application/x-www-form-urlencoded'}, 
            body: 'direction=next' 
        });
    });
    
    prevButton.addEventListener('click', () => {
        console.log("[ACTION] Previous");
        fetch('/playlist_change', { 
            method: 'POST', 
            headers: {'Content-Type': 'application/x-www-form-urlencoded'}, 
            body: 'direction=previous' 
        });
    });

    // Управление громкостью
    let volumeTimeout;
    volumeSlider.addEventListener('input', function() {
        volumePercent.textContent = `${this.value}%`;
        clearTimeout(volumeTimeout);
        volumeTimeout = setTimeout(() => {
            fetch('/set_volume', {
                method: 'POST',
                headers: {'Content-Type': 'application/x-www-form-urlencoded'},
                body: `volume=${this.value}`
            });
        }, 50);
    });

    // ПРОСТОЕ управление прогресс-баром
    if (progressBar) {
        // Отслеживание начала перетаскивания
        progressBar.addEventListener('mousedown', function() {
            console.log("[SEEK] Начало перетаскивания");
            isUserDragging = true;
        });
        
        progressBar.addEventListener('touchstart', function() {
            console.log("[SEEK] Начало перетаскивания (touch)");
            isUserDragging = true;
        });
        
        // Отслеживание окончания перетаскивания - глобальные обработчики
        document.addEventListener('mouseup', function() {
            if (isUserDragging) {
                console.log("[SEEK] Окончание перетаскивания");
                isUserDragging = false;
                handleSeek();
            }
        });
        
        document.addEventListener('touchend', function() {
            if (isUserDragging) {
                console.log("[SEEK] Окончание перетаскивания (touch)");
                isUserDragging = false;
                handleSeek();
            }
        });
        
        // Отправляем позицию только при изменении во время перетаскивания
        progressBar.addEventListener('change', function() {
            if (isUserDragging) {
                handleSeek();
            }
        });
        
        function handleSeek() {
                let newPosition = parseFloat(progressBar.value);
                const maxPosition = parseFloat(progressBar.max);
                
                // ЗАЩИТА: проверяем значения перед отправкой
                if (isNaN(newPosition) || newPosition < 0) {
                    console.warn(`[ЗАЩИТА ЗМЕИ] Некорректная позиция seek: ${progressBar.value} -> 0`);
                    newPosition = 0;
                }
                
                if (newPosition > maxPosition) {
                    console.warn(`[ЗАЩИТА ЗМЕИ] Позиция seek превышает максимум: ${newPosition.toFixed(1)} > ${maxPosition.toFixed(1)}, зажимаем`);
                    newPosition = maxPosition;
                }
                
                console.log(`[SEEK] Перемотка на ${newPosition.toFixed(1)} (макс: ${maxPosition.toFixed(1)})`);
                
                fetch('/seek', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
                    body: `position=${newPosition}`
                })
                .then(response => response.json())
                .then(data => {
                    console.log("[SEEK] Результат:", data);
                    // Немедленно запрашиваем новый статус
                    setTimeout(fetchStatus, 100);
                })
                .catch(error => {
                    console.error("[SEEK] Ошибка:", error);
                });
        }
        
        // Обновление времени при перетаскивании
        progressBar.addEventListener('input', function() {
            currentTimeSpan.textContent = formatTime(parseFloat(this.value));
        });
    }

    // Форма создания папки
    createFolderForm.addEventListener('submit', function(event) {
        event.preventDefault();
        const folderName = newFolderNameInput.value;
        const currentPath = document.querySelector('h3').textContent.replace('Текущая папка: /', '');
        
        if (folderName) {
            const formData = new FormData();
            formData.append('current_path', currentPath);
            formData.append('folder_name', folderName);
            
            fetch('/create_folder', { method: 'POST', body: formData })
                .then(response => {
                    if (response.ok) {
                        setTimeout(() => location.reload(), 500);
                    }
                });
            
            newFolderNameInput.value = '';
        }
    });

    // Форма загрузки файлов
    uploadForm.addEventListener('submit', function(event) {
        event.preventDefault();
        const files = fileInput.files;
        const currentPath = document.querySelector('h3').textContent.replace('Текущая папка: /', '');
        
        if (files.length > 0) {
            const formData = new FormData();
            formData.append('current_path', currentPath);
            
            for (let i = 0; i < files.length; i++) {
                formData.append('files_to_upload', files[i]);
            }
            
            fetch('/upload', { method: 'POST', body: formData })
                .then(response => {
                    if (response.ok) {
                        setTimeout(() => location.reload(), 500);
                    }
                });
            
            fileInput.value = '';
        }
    });
});
