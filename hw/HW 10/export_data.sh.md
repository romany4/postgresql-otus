#!/bin/bash
# Экспорт данных из PostgreSQL в CSV с правильным форматом дат
export PGPASSWORD=postgres123

echo "Начинаем экспорт данных из PostgreSQL с конвертацией дат..."

# airports_data - правильное извлечение координат из типа point
psql -h 10.10.0.20 -U postgres -d demo -c "
COPY (SELECT airport_code, airport_name::text, city::text, country::text, 
             CONCAT('(', (coordinates[0])::numeric(10,6), ',', (coordinates[1])::numeric(10,6), ')') as coordinates,
             timezone 
      FROM bookings.airports_data) 
TO STDOUT WITH CSV HEADER" > airports_data.csv
echo "airports_data.csv - готово"

# bookings - конвертируем timestamp with time zone в timestamp без TZ
psql -h 10.10.0.20 -U postgres -d demo -c "
COPY (SELECT book_ref, 
             to_char(book_date, 'YYYY-MM-DD HH24:MI:SS.US') as book_date,
             total_amount 
      FROM bookings.bookings) 
TO STDOUT WITH CSV HEADER" > bookings.csv
echo "bookings.csv - готово"

# flights - конвертируем timestamp with time zone
psql -h 10.10.0.20 -U postgres -d demo -c "
COPY (SELECT flight_id, route_no, status,
             to_char(scheduled_departure, 'YYYY-MM-DD HH24:MI:SS.US') as scheduled_departure,
             to_char(scheduled_arrival, 'YYYY-MM-DD HH24:MI:SS.US') as scheduled_arrival,
             to_char(actual_departure, 'YYYY-MM-DD HH24:MI:SS.US') as actual_departure,
             to_char(actual_arrival, 'YYYY-MM-DD HH24:MI:SS.US') as actual_arrival
      FROM bookings.flights) 
TO STDOUT WITH CSV HEADER" > flights.csv
echo "flights.csv - готово"

# boarding_passes - конвертируем timestamp with time zone
psql -h 10.10.0.20 -U postgres -d demo -c "
COPY (SELECT ticket_no, flight_id, seat_no, boarding_no,
             to_char(boarding_time, 'YYYY-MM-DD HH24:MI:SS.US') as boarding_time
      FROM bookings.boarding_passes) 
TO STDOUT WITH CSV HEADER" > boarding_passes.csv
echo "boarding_passes.csv - готово"

# Остальные таблицы без изменений
psql -h 10.10.0.20 -U postgres -d demo -c "
COPY (SELECT airplane_code, model::text, range, speed FROM bookings.airplanes_data) 
TO STDOUT WITH CSV HEADER" > airplanes_data.csv
echo "airplanes_data.csv - готово"

psql -h 10.10.0.20 -U postgres -d demo -c "
COPY (SELECT ticket_no, book_ref, passenger_id, passenger_name, 
             CASE WHEN outbound THEN 1 ELSE 0 END as outbound 
      FROM bookings.tickets) 
TO STDOUT WITH CSV HEADER" > tickets.csv
echo "tickets.csv - готово"

psql -h 10.10.0.20 -U postgres -d demo -c "
COPY (SELECT route_no, 
             EXTRACT(epoch FROM lower(validity)) as validity_start,
             EXTRACT(epoch FROM upper(validity)) as validity_end,
             departure_airport, arrival_airport, airplane_code,
             array_to_string(days_of_week, ',') as days_of_week,
             scheduled_time::text,
             EXTRACT(epoch FROM duration) as duration_seconds
      FROM bookings.routes) 
TO STDOUT WITH CSV HEADER" > routes.csv
echo "routes.csv - готово"

psql -h 10.10.0.20 -U postgres -d demo -c "
COPY bookings.segments TO STDOUT WITH CSV HEADER" > segments.csv
echo "segments.csv - готово"

psql -h 10.10.0.20 -U postgres -d demo -c "
COPY bookings.seats TO STDOUT WITH CSV HEADER" > seats.csv
echo "seats.csv - готово"

echo "Экспорт всех данных завершен!"