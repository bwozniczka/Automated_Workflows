-- Write and retain your diagnostic queries here. Use the notebook questions.
-- Enable enforcement when opening your own SQLite session:
PRAGMA foreign_keys = ON;

-- Q1. List requests with their number of attempts, grouped by outcome.
SELECT
  r.request_id,
  r.stage,
  r.fingerprint,
  a.status,
  COUNT(*) AS attempt_count
FROM processing_requests AS r
JOIN processing_attempts AS a USING (request_id)
GROUP BY r.request_id, r.stage, r.fingerprint, a.status
ORDER BY r.request_id, a.status;

-- Q2. Starting from an NDVI artifact ID, find its successful producing attempt,
-- normalized request, each input role, original Lab 3 subset, scene, band and AOI.
-- Replace :ndvi_artifact_id with a concrete output artifact_id when running interactively.
SELECT
  out_link.artifact_id AS ndvi_artifact_id,
  out_link.role AS output_role,
  producer.attempt_id AS producing_attempt_id,
  producer.status AS producing_status,
  producer.finished_at,
  req.request_id,
  req.fingerprint,
  req.normalized_json,
  inp.role AS input_role,
  pa.artifact_id AS processing_input_id,
  pa.source_artifact_id AS lab3_artifact_id,
  pa.sha256 AS input_sha256,
  art.subset_id,
  a.collection,
  a.item_id,
  a.asset_key,
  a.source_url,
  s.aoi_key,
  s.aoi_json,
  s.recipe_version
FROM processing_outputs AS out_link
JOIN processing_attempts AS producer
  ON producer.attempt_id = out_link.attempt_id
 AND producer.status = 'succeeded'
JOIN processing_requests AS req
  ON req.request_id = producer.request_id
JOIN processing_inputs AS inp
  ON inp.request_id = req.request_id
JOIN processing_artifacts AS pa
  ON pa.artifact_id = inp.artifact_id
LEFT JOIN artifacts AS art
  ON art.artifact_id = pa.source_artifact_id
LEFT JOIN subset_requests AS s
  ON s.subset_id = art.subset_id
LEFT JOIN assets AS a
  ON a.asset_id = s.asset_id
WHERE out_link.role = 'ndvi'
  -- AND out_link.artifact_id = :ndvi_artifact_id
ORDER BY out_link.artifact_id, inp.role;

-- Same lineage when the notebook only returns an output from a reused attempt:
-- follow reused_from_attempt_id (or any succeeded attempt that published the artifact).
SELECT
  link.artifact_id AS ndvi_artifact_id,
  link.attempt_id AS returning_attempt_id,
  returned.status AS returning_status,
  returned.reused_from_attempt_id,
  producer.attempt_id AS producing_attempt_id,
  producer.status AS producing_status
FROM processing_outputs AS link
JOIN processing_attempts AS returned
  ON returned.attempt_id = link.attempt_id
JOIN processing_outputs AS produced
  ON produced.artifact_id = link.artifact_id
 AND produced.role = 'ndvi'
JOIN processing_attempts AS producer
  ON producer.attempt_id = produced.attempt_id
 AND producer.status = 'succeeded'
WHERE link.role = 'ndvi'
ORDER BY link.artifact_id, returned.started_at;

-- Q3. Find failed/interrupted attempts with stage and error; retain recovery rows.
SELECT
  attempt_id,
  request_id,
  status,
  stage,
  started_at,
  finished_at,
  error_code,
  error_message,
  reused_from_attempt_id
FROM processing_attempts
WHERE status IN ('failed', 'interrupted')
   OR error_code IS NOT NULL
ORDER BY started_at;

-- Recovery context for the same request: keep every attempt, including later success/reuse.
SELECT
  request_id,
  attempt_id,
  status,
  stage,
  started_at,
  finished_at,
  error_code,
  error_message,
  reused_from_attempt_id
FROM processing_attempts
WHERE request_id IN (
  SELECT request_id
  FROM processing_attempts
  WHERE status IN ('failed', 'interrupted')
)
ORDER BY request_id, started_at;

-- Q4. Find succeeded attempts whose returned artifact has no available location.
-- SQL only knows the last recorded location status; it cannot see whether the file
-- still exists on disk or whether size/sha256 still match. Python re-checks those.
SELECT
  a.attempt_id,
  a.request_id,
  a.status,
  a.finished_at,
  o.role AS output_role,
  o.artifact_id,
  loc.location_id,
  loc.local_path,
  loc.status AS location_status,
  loc.checked_at
FROM processing_attempts AS a
JOIN processing_outputs AS o
  ON o.attempt_id = a.attempt_id
LEFT JOIN processing_artifact_locations AS loc
  ON loc.artifact_id = o.artifact_id
WHERE a.status = 'succeeded'
  AND (
    loc.location_id IS NULL
    OR loc.status <> 'available'
    OR NOT EXISTS (
      SELECT 1
      FROM processing_artifact_locations AS ok
      WHERE ok.artifact_id = o.artifact_id
        AND ok.status = 'available'
    )
  )
ORDER BY a.finished_at;

-- Q5. Find running attempts and inspect temp/final path, receipt and output links.
SELECT
  a.attempt_id,
  a.request_id,
  a.status,
  a.stage,
  a.started_at,
  a.finished_at,
  a.temp_path,
  a.final_path,
  a.log_path,
  a.receipt_json,
  a.error_code,
  o.role AS output_role,
  o.artifact_id AS output_artifact_id
FROM processing_attempts AS a
LEFT JOIN processing_outputs AS o
  ON o.attempt_id = a.attempt_id
WHERE a.status = 'running'
ORDER BY a.started_at;

-- Q6. Compare original calibration metadata with the reviewed configuration.
SELECT
  inp.role,
  pa.artifact_id,
  json_extract(pa.raster_json, '$.scale') AS asset_scale,
  json_extract(pa.raster_json, '$.offset') AS asset_offset,
  json_extract(req.normalized_json, '$.settings.scaling') AS scaling_policy,
  json_extract(req.normalized_json, '$.settings.calibration.' || inp.role || '.scale') AS reviewed_scale,
  json_extract(req.normalized_json, '$.settings.calibration.' || inp.role || '.offset') AS reviewed_offset,
  json_extract(req.normalized_json, '$.settings.calibration.' || inp.role || '.evidence') AS review_evidence,
  json_extract(req.normalized_json, '$.settings.calibration.' || inp.role || '.sha256') AS reviewed_input_sha256,
  pa.sha256 AS registered_input_sha256
FROM processing_requests AS req
JOIN processing_inputs AS inp USING (request_id)
JOIN processing_artifacts AS pa
  ON pa.artifact_id = inp.artifact_id
ORDER BY req.request_id, inp.role;
