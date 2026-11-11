-- Универсальная подготовка теста широких строк для Greenplum/ADB.
-- Запускать через psql от пользователя, имеющего права CREATE в public.
-- Параметры можно изменить перед запуском.

\set row_count 200000
\set candidate_count 1000000
-- 0 = принять фактическое число хостов; 4 = жёстко проверить топологию 4xN.
\set expected_hosts 0

-- Проверяем фактическую топологию. Количество сегментов важнее количества хостов.
SELECT count(DISTINCT hostname) AS actual_primary_hosts,
       count(*) AS actual_primary_segments
FROM gp_segment_configuration
WHERE role = 'p' AND content >= 0;

-- Проверка expected_hosts выполняется отдельным запросом, поскольку psql
-- не подставляет переменные внутри dollar-quoted DO-блока.
SELECT CASE WHEN :expected_hosts = 0 OR count(DISTINCT hostname) = :expected_hosts THEN 'OK'
            ELSE 'ERROR: expected ' || :expected_hosts || ' hosts, found ' || count(DISTINCT hostname)
       END AS topology_check
FROM gp_segment_configuration
WHERE role = 'p' AND content >= 0;

DROP TABLE IF EXISTS public.interconnect_universal_seed;
DROP TABLE IF EXISTS public.interconnect_universal_route_keys;
DROP TABLE IF EXISTS public.interconnect_universal_routes;

-- Исходные данные: около 205 МБ payload на весь кластер.
CREATE TABLE public.interconnect_universal_seed
(
    id      integer NOT NULL,
    payload text    NOT NULL
)
WITH (appendonly = false)
DISTRIBUTED BY (id);

INSERT INTO public.interconnect_universal_seed (id, payload)
SELECT g, repeat(md5(g::text), 32)
FROM generate_series(1, :row_count) AS s(g);

ANALYZE public.interconnect_universal_seed;

-- Получаем фактический список primary-сегментов из самих данных.
-- При достаточном количестве строк здесь будет одна группа на каждый сегмент.
CREATE TEMP TABLE universal_segments
(
    source_seg integer NOT NULL,
    hostname   text    NOT NULL,
    host_no    integer NOT NULL,
    host_count integer NOT NULL,
    host_seg_count integer NOT NULL,
    host_rn    integer NOT NULL
)
ON COMMIT PRESERVE ROWS;

-- Берём topology из gp_segment_configuration. Это важно для схем, где на
-- каждом хосте находится несколько primary-сегментов: номера сегментов сами
-- по себе не гарантируют переход на другой физический сервер.
INSERT INTO universal_segments (source_seg, hostname, host_no, host_count, host_seg_count, host_rn)
WITH primary_segments AS
(
    SELECT content AS source_seg,
           hostname,
           count(*) OVER (PARTITION BY hostname)::integer AS host_seg_count,
           row_number() OVER (PARTITION BY hostname ORDER BY content)::integer AS host_rn
    FROM gp_segment_configuration
    WHERE role = 'p' AND content >= 0
), host_numbers AS
(
    SELECT hostname,
           row_number() OVER (ORDER BY hostname)::integer AS host_no,
           count(*) OVER ()::integer AS host_count
    FROM (SELECT DISTINCT hostname FROM primary_segments) h
)
SELECT s.source_seg,
       s.hostname,
       h.host_no,
       h.host_count,
       s.host_seg_count,
       s.host_rn
FROM primary_segments s
JOIN host_numbers h USING (hostname);

-- Подбираем route_key для каждого фактического сегмента.
-- Это небольшой одноразовый служебный набор. Он позволяет не знать заранее,
-- как Greenplum хеширует DISTRIBUTED BY-ключи.
CREATE TEMP TABLE universal_route_candidates
(
    route_key integer NOT NULL
)
ON COMMIT PRESERVE ROWS
DISTRIBUTED BY (route_key);

INSERT INTO universal_route_candidates
SELECT g
FROM generate_series(1, :candidate_count) AS s(g);

CREATE TEMP TABLE universal_route_key_by_segment
(
    target_seg integer NOT NULL,
    route_key  integer NOT NULL
)
ON COMMIT PRESERVE ROWS;

INSERT INTO universal_route_key_by_segment
SELECT gp_segment_id AS target_seg,
       min(route_key) AS route_key
FROM universal_route_candidates
GROUP BY gp_segment_id;

SELECT CASE WHEN (SELECT count(*) FROM universal_segments) = (SELECT count(*) FROM universal_route_key_by_segment)
            THEN 'OK'
            ELSE 'ERROR: route candidates do not cover all segments'
       END AS route_key_check;

-- Кольцо маршрутов между физическими хостами. Каждый source-хост отправляет
-- данные на следующий host_no, а номер сегмента внутри хоста сохраняется по
-- возможности. Поэтому при топологии 4 хоста x 4 сегмента получаем 16
-- межхостовых направлений, а не случайные переходы между сегментами.
CREATE TABLE public.interconnect_universal_routes
(
    source_seg integer NOT NULL,
    target_seg integer NOT NULL,
    route_key  integer NOT NULL
)
WITH (appendonly = false)
DISTRIBUTED RANDOMLY;

INSERT INTO public.interconnect_universal_routes
WITH next_host AS
(
    SELECT s.source_seg,
           s.host_rn,
           th.hostname AS target_hostname,
           th.host_seg_count AS target_host_seg_count
    FROM universal_segments s
    JOIN (SELECT DISTINCT hostname, host_no, host_count, host_seg_count FROM universal_segments) th
      ON th.host_no = CASE WHEN s.host_no = s.host_count THEN 1 ELSE s.host_no + 1 END
), next_segment AS
(
    SELECT n.source_seg,
           t.source_seg AS target_seg
    FROM next_host n
    JOIN universal_segments t
      ON t.hostname = n.target_hostname
     AND t.host_rn = ((n.host_rn - 1) % n.target_host_seg_count) + 1
)
SELECT n.source_seg,
       n.target_seg,
       k.route_key
FROM next_segment n
JOIN universal_route_key_by_segment k
  ON k.target_seg = n.target_seg;

ANALYZE public.interconnect_universal_routes;

-- Контроль маршрутизации.
-- SELECT *
-- FROM public.interconnect_universal_routes
-- ORDER BY source_seg;

-- Контрольный тест.
-- Параметры нужно передать при установлении соединения:
-- PGOPTIONS='-c gp_interconnect_type=tcp -c gp_max_packet_size=65507'
SET optimizer = off;
SET enable_mergejoin = off;
SET memory_spill_ratio = 0;
SET statement_mem = '128MB';
SET statement_timeout = '60s';

SELECT sum(octet_length(w.payload || coalesce(k.route_key::text, '')))
FROM
(
    SELECT r.route_key,
           repeat(s.payload, 32) AS payload
    FROM public.interconnect_universal_seed s
    JOIN public.interconnect_universal_routes r
      ON r.source_seg = s.gp_segment_id
    OFFSET 0
) w
FULL JOIN public.interconnect_universal_routes k
  ON k.route_key = w.route_key;

-- В отличие от кластерно-специфичной версии, ожидаемое число байт здесь
-- зависит от числа сегментов и топологии; проверяйте результат фактически.
