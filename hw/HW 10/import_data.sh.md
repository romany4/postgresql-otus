#!/bin/bash
echo "Начинаем импорт данных в ClickHouse..."

# Функция для импорта
import_to_clickhouse() {
    local file=$1
    local table=$2
    
    if [ -f "$file" ]; then
        echo "Импорт $file в таблицу $table"
        cat "$file" | docker run -i --rm --network=container:some-clickhouse-server \
            --entrypoint clickhouse-client clickhouse/clickhouse-server \
            --query="INSERT INTO bookings.$table FORMAT CSVWithNames"
        echo "$table - импортировано"
    else
        echo "Файл $file не найден"
    fi
}

# Импортируем все таблицы
import_to_clickhouse airplanes_data.csv airplanes_data
import_to_clickhouse airports_data.csv airports_data
import_to_clickhouse bookings.csv bookings
import_to_clickhouse tickets.csv tickets
import_to_clickhouse flights.csv flights
import_to_clickhouse routes.csv routes
import_to_clickhouse segments.csv segments
import_to_clickhouse boarding_passes.csv boarding_passes
import_to_clickhouse seats.csv seats

echo "Импорт всех данных завершен!"