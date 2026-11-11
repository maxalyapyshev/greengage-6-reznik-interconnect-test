Тест ADB Interconnect
Запускать на координаторе от gpadmin с загруженным окружением ADB. Нужны bash и psql. База данных в скриптах: adb.
Подготовка — один раз перед тестами
Подготовка пересоздаёт тестовые таблицы public.interconnect_universal_seed и public.interconnect_universal_routes, генерирует данные и выполняет один контрольный запрос. Не запускать подготовку одновременно с нагрузкой.
bash
PGOPTIONS='-c gp_interconnect_type=tcp -c gp_max_packet_size=65507' \
psql -X -v ON_ERROR_STOP=1 -d adb -f interconnect-universal-setup.sql
В начале SQL задаются row_count и candidate_count. Топология определяется автоматически. Проверки topology_check и route_key_check должны вывести OK; эти диагностические SELECT сами по себе не останавливают выполнение при несовпадении.
Проверка маршрутов
bash
psql -X -v ON_ERROR_STOP=1 -d adb -f route-host-check.sql
Все маршруты должны быть INTER_HOST, внутрихостовых — 0. Сценарий рассчитан на несколько primary-хостов; равномерное количество primary-сегментов на хостах обеспечивает взаимно однозначные маршруты кольца.
Нагрузка
bash
IC_PACKET=65507 bash interconnect-universal-load.sh tcp 4 10 128 128
Позиционные параметры: транспорт, число клиентских сессий, число запросов на сессию, множитель payload, глубина очередей Interconnect.
Пример UDPIFC для подтверждённого сквозного jumbo MTU:
bash
IC_PACKET=8192 bash interconnect-universal-load.sh udpifc 4 10 128 128
Для первоначального контрольного запуска используйте 1 сессию и 1 повтор. В скрипте установлен statement_timeout=60s на каждый запрос. Результаты и время выводятся после завершения workers; для сохранения вывода:
bash
set -o pipefail
IC_PACKET=65507 bash interconnect-universal-load.sh tcp 4 10 128 128 2>&1 | tee load.log
