#!/bin/bash

set -e

PG_HOST="localhost"
PG_PORT="5432"
PG_USER="postgres"
PG_DB="demo"
CSV_DIR="/tmp/crdb_import"
LOG_FILE="/tmp/crdb_export.log"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"; }
err() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; exit 1; }

log "=== Начало экспорта ==="
log "БД: $PG_DB на $PG_HOST:$PG_PORT"

mkdir -p "$CSV_DIR"
> "$LOG_FILE"

PSQL="psql -h $PG_HOST -p $PG_PORT -U $PG_USER -d $PG_DB -v ON_ERROR_STOP=1"

# =============================================================================
# Проверка подключения
# =============================================================================
log "Проверка подключения к PostgreSQL..."
$PSQL -c "SELECT bookings.version();" || err "Не удалось подключиться к БД"

log "Экспорт airplanes_data..."
$PSQL -c "\COPY (
    SELECT
        airplane_code,
        model::text,         -- jsonb -> text, в CRDB останется jsonb
        range,
        speed
    FROM bookings.airplanes_data
) TO '$CSV_DIR/airplanes_data.csv' CSV HEADER"
log "  airplanes_data: $(wc -l < $CSV_DIR/airplanes_data.csv) строк"

log "Экспорт airports_data..."
$PSQL -c "\COPY (
    SELECT
        airport_code,
        airport_name::text,
        city::text,
        country::text,
        coordinates[0] AS longitude,   -- разбиваем point на два float
        coordinates[1] AS latitude,
        timezone
    FROM bookings.airports_data
) TO '$CSV_DIR/airports_data.csv' CSV HEADER"
log "  airports_data: $(wc -l < $CSV_DIR/airports_data.csv) строк"

log "Экспорт bookings..."
$PSQL -c "\COPY (
    SELECT book_ref, book_date, total_amount
    FROM bookings.bookings
) TO '$CSV_DIR/bookings.csv' CSV HEADER"
log "  bookings: $(wc -l < $CSV_DIR/bookings.csv) строк"

log "Экспорт seats..."
$PSQL -c "\COPY (
    SELECT airplane_code, seat_no, fare_conditions
    FROM bookings.seats
) TO '$CSV_DIR/seats.csv' CSV HEADER"
log "  seats: $(wc -l < $CSV_DIR/seats.csv) строк"

log "Экспорт routes..."
$PSQL -c "\COPY (
    SELECT
        route_no,
        lower(validity) AS validity_start,
        upper(validity) AS validity_end,
        departure_airport,
        arrival_airport,
        airplane_code,
        array_to_string(days_of_week, ',') AS days_of_week,  -- int[] -> text
        scheduled_time,
        duration
    FROM bookings.routes
) TO '$CSV_DIR/routes.csv' CSV HEADER"
log "  routes: $(wc -l < $CSV_DIR/routes.csv) строк"

log "Экспорт flights..."
$PSQL -c "\COPY (
    SELECT
        flight_id,
        route_no,
        status,
        scheduled_departure,
        scheduled_arrival,
        actual_departure,
        actual_arrival
    FROM bookings.flights
) TO '$CSV_DIR/flights.csv' CSV HEADER"
log "  flights: $(wc -l < $CSV_DIR/flights.csv) строк"

log "Экспорт tickets..."
$PSQL -c "\COPY (
    SELECT ticket_no, book_ref, passenger_id, passenger_name, outbound
    FROM bookings.tickets
) TO '$CSV_DIR/tickets.csv' CSV HEADER"
log "  tickets: $(wc -l < $CSV_DIR/tickets.csv) строк"

log "Экспорт segments (большая таблица, может занять время)..."
START=$(date +%s)
$PSQL -c "\COPY (
    SELECT ticket_no, flight_id, fare_conditions, price
    FROM bookings.segments
) TO '$CSV_DIR/segments.csv' CSV HEADER"
END=$(date +%s)
log "  segments: $(wc -l < $CSV_DIR/segments.csv) строк, время: $((END-START))s"

log "Экспорт boarding_passes (самая большая таблица)..."
START=$(date +%s)
$PSQL -c "\COPY (
    SELECT ticket_no, flight_id, seat_no, boarding_no, boarding_time
    FROM bookings.boarding_passes
) TO '$CSV_DIR/boarding_passes.csv' CSV HEADER"
END=$(date +%s)
log "  boarding_passes: $(wc -l < $CSV_DIR/boarding_passes.csv) строк, время: $((END-START))s"

log "Упаковка CSV файлов..."
cd /tmp
tar -czf crdb_import.tar.gz crdb_import/
log "Архив: /tmp/crdb_import.tar.gz ($(du -sh /tmp/crdb_import.tar.gz | cut -f1))"

log ""
log "=== Экспорт завершён ==="
log "Файлы в $CSV_DIR:"
ls -lh "$CSV_DIR"/*.csv | awk '{print "  " $5 "\t" $9}' | tee -a "$LOG_FILE"

log ""
log "Следующий шаг: загрузить архив в Yandex Object Storage:"
log "  yc storage object put --bucket crdb-demo-import --file /tmp/crdb_import.tar.gz"
log "  или по одному:"
log "  for f in $CSV_DIR/*.csv; do"
log "    yc storage object put --bucket crdb-demo-import --file \$f"
log "  done"
