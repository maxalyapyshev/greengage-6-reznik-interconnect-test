DO $$
BEGIN
 IF (SELECT count(*) FROM public.interconnect_universal_routes) <> 8
 OR (SELECT count(DISTINCT source_seg) FROM public.interconnect_universal_routes) <> 8
 OR (SELECT count(DISTINCT target_seg) FROM public.interconnect_universal_routes) <> 8
 OR (SELECT count(DISTINCT route_key) FROM public.interconnect_universal_routes) <> 8
 OR (SELECT count(*) FROM public.interconnect_universal_routes r
     JOIN gp_segment_configuration s ON s.content=r.source_seg AND s.role='p'
     JOIN gp_segment_configuration t ON t.content=r.target_seg AND t.role='p'
     WHERE s.hostname<>t.hostname) <> 8
 THEN RAISE EXCEPTION 'Expected 8 valid one-to-one inter-host routes';
 END IF;
END $$;
SELECT 'ROUTES_OK: 8 INTER_HOST, 0 INTRA_HOST' AS result;
