<?php

declare(strict_types=1);

const PG_HOST    = '127.0.0.1';
const PG_PORT    = 5432;
const PG_DB      = 'demo';
const PG_USER    = 'postgres';
const PG_PASS    = '';

const CRDB_HOST  = 'cdb1';
const CRDB_PORT  = 26257;
const CRDB_DB    = 'demo';
const CRDB_USER  = 'root';
const CRDB_CERTS = '/opt/cockroach/certs';

const ITERATIONS  = 5;               // прогонов каждого запроса
const WARMUP_RUNS = 1;               // прогревочных прогонов (не считаем)
const OUTPUT_JSON = false;           // переключается флагом --json

$queries = [

    // Q1: Агрегация по месяцам — базовый тест GROUP BY + DATE_TRUNC
    'Q1_revenue_by_month' => [
        'description' => 'Выручка по месяцам бронирования',
        'sql' => "
            SELECT
                date_trunc('month', book_date) AS month,
                count(*)                        AS bookings_count,
                sum(total_amount)               AS revenue,
                avg(total_amount)               AS avg_amount,
                min(total_amount)               AS min_amount,
                max(total_amount)               AS max_amount
            FROM bookings.bookings
            GROUP BY 1
            ORDER BY 1
        ",
    ],

    // Q2: JOIN двух больших таблиц — segments + flights
    'Q2_popular_routes' => [
        'description' => 'Топ-20 популярных маршрутов по выручке',
        'sql' => "
            SELECT
                r.departure_airport,
                r.arrival_airport,
                count(*)          AS flights_count,
                sum(s.price)      AS total_revenue,
                avg(s.price)      AS avg_price,
                min(s.price)      AS min_price,
                max(s.price)      AS max_price
            FROM bookings.flights f
            JOIN bookings.routes r
                ON r.route_no = f.route_no
            JOIN bookings.segments s
                ON s.flight_id = f.flight_id
            WHERE f.status = 'Arrived'
            GROUP BY r.departure_airport, r.arrival_airport
            ORDER BY total_revenue DESC
            LIMIT 20
        ",
    ],

    // Q3: Аналитика пассажиров — JOIN 4 таблиц
    'Q3_passenger_stats' => [
        'description' => 'Топ-50 пассажиров по суммарным тратам',
        'sql' => "
            SELECT
                t.passenger_id,
                t.passenger_name,
                count(DISTINCT t.ticket_no)  AS tickets_count,
                count(DISTINCT s.flight_id)  AS flights_count,
                sum(s.price)                 AS total_spent,
                avg(s.price)                 AS avg_segment_price
            FROM bookings.tickets t
            JOIN bookings.segments s ON s.ticket_no = t.ticket_no
            GROUP BY t.passenger_id, t.passenger_name
            ORDER BY total_spent DESC
            LIMIT 50
        ",
    ],

    // Q4: Window function — нарастающий итог (потенциально медленнее в CRDB)
    'Q4_cumulative_revenue' => [
        'description' => 'Нарастающая выручка по дням (window function)',
        'sql' => "
            SELECT
                day,
                daily_revenue,
                sum(daily_revenue) OVER (ORDER BY day) AS cumulative_revenue,
                avg(daily_revenue) OVER (
                    ORDER BY day
                    ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
                ) AS revenue_7day_avg
            FROM (
                SELECT
                    date_trunc('day', book_date) AS day,
                    sum(total_amount)            AS daily_revenue
                FROM bookings.bookings
                GROUP BY 1
            ) daily
            ORDER BY day
        ",
    ],

    // Q5: Загруженность рейсов — JOIN 3 таблиц + агрегация
    'Q5_flight_occupancy' => [
        'description' => 'Загруженность рейсов (посадочные vs места)',
        'sql' => "
            SELECT
                f.flight_id,
                r.departure_airport,
                r.arrival_airport,
                r.airplane_code,
                count(bp.ticket_no)  AS boarded_passengers,
                count(se.seat_no)    AS total_seats,
                CASE
                    WHEN count(se.seat_no) > 0
                    THEN round(
                        count(bp.ticket_no)::numeric / count(se.seat_no) * 100,
                        2
                    )
                    ELSE 0
                END AS occupancy_pct
            FROM bookings.flights f
            JOIN bookings.routes r
                ON r.route_no = f.route_no
            LEFT JOIN bookings.boarding_passes bp
                ON bp.flight_id = f.flight_id
            LEFT JOIN bookings.seats se
                ON se.airplane_code = r.airplane_code
            WHERE f.status = 'Arrived'
            GROUP BY f.flight_id, r.departure_airport, r.arrival_airport, r.airplane_code
            ORDER BY occupancy_pct DESC
            LIMIT 100
        ",
    ],

    // Q6: Статус рейсов — простой GROUP BY для сравнения с README
    'Q6_flights_by_status' => [
        'description' => 'Статистика рейсов по статусам (как в README)',
        'sql' => "
            SELECT
                status,
                count(*)                     AS cnt,
                min(scheduled_departure)     AS min_departure,
                max(scheduled_departure)     AS max_departure
            FROM bookings.flights
            GROUP BY status
            ORDER BY min_departure
        ",
    ],
];

function connectPostgres(): PDO
{
    $dsn = sprintf(
        'pgsql:host=%s;port=%d;dbname=%s',
        PG_HOST, PG_PORT, PG_DB
    );
    $pdo = new PDO($dsn, PG_USER, PG_PASS, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_TIMEOUT => 600,
    ]);
    $pdo->exec("SET search_path TO bookings, public");
    return $pdo;
}

