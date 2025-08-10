# GitHub Copilot Instructions for Aether Player

## Project Overview

Aether Player is a Python/Flask-based audio enhancement and media player system designed for Raspberry Pi environments. It features advanced audio processing, GPIO-controlled power management, and a modern web interface for real-time control.

### Core Technologies
- **Backend**: Python 3.11+ with Flask framework
- **Media Engine**: MPV player with IPC socket communication
- **Audio Enhancement**: Custom filter chains using FFmpeg/ALSA
- **Hardware Control**: RPi.GPIO for power management (GPIO18/21)
- **Frontend**: Modern JavaScript with real-time WebSocket-like updates
- **System Integration**: systemd services with automatic startup

## Architecture Overview

### Primary Components

1. **`app.py`** - Main Flask application
   - MPV process management and IPC communication
   - Audio device detection and configuration
   - Filter chain construction and application
   - RESTful API endpoints for control
   - Video stream selection and playback logic

2. **`audio_enhancement.py`** - Audio processing engine
   - Crossfeed implementation with empirically tuned coefficients
   - Haas effect for stereo widening
   - Extrastereo with volume compensation (28% reduction)
   - Surround sound upmixing
   - Preset management and parameter validation

3. **`power-control.py`** - GPIO power management
   - Hardware relay control for 220V peripherals
   - Safe shutdown procedures with USB unmounting
   - systemd service integration
   - Status monitoring and diagnostics

4. **Web Interface** (`static/script.js` + `templates/index.html`)
   - Real-time control interface
   - Audio enhancement parameter adjustment
   - System monitoring and diagnostics

### Key Integration Points

- **MPV Socket**: `/tmp/mpv-socket` for IPC communication
- **Audio Device**: Auto-detected ALSA device (typically `hw:1,0`)
- **GPIO Pin**: 18 or 21 for relay control (with opto-isolator)
- **Service Names**: `aether-player.service`, `aether-power.service`

## Audio Enhancement System

### Filter Chain Architecture
```python
def _build_custom_filters(self, config):
    filters = []
    if config.get('crossfeed'):
        filters.append(f"crossfeed=strength={strength}:range={range}")
    if config.get('extrastereo'):
        filters.append(f"extrastereo=m={coefficient}")
    # Compensation applied via volume adjustment
    return ",".join(filters)
```

### Critical Audio Parameters
- **Crossfeed**: Strength 0.5-0.9, Range 2000-8000 Hz (empirically tuned)
- **Extrastereo**: Coefficient 1.5-3.0 with 28% volume compensation
- **Startup Volume**: 60% for safety (MPV softvol-max=200%)
- **Device Selection**: Auto-detection with fallback to default

### Volume Compensation Logic
```python
# Extrastereo compensation (empirically determined)
if extrastereo_enabled and extrastereo > 1.0:
    compensation = 0.72  # 28% volume reduction
    target_volume = int(target_volume * compensation)
```

## Power Management System

### GPIO Configuration
- **Current Pin**: GPIO 18 (BCM numbering, physical pin 12)
- **Backup Pin**: GPIO 21 (physical pin 40) - documented fallback
- **Hardware**: Opto-isolated relay module for 220V peripheral control
- **Safety**: Always LOW on startup, HIGH for power-on

### Critical Power Operations
```python
# Power on sequence
GPIO.setup(gpio_pin, GPIO.OUT)
GPIO.output(gpio_pin, GPIO.HIGH)  # 3.3V to opto-isolator

# Safe shutdown with USB unmounting
umount_usb_devices()
GPIO.output(gpio_pin, GPIO.LOW)
GPIO.cleanup()
```

### systemd Integration
- **Service**: `aether-power.service` (oneshot with RemainAfterExit)
- **Dependency**: Runs before `aether-player.service`
- **Lifecycle**: ExecStart=power on, ExecStop=safe power off

## Development Guidelines

### Code Style & Patterns

1. **Error Handling**: Always use try/except for GPIO and MPV operations
2. **Logging**: Use Python logging module, avoid print() in production paths
3. **Resource Cleanup**: Always call `GPIO.cleanup()` and close MPV sockets
4. **Parameter Validation**: Validate all user inputs before applying to MPV

### Testing Approaches

1. **Audio Testing**: Use `diagnose-audio.sh` for device validation
2. **Video Testing**: Use `test-video.sh` for codec/stream testing
3. **GPIO Testing**: Use `power-control.py test` for relay verification
4. **Service Testing**: `systemctl status` for service health

### Common Pitfalls to Avoid

