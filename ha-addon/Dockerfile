ARG BUILD_FROM
FROM $BUILD_FROM

# Instalace závislostí
RUN apk add --no-cache \
    python3 \
    py3-pip \
    openssh \
    curl \
    bash

WORKDIR /app

# Python závislosti
COPY app/requirements.txt .
RUN pip3 install --no-cache-dir --break-system-packages -r requirements.txt

# Aplikace
COPY app/ .

# Startup skript
COPY run.sh /run.sh
RUN chmod +x /run.sh

CMD ["/run.sh"]
