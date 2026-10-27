FROM python:3.12-slim

# Sin ficheros .pyc y con la salida sin buffer para ver los logs al momento
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Primero las dependencias: esta capa se reutiliza mientras no cambie requirements.txt
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

# No ejecutar la aplicación como root
RUN useradd --uid 1000 --no-create-home appuser
USER appuser

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