1. **Audio Device Changes**: Never hardcode device numbers - always auto-detect
2. **MPV Command Construction**: Include ALL required parameters (--audio-device is critical)
3. **GPIO Cleanup**: Always cleanup on exit to prevent "device busy" errors
4. **Volume Safety**: Never exceed safe startup levels without user confirmation
5. **Filter Conflicts**: Test all filter combinations - some are mutually exclusive

## File Organization

### Core Application Files
- `app.py` - Main Flask application and MPV control
- `audio_enhancement.py` - Audio processing and filter management
- `power-control.py` - GPIO and power management
- `requirements.txt` - Python dependencies

### Configuration & Setup
- `install.sh` - Main installation script
- `setup-*.sh` - Specialized setup scripts for services/monitoring
- `.gitignore` - Excludes test files, logs, and system artifacts

### Documentation
- `README.md` - Project overview and quick start
- `AUDIO_ENHANCEMENT_GUIDE.md` - Detailed audio processing documentation
- `СТРУКТУРА_ПРОЕКТА.md` - Russian project structure documentation
- `УПРАВЛЕНИЕ_ПИТАНИЕМ.md` - Power management documentation

### Web Interface
- `templates/index.html` - Main web interface
- `static/script.js` - Frontend JavaScript logic
- `static/style.css` - UI styling

### Diagnostic Tools
- `diagnose-*.sh` - Hardware and software diagnostic scripts
- `test-*.sh` - Automated testing utilities
- `monitor.sh` - System monitoring and logging

## API Endpoints

### Audio Control
- `POST /play` - Start playback with file path
- `POST /pause` - Pause/resume playback
- `POST /volume` - Set volume level (0-200)
- `POST /apply_audio_enhancement` - Apply filter configuration

### System Control  
- `GET /status` - Get system and playback status
- `POST /system/power` - Power management (on/off/status)
- `GET /system/devices` - List available audio devices

### Enhancement Parameters
- `POST /enhancement/crossfeed` - Configure crossfeed parameters
- `POST /enhancement/extrastereo` - Configure stereo widening
- `POST /enhancement/preset` - Apply enhancement preset

## Debugging & Troubleshooting

### Audio Issues
1. Check device availability: `cat /proc/asound/cards`
2. Verify MPV socket: `ls -la /tmp/mpv-socket`
3. Test direct playback: `mpv --audio-device=hw:1,0 test.wav`
4. Check filter syntax: Review MPV error logs

### Power Management Issues
1. GPIO permissions: Run power commands with `sudo`
2. Hardware testing: Use multimeter on GPIO pin (0V/3.3V)
3. Relay verification: Listen for relay clicking sound
4. Service status: `systemctl status aether-power`

### Video Playback Issues
1. Stream detection: Use `ffprobe` to analyze file structure
2. Codec support: Check MPV hardware decoding capabilities
3. Multiple streams: Verify correct video stream selection
4. Performance: Monitor CPU usage during playback

## Development Workflow

### Making Changes
1. **Always backup**: Use git before major changes
2. **Test incrementally**: Apply one change at a time
3. **Verify services**: Check systemd status after modifications
4. **Document changes**: Update relevant .md files

### Common Development Tasks

#### Adding New Audio Enhancement
```python
# In audio_enhancement.py
def add_new_filter(self, config):
    if config.get('new_filter'):
        return f"filtername=param1={value1}:param2={value2}"
    return ""
```

#### Modifying GPIO Behavior
```python
# Always include cleanup and error handling
try:
    GPIO.setup(pin, GPIO.OUT)
    GPIO.output(pin, state)
except Exception as e:
    logger.error(f"GPIO error: {e}")
finally:
    GPIO.cleanup()
```

#### Adding API Endpoints
```python
@app.route('/new_endpoint', methods=['POST'])
def new_endpoint():
    # Always validate input
    data = request.get_json()
    if not validate_input(data):
        return jsonify({'error': 'Invalid input'}), 400
    
    # Apply changes and return status
    result = apply_changes(data)
    return jsonify({'success': True, 'result': result})
```

## Security Considerations

- **GPIO Access**: Requires root/sudo permissions
- **File Access**: Validate all file paths to prevent traversal attacks  
- **Network Binding**: Flask development server - not for production use
- **System Commands**: Sanitize all shell command parameters

## Performance Notes

- **MPV Startup**: Allow 2-3 seconds for MPV socket initialization
- **Filter Application**: Some combinations may increase CPU usage
- **GPIO Operations**: Include small delays (0.1s) for relay settling
- **Web Interface**: Updates every 1-2 seconds for real-time feel

---

*This document is maintained as part of the Aether Player project to enable rapid onboarding of AI assistants and human developers.*
