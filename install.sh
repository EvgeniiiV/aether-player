#!/bin/bash
# Aether Player - Автоматическая установка для Raspberry Pi
# Версия: 1.0
# Автор: EvgeniiiV

set -e  # Останавливаем скрипт при любой ошибке

# Цвета для красивого вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Функция для красивого вывода
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[УСПЕХ]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[ВНИМАНИЕ]${NC} $1"
}

print_error() {
    echo -e "${RED}[ОШИБКА]${NC} $1"
}

print_header() {
    echo -e "${PURPLE}"
    echo "=================================================="
    echo "🎵 AETHER PLAYER - УСТАНОВКА НА RASPBERRY PI"
    echo "=================================================="
    echo -e "${NC}"
}

# Проверяем, что мы на Raspberry Pi
check_system() {
    print_status "Проверяем систему..."
    
    if ! grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
        print_warning "Возможно, это не Raspberry Pi, но продолжаем..."
    else
        print_success "Raspberry Pi обнаружен!"
    fi
    
    # Проверяем права root
    if [[ $EUID -eq 0 ]]; then
        print_error "Не запускайте этот скрипт от root! Используйте обычного пользователя."
        exit 1
    fi
}

# Установка системных зависимостей
install_system_dependencies() {
    print_status "Обновляем систему и устанавливаем зависимости..."
    
    sudo apt update
    sudo apt install -y \
        python3 \
        python3-pip \
        python3-venv \
        git \
        alsa-utils \
        pulseaudio \
        libsdl2-dev \
        libsdl2-mixer-2.0-0 \
        ffmpeg
    
    print_success "Системные зависимости установлены!"
}

# Создание пользователя для сервиса (если нужно)
setup_user() {
    print_status "Настройка пользователя..."
    
    # Добавляем пользователя в audio группу для работы со звуком
    sudo usermod -a -G audio $USER
    
    print_success "Пользователь настроен!"
}

# Клонирование репозитория
clone_repository() {
    print_status "Скачиваем Aether Player с GitHub..."
    
    INSTALL_DIR="/home/$USER/aether-player"
    
    if [ -d "$INSTALL_DIR" ]; then
        print_warning "Папка $INSTALL_DIR уже существует!"
        read -p "Удалить и переустановить? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$INSTALL_DIR"
        else
            print_error "Установка отменена."
            exit 1
        fi
    fi
    
    git clone https://github.com/EvgeniiiV/aether-player.git "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    print_success "Репозиторий клонирован в $INSTALL_DIR"
}

# Создание виртуального окружения и установка зависимостей Python
setup_python_environment() {
    print_status "Создаем виртуальное окружение Python..."
    
    cd "/home/$USER/aether-player"
    
    # Создаем виртуальное окружение
    python3 -m venv .venv
    
    # Активируем и устанавливаем зависимости
    source .venv/bin/activate
    pip install --upgrade pip
    pip install -r requirements.txt
    
    print_success "Python окружение настроено!"
}

# Создание папки для медиа файлов
setup_media_directory() {
    print_status "Создаем папку для медиа файлов..."
    
    MEDIA_DIR="/home/$USER/aether-player/media"
    mkdir -p "$MEDIA_DIR"
    
    # Создаем демонстрационную структуру папок
    mkdir -p "$MEDIA_DIR/Music"
    mkdir -p "$MEDIA_DIR/Podcasts"
    mkdir -p "$MEDIA_DIR/Audiobooks"
    
    # Создаем README файл
    cat > "$MEDIA_DIR/README.txt" << EOF
🎵 Папка для медиа файлов Aether Player

Поддерживаемые форматы:
- Аудио: MP3, WAV, FLAC, M4A, OGG
- Изображения: JPG, JPEG, PNG, GIF, BMP

Создайте свои папки и загружайте файлы через веб-интерфейс
или копируйте напрямую в эти папки.

Aether Player автоматически обнаружит новые файлы.
EOF
    
    print_success "Медиа папка создана: $MEDIA_DIR"
}

# Главная функция
main() {
    print_header
    
    print_status "Начинаем установку Aether Player..."
    echo
    
    check_system
    install_system_dependencies
    setup_user
    clone_repository
    setup_python_environment
    setup_media_directory
    
    echo
    print_success "🎉 УСТАНОВКА ЗАВЕРШЕНА!"
    echo
    print_status "Что дальше:"
    echo "1. Запустите плеер: cd ~/aether-player && source .venv/bin/activate && python app.py"
    echo "2. Откройте браузер: http://$(hostname -I | awk '{print $1}'):5000"
    echo "3. Скопируйте медиа файлы в папку: ~/aether-player/media/"
    echo
    print_status "Для автозапуска при загрузке системы запустите: ./setup-service.sh"
    echo
}

# Запускаем установку
main
