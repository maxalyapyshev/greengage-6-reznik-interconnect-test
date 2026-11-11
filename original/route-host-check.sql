SELECT r.source_seg, s.hostname AS source_host, r.target_seg, t.hostname AS target_host, r.route_key,
       CASE WHEN s.hostname = t.hostname THEN 'INTRA_HOST' ELSE 'INTER_HOST' END AS path_type
FROM public.interconnect_universal_routes r
JOIN gp_segment_configuration s ON s.content=r.source_seg AND s.role='p'
JOIN gp_segment_configuration t ON t.content=r.target_seg AND t.role='p'
ORDER BY r.source_seg;
SELECT count(*) FILTER (WHERE s.hostname <> t.hostname) AS inter_host_routes,
       count(*) FILTER (WHERE s.hostname = t.hostname) AS intra_host_routes
FROM public.interconnect_universal_routes r
JOIN gp_segment_configuration s ON s.content=r.source_seg AND s.role='p'
JOIN gp_segment_configuration t ON t.content=r.target_seg AND t.role='p';