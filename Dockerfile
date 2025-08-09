# Базовый образ Python
FROM python:3.11-slim

# Рабочая директория в контейнере
WORKDIR /app

# Копируем requirements и устанавливаем зависимости
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Копируем приложение
COPY . .

# Открываем порт
EXPOSE 5000

# Команда запуска с Gunicorn
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "app:app"]
