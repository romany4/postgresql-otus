FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive

# Добавляем PostgreSQL для Debian 13
RUN apt-get update && apt-get install -y curl ca-certificates gnupg lsb-release \
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
       | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg \
    && echo "deb http://apt.postgresql.org/pub/repos/apt trixie-pgdg main" \
       > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update && apt-get install -y \
       postgresql-15 \
       postgresql-client-15 \
       python3 \
       python3-pip \
       python3-psycopg2 \
       libpq-dev \
    && pip3 install patroni[etcd3] --break-system-packages \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Создаём директорию для данных и передаём владение пользователю postgres
# initdb и postgres не могут запускаться от root
RUN mkdir -p /var/lib/postgresql/15/data \
    && chown -R postgres:postgres /var/lib/postgresql \
    && chmod 700 /var/lib/postgresql/15/data

# Создаём директорию для конфига Patroni
RUN mkdir -p /etc/patroni && chown postgres:postgres /etc/patroni

# Создаём директорию для логов
RUN mkdir -p /var/log/postgresql && chown postgres:postgres /var/log/postgresql

# Все дальнейшие команды и запуск — от пользователя postgres
USER postgres

EXPOSE 5432 8008

CMD ["patroni", "/etc/patroni/patroni.yml"]