function connectCockroachDB(): PDO
{
    // CockroachDB использует PostgreSQL wire protocol
    $dsn = sprintf(
        'pgsql:host=%s;port=%d;dbname=%s;sslmode=verify-full;sslrootcert=%s/ca.crt;sslcert=%s/client.root.crt;sslkey=%s/client.root.key',
        CRDB_HOST, CRDB_PORT, CRDB_DB,
        CRDB_CERTS, CRDB_CERTS, CRDB_CERTS
    );
    $pdo = new PDO($dsn, CRDB_USER, '', [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_TIMEOUT => 600,
    ]);
    $pdo->exec("SET search_path TO bookings");
    return $pdo;
}

function runQuery(PDO $pdo, string $sql): array
{
    $start = hrtime(true);
    $stmt  = $pdo->query($sql);
    $rows  = $stmt->fetchAll(PDO::FETCH_ASSOC);
    $end   = hrtime(true);

    return [
        'time_ms'   => ($end - $start) / 1_000_000,
        'row_count' => count($rows),
    ];
}

function benchmark(PDO $pdo, string $dbName, array $queries): array
{
    $results = [];

    foreach ($queries as $name => $query) {
        $sql = trim($query['sql']);
        echo "  [$dbName] $name ";

        for ($i = 0; $i < WARMUP_RUNS; $i++) {
            runQuery($pdo, $sql);
            echo ".";
        }

        $times  = [];
        $rowCount = 0;
        for ($i = 0; $i < ITERATIONS; $i++) {
            $run      = runQuery($pdo, $sql);
            $times[]  = $run['time_ms'];
            $rowCount = $run['row_count'];
            echo ".";
        }

        sort($times);
        $avg    = array_sum($times) / count($times);
        $median = $times[(int)(count($times) / 2)];

        $results[$name] = [
            'min_ms'    => round(min($times), 2),
            'max_ms'    => round(max($times), 2),
            'avg_ms'    => round($avg, 2),
            'median_ms' => round($median, 2),
            'row_count' => $rowCount,
            'runs'      => array_map(fn($t) => round($t, 2), $times),
        ];

        echo sprintf(
            " avg=%.0fms median=%.0fms rows=%d\n",
            $avg, $median, $rowCount
        );
    }

    return $results;
}

function printComparison(array $queries, array $pgResults, array $crdbResults): void
{
    $line = str_repeat('-', 90);
    echo "\n$line\n";
    echo sprintf(
        "%-30s | %10s | %10s | %10s | %s\n",
        'Запрос', 'PG avg ms', 'CRDB avg ms', 'Разница %', 'Победитель'
    );
    echo "$line\n";

    foreach ($queries as $name => $query) {
        $pg   = $pgResults[$name]['avg_ms']   ?? null;
        $crdb = $crdbResults[$name]['avg_ms'] ?? null;

        if ($pg === null || $crdb === null) {
            echo sprintf("%-30s | ОШИБКА\n", $name);
            continue;
        }

        $diff    = $pg > 0 ? (($crdb - $pg) / $pg * 100) : 0;
        $winner  = $crdb < $pg ? 'CockroachDB ✓' : 'PostgreSQL  ✓';
        $diffStr = sprintf('%+.1f%%', $diff);

        echo sprintf(
            "%-30s | %10.0f | %10.0f | %10s | %s\n",
            $name, $pg, $crdb, $diffStr, $winner
        );
    }

    echo "$line\n";
}

$outputJson = in_array('--json', $argv ?? [], true);

echo "=== Benchmark: PostgreSQL vs CockroachDB ===\n";
echo "Датасет:    demo-20250901-2y (~11 ГБ)\n";
echo "Итераций:   " . ITERATIONS . " (+ " . WARMUP_RUNS . " прогрев)\n";
echo "Запросов:   " . count($queries) . "\n";
echo str_repeat('=', 50) . "\n\n";

// Подключения
echo "Подключение к PostgreSQL...\n";
try {
    $pgPdo = connectPostgres();
    echo "  OK\n";
} catch (PDOException $e) {
    die("ОШИБКА PostgreSQL: " . $e->getMessage() . "\n");
}

echo "Подключение к CockroachDB...\n";
try {
    $crdbPdo = connectCockroachDB();
    echo "  OK\n";
} catch (PDOException $e) {
    die("ОШИБКА CockroachDB: " . $e->getMessage() . "\n");
}

// Бенчмарк
echo "\n--- PostgreSQL ---\n";
$pgResults = benchmark($pgPdo, 'PostgreSQL', $queries);

echo "\n--- CockroachDB ---\n";
$crdbResults = benchmark($crdbPdo, 'CockroachDB', $queries);

// Итоговая таблица
echo "\n\n=== РЕЗУЛЬТАТЫ ===";
printComparison($queries, $pgResults, $crdbResults);

// Сохраняем JSON
$output = [
    'timestamp'   => date('c'),
    'dataset'     => 'demo-20250901-2y',
    'iterations'  => ITERATIONS,
    'warmup_runs' => WARMUP_RUNS,
    'postgresql'  => [
        'host'    => PG_HOST,
        'version' => $pgPdo->query('SELECT version()')->fetchColumn(),
        'results' => $pgResults,
    ],
    'cockroachdb' => [
        'host'    => CRDB_HOST,
        'version' => $crdbPdo->query('SELECT version()')->fetchColumn(),
        'results' => $crdbResults,
    ],
];

$jsonFile = __DIR__ . '/benchmark_results.json';
file_put_contents($jsonFile, json_encode($output, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));

if ($outputJson) {
    echo json_encode($output, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);
} else {
    echo "\nРезультаты сохранены: $jsonFile\n";
}
