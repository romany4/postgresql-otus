-- Создаем базу данных
CREATE DATABASE IF NOT EXISTS bookings;
USE bookings;

-- airplanes_data
CREATE TABLE airplanes_data
(
    airplane_code FixedString(3),
    model String,
    range UInt16,
    speed UInt16
)
ENGINE = MergeTree()
ORDER BY airplane_code;

-- airports_data
CREATE TABLE airports_data
(
    airport_code FixedString(3),
    airport_name String,
    city String,
    country String,
    coordinates String,
    timezone String
)
ENGINE = MergeTree()
ORDER BY airport_code;

-- bookings
CREATE TABLE bookings
(
    book_ref FixedString(6),
    book_date String, -- Временно как String для импорта
    total_amount Decimal(10,2)
)
ENGINE = MergeTree()
ORDER BY (book_ref, book_date);

-- tickets
CREATE TABLE tickets
(
    ticket_no String,
    book_ref FixedString(6),
    passenger_id String,
    passenger_name String,
    outbound UInt8
)
ENGINE = MergeTree()
ORDER BY (ticket_no, book_ref);

-- flights
CREATE TABLE flights
(
    flight_id UInt32,
    route_no String,
    status String,
    scheduled_departure String, -- Временно как String
    scheduled_arrival String,   -- Временно как String
    actual_departure String,    -- Временно как String
    actual_arrival String       -- Временно как String
)
ENGINE = MergeTree()
ORDER BY (flight_id, scheduled_departure);

-- routes
CREATE TABLE routes
(
    route_no String,
    validity_start Float64,
    validity_end Float64,
    departure_airport FixedString(3),
    arrival_airport FixedString(3),
    airplane_code FixedString(3),
    days_of_week String,
    scheduled_time String,
    duration_seconds Float64
)
ENGINE = MergeTree()
ORDER BY (route_no, validity_start);

-- segments
CREATE TABLE segments
(
    ticket_no String,
    flight_id UInt32,
    fare_conditions String,
    price Decimal(10,2)
)
ENGINE = MergeTree()
ORDER BY (ticket_no, flight_id);

-- boarding_passes
CREATE TABLE boarding_passes
(
    ticket_no String,
    flight_id UInt32,
    seat_no String,
    boarding_no Nullable(UInt32),
    boarding_time String -- Временно как String
)
ENGINE = MergeTree()
ORDER BY (ticket_no, flight_id);

-- seats
CREATE TABLE seats
(
    airplane_code FixedString(3),
    seat_no String,
    fare_conditions String
)
ENGINE = MergeTree()
ORDER BY (airplane_code, seat_no);