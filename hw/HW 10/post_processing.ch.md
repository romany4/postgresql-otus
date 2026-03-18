USE bookings;

-- Пересоздаем таблицы с правильными типами дат
CREATE TABLE bookings_final
ENGINE = MergeTree()
ORDER BY (book_ref, book_date) AS
SELECT 
    book_ref,
    parseDateTime64BestEffort(book_date, 3) as book_date,
    total_amount
FROM bookings;

CREATE TABLE flights_final
ENGINE = MergeTree()
ORDER BY (flight_id, scheduled_departure) AS
SELECT 
    flight_id,
    route_no,
    status,
    parseDateTime64BestEffort(scheduled_departure, 3) as scheduled_departure,
    parseDateTime64BestEffort(scheduled_arrival, 3) as scheduled_arrival,
    if(actual_departure = '', NULL, parseDateTime64BestEffort(actual_departure, 3)) as actual_departure,
    if(actual_arrival = '', NULL, parseDateTime64BestEffort(actual_arrival, 3)) as actual_arrival
FROM flights;

CREATE TABLE boarding_passes_final
ENGINE = MergeTree()
ORDER BY (ticket_no, flight_id) AS
SELECT 
    ticket_no,
    flight_id,
    seat_no,
    boarding_no,
    if(boarding_time = '', NULL, parseDateTime64BestEffort(boarding_time, 3)) as boarding_time
FROM boarding_passes;

-- Остальные таблицы без изменений
CREATE TABLE airports_data_final
ENGINE = MergeTree()
ORDER BY airport_code AS
SELECT 
    airport_code,
    airport_name,
    city,
    country,
    tuple(
        cast(splitByChar(',', replaceAll(replaceAll(coordinates, '(', ''), ')', ''))[1] as Float64),
        cast(splitByChar(',', replaceAll(replaceAll(coordinates, '(', ''), ')', ''))[2] as Float64)
    ) as coordinates,
    timezone
FROM airports_data;

CREATE TABLE routes_final
ENGINE = MergeTree()
ORDER BY (route_no, validity_start) AS
SELECT 
    route_no,
    toDateTime(validity_start) as validity_start,
    toDateTime(validity_end) as validity_end,
    departure_airport,
    arrival_airport,
    airplane_code,
    arrayMap(x -> cast(x as UInt8), splitByString(',', days_of_week)) as days_of_week,
    scheduled_time,
    duration_seconds
FROM routes;

-- Создаем представления
CREATE VIEW airplanes AS
SELECT 
    airplane_code,
    JSONExtractString(model, 'en') as model,
    range,
    speed
FROM airplanes_data;

CREATE VIEW airports AS
SELECT 
    airport_code,
    JSONExtractString(airport_name, 'en') as airport_name,
    JSONExtractString(city, 'en') as city,
    JSONExtractString(country, 'en') as country,
    coordinates,
    timezone
FROM airports_data_final;

-- Добавляем индексы
ALTER TABLE flights_final ADD INDEX status_index status TYPE set(10) GRANULARITY 1;
ALTER TABLE flights_final ADD INDEX departure_index scheduled_departure TYPE minmax GRANULARITY 1;

-- Проверяем данные
SELECT 'bookings_final' as table, count() as count FROM bookings_final
UNION ALL
SELECT 'flights_final', count() FROM flights_final
UNION ALL
SELECT 'airports_data', count() FROM airports_data
UNION ALL
SELECT 'tickets', count() FROM tickets
UNION ALL
SELECT 'routes_final', count() FROM routes_final;