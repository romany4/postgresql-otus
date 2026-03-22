SET CLUSTER SETTING sql.defaults.vectorize = 'on';

-- Пересоздаём БД чисто
DROP DATABASE IF EXISTS demo CASCADE;
CREATE DATABASE demo;
USE demo;

CREATE SCHEMA IF NOT EXISTS bookings;

CREATE TABLE bookings.airplanes_data (
    airplane_code   STRING(3)   NOT NULL,
    model           JSONB       NOT NULL,
    range           INT8        NOT NULL,
    speed           INT8        NOT NULL,
    CONSTRAINT airplanes_data_pkey PRIMARY KEY (airplane_code),
    CONSTRAINT airplanes_data_range_check CHECK (range > 0),
    CONSTRAINT airplanes_data_speed_check CHECK (speed > 0)
);

-- VIEW вместо функции lang() — хардкод 'en'
CREATE VIEW bookings.airplanes AS
    SELECT
        airplane_code,
        jsonb_extract_path_text(model, 'en') AS model,
        range,
        speed
    FROM bookings.airplanes_data;

CREATE TABLE bookings.airports_data (
    airport_code    STRING(3)   NOT NULL,
    airport_name    JSONB       NOT NULL,
    city            JSONB       NOT NULL,
    country         JSONB       NOT NULL,
    longitude       FLOAT       NULL,           -- было: coordinates point
    latitude        FLOAT       NULL,
    timezone        STRING      NOT NULL,
    CONSTRAINT airports_data_pkey PRIMARY KEY (airport_code)
);

CREATE VIEW bookings.airports AS
    SELECT
        airport_code,
        jsonb_extract_path_text(airport_name, 'en') AS airport_name,
        jsonb_extract_path_text(city, 'en')         AS city,
        jsonb_extract_path_text(country, 'en')      AS country,
        longitude,
        latitude,
        timezone
    FROM bookings.airports_data;

CREATE TABLE bookings.bookings (
    book_ref        STRING(6)       NOT NULL,
    book_date       TIMESTAMPTZ     NOT NULL,
    total_amount    DECIMAL(10, 2)  NOT NULL,
    CONSTRAINT bookings_pkey PRIMARY KEY (book_ref)
);

CREATE TABLE bookings.tickets (
    ticket_no       STRING          NOT NULL,
    book_ref        STRING(6)       NOT NULL,
    passenger_id    STRING          NOT NULL,
    passenger_name  STRING          NOT NULL,
    outbound        BOOL            NOT NULL,
    CONSTRAINT tickets_pkey PRIMARY KEY (ticket_no),
    CONSTRAINT tickets_book_ref_passenger_id_outbound_key
        UNIQUE (book_ref, passenger_id, outbound)
);

CREATE TABLE bookings.seats (
    airplane_code   STRING(3)   NOT NULL,
    seat_no         STRING      NOT NULL,
    fare_conditions STRING      NOT NULL,
    CONSTRAINT seats_pkey PRIMARY KEY (airplane_code, seat_no),
    CONSTRAINT seat_fare_conditions_check
        CHECK (fare_conditions IN ('Economy', 'Comfort', 'Business'))
);

CREATE TABLE bookings.routes (
    route_no            STRING          NOT NULL,
    validity_start      TIMESTAMPTZ     NOT NULL,
    validity_end        TIMESTAMPTZ     NOT NULL,
    departure_airport   STRING(3)       NOT NULL,
    arrival_airport     STRING(3)       NOT NULL,
    airplane_code       STRING(3)       NOT NULL,
    days_of_week        STRING          NOT NULL,   -- "1,2,3,4,5,6,7"
    scheduled_time      TIME            NOT NULL,
    duration            INTERVAL        NOT NULL,
    CONSTRAINT routes_pkey PRIMARY KEY (route_no, validity_start)
);

CREATE INDEX routes_departure_airport_idx ON bookings.routes (departure_airport);
CREATE INDEX routes_validity_idx ON bookings.routes (route_no, validity_start, validity_end);

