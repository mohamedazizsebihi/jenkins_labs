FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# Version injectée par le pipeline (--build-arg APP_VERSION=<n° de build>).
# Déclarée APRÈS l'installation des dépendances pour ne pas invalider le cache des couches.
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}
LABEL org.opencontainers.image.version=${APP_VERSION}

EXPOSE 5000
USER nobody
CMD ["python", "app.py"]
