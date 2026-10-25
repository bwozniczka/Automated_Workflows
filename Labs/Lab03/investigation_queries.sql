-- Diagnostic SQL for Lab 03. Run against state/catalogue.sqlite or cases/*/state/catalogue.sqlite.
SELECT r.run_id,r.command,a.item_id,a.asset_key,s.aoi_key,d.status,d.stage,
       d.network_bytes,d.http_status,d.error_code,d.error_message
FROM download_attempts d JOIN runs r ON r.run_id=d.run_id
JOIN subset_requests s ON s.subset_id=d.subset_id
JOIN assets a ON a.asset_id=s.asset_id
ORDER BY d.started_at,d.attempt_id;

-- Paths, hashes and location state (avoid summing network_bytes after joining locations).
SELECT a.asset_key, s.aoi_key, f.sha256, f.size_bytes, l.local_path, l.status AS location_status,
       d.attempt_id, d.status AS attempt_status, d.network_bytes
FROM subset_requests s
JOIN assets a USING(asset_id)
JOIN artifacts f ON f.artifact_id = s.latest_artifact_id
JOIN artifact_locations l ON l.artifact_id = f.artifact_id
LEFT JOIN download_attempts d ON d.artifact_id = f.artifact_id AND d.subset_id = s.subset_id
ORDER BY a.asset_key, s.aoi_key, d.started_at;

-- Case A: failed band, partial success, and recovery history (use cases/network DB).
SELECT a.asset_key, d.run_id, d.status, d.stage, d.network_bytes, d.error_code, d.error_message,
       d.artifact_id, d.started_at, d.finished_at
FROM download_attempts d
JOIN subset_requests s ON s.subset_id = d.subset_id
JOIN assets a ON a.asset_id = s.asset_id
ORDER BY d.started_at, d.attempt_id;

-- Which band already has an artifact vs none (before/after recovery view).
SELECT a.asset_key, s.status AS request_status, s.latest_artifact_id,
       COUNT(d.attempt_id) AS attempts,
       SUM(CASE WHEN d.status = 'failed' THEN 1 ELSE 0 END) AS failed_attempts,
       SUM(CASE WHEN d.status IN ('succeeded','reused') THEN 1 ELSE 0 END) AS ok_attempts
FROM subset_requests s
JOIN assets a USING(asset_id)
LEFT JOIN download_attempts d ON d.subset_id = s.subset_id
GROUP BY a.asset_key, s.status, s.latest_artifact_id;

-- Case B: historical success vs current location availability (use cases/missing DB).
SELECT a.asset_key, d.status AS attempt_status, d.stage, d.error_code, d.started_at,
       f.sha256, l.status AS location_status, l.checked_at
FROM download_attempts d
JOIN subset_requests s ON s.subset_id = d.subset_id
JOIN assets a ON a.asset_id = s.asset_id
LEFT JOIN artifacts f ON f.artifact_id = COALESCE(d.artifact_id, s.latest_artifact_id)
LEFT JOIN artifact_locations l ON l.artifact_id = f.artifact_id
ORDER BY d.started_at, d.attempt_id;

-- AOI identity: one source band with separate requests for two AOIs.
SELECT a.asset_key, a.asset_id, s.aoi_key, s.subset_id, s.status, s.latest_artifact_id,
       f.sha256, f.size_bytes
FROM subset_requests s
JOIN assets a USING(asset_id)
LEFT JOIN artifacts f ON f.artifact_id = s.latest_artifact_id
ORDER BY a.asset_key, s.aoi_key;
