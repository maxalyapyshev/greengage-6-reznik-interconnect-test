SET optimizer=off;
SET enable_mergejoin=off;
EXPLAIN VERBOSE
SELECT sum(octet_length(w.payload || coalesce(k.route_key::text, '')))
FROM (
 SELECT r.route_key, repeat(s.payload,8) AS payload
 FROM public.interconnect_universal_seed s
 JOIN public.interconnect_universal_routes r ON r.source_seg=s.gp_segment_id
 OFFSET 0
) w FULL JOIN public.interconnect_universal_routes k ON k.route_key=w.route_key;