CREATE TABLE bookings.flights (
    flight_id               INT8        NOT NULL DEFAULT unique_rowid(),
    route_no                STRING      NOT NULL,
    status                  STRING      NOT NULL,
    scheduled_departure     TIMESTAMPTZ NOT NULL,
    scheduled_arrival       TIMESTAMPTZ NOT NULL,
    actual_departure        TIMESTAMPTZ NULL,
    actual_arrival          TIMESTAMPTZ NULL,
    CONSTRAINT flights_pkey PRIMARY KEY (flight_id),
    CONSTRAINT flights_route_no_scheduled_departure_key
        UNIQUE (route_no, scheduled_departure),
    CONSTRAINT flight_status_check CHECK (
        status IN ('Scheduled','On Time','Delayed','Boarding','Departed','Arrived','Cancelled')
    ),
    CONSTRAINT flights_times_check CHECK (
        scheduled_arrival > scheduled_departure
    )
);

CREATE INDEX flights_route_no_idx ON bookings.flights (route_no);
CREATE INDEX flights_scheduled_departure_idx ON bookings.flights (scheduled_departure);

CREATE TABLE bookings.segments (
    ticket_no       STRING          NOT NULL,
    flight_id       INT8            NOT NULL,
    fare_conditions STRING          NOT NULL,
    price           DECIMAL(10, 2)  NOT NULL,
    CONSTRAINT segments_pkey PRIMARY KEY (ticket_no, flight_id),
    CONSTRAINT segments_fare_conditions_check
        CHECK (fare_conditions IN ('Economy', 'Comfort', 'Business')),
    CONSTRAINT segments_price_check CHECK (price >= 0)
);

CREATE INDEX segments_flight_id_idx ON bookings.segments (flight_id);

CREATE TABLE bookings.boarding_passes (
    ticket_no       STRING      NOT NULL,
    flight_id       INT8        NOT NULL,
    seat_no         STRING      NOT NULL,
    boarding_no     INT8        NULL,
    boarding_time   TIMESTAMPTZ NULL,
    CONSTRAINT boarding_passes_pkey PRIMARY KEY (ticket_no, flight_id),
    CONSTRAINT boarding_passes_flight_id_boarding_no_key
        UNIQUE (flight_id, boarding_no),
    CONSTRAINT boarding_passes_flight_id_seat_no_key
        UNIQUE (flight_id, seat_no)
);

-- =============================================================================
-- Внешние ключи — добавляем ПОСЛЕ создания всех таблиц
-- =============================================================================
ALTER TABLE bookings.routes
    ADD CONSTRAINT routes_airplane_code_fkey
        FOREIGN KEY (airplane_code) REFERENCES bookings.airplanes_data(airplane_code);

ALTER TABLE bookings.routes
    ADD CONSTRAINT routes_departure_airport_fkey
        FOREIGN KEY (departure_airport) REFERENCES bookings.airports_data(airport_code);

ALTER TABLE bookings.routes
    ADD CONSTRAINT routes_arrival_airport_fkey
        FOREIGN KEY (arrival_airport) REFERENCES bookings.airports_data(airport_code);

ALTER TABLE bookings.seats
    ADD CONSTRAINT seats_airplane_code_fkey
        FOREIGN KEY (airplane_code) REFERENCES bookings.airplanes_data(airplane_code);

ALTER TABLE bookings.tickets
    ADD CONSTRAINT tickets_book_ref_fkey
        FOREIGN KEY (book_ref) REFERENCES bookings.bookings(book_ref);

ALTER TABLE bookings.flights
    ADD CONSTRAINT flights_route_no_fkey
        FOREIGN KEY (route_no) REFERENCES bookings.routes(route_no);  -- упрощённый FK

ALTER TABLE bookings.segments
    ADD CONSTRAINT segments_ticket_no_fkey
        FOREIGN KEY (ticket_no) REFERENCES bookings.tickets(ticket_no);

ALTER TABLE bookings.segments
    ADD CONSTRAINT segments_flight_id_fkey
        FOREIGN KEY (flight_id) REFERENCES bookings.flights(flight_id);

ALTER TABLE bookings.boarding_passes
    ADD CONSTRAINT boarding_passes_ticket_no_flight_id_fkey
        FOREIGN KEY (ticket_no, flight_id) REFERENCES bookings.segments(ticket_no, flight_id);

SHOW TABLES FROM bookings;
