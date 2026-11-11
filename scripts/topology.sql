DO $$
BEGIN
 IF (SELECT count(*) FROM gp_segment_configuration WHERE content=-1 AND role='p' AND status='u') <> 1
 OR (SELECT count(*) FROM gp_segment_configuration WHERE content=-1 AND role='m' AND status='u') <> 1
 OR (SELECT count(*) FROM gp_segment_configuration WHERE content>=0 AND role='p') <> 8
 OR (SELECT count(*) FROM gp_segment_configuration WHERE content>=0 AND role='m') <> 8
 OR (SELECT count(DISTINCT hostname) FROM gp_segment_configuration WHERE content>=0 AND role='p') <> 2
 OR EXISTS (SELECT 1 FROM gp_segment_configuration WHERE content>=0 AND (status<>'u' OR mode<>'s' OR role<>preferred_role))
 OR EXISTS (SELECT hostname FROM gp_segment_configuration WHERE content>=0 AND role='p' GROUP BY hostname HAVING count(*)<>4)
 OR EXISTS (SELECT 1 FROM gp_segment_configuration p JOIN gp_segment_configuration m ON p.content=m.content
            WHERE p.content>=0 AND p.role='p' AND m.role='m' AND p.hostname=m.hostname)
 THEN RAISE EXCEPTION 'Topology/health mismatch: expected 2 hosts x 4 primary, remote synchronized mirrors and standby';
 END IF;
END $$;
SELECT 'TOPOLOGY_OK' AS result;
