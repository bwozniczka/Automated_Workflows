-- Keep the question, parameters, expected columns, empty-result interpretation and next check.

-- 1. Which expected members have never reached an application attempt?
-- Question: list batch members with no row in processing_attempts yet.
-- Parameters: none (scope = current catalogue / batch_members present).
-- Expected columns: batch_id, member_id, planned_request_id, request_id.
-- Empty result: every expected member already has at least one application attempt.
-- Next check: if non-empty, inspect batch_observations for blocked/ready and missing inputs;
--             if empty after a fault case, confirm recovery created a producing attempt.
SELECT m.batch_id,
       m.member_id,
       m.planned_request_id,
       m.request_id
FROM batch_members m
WHERE NOT EXISTS (
  SELECT 1
  FROM processing_attempts a
  WHERE a.request_id = COALESCE(m.request_id, m.planned_request_id)
)
ORDER BY m.member_id;

-- 2. Which request failed or stopped and later produced a verified result?
-- Question: find requests with an earlier failed/interrupted attempt and a later succeeded
--           producing attempt that published an output artifact.
-- Parameters: none.
-- Expected columns: member_id, request_id, earlier_attempt_id, earlier_status,
--                   earlier_error_code, producing_attempt_id, producing_status,
--                   verified_artifact_id.
-- Empty result: no recovered failures/interruptions in this catalogue (e.g. clean happy path).
-- Next check: compare attempt counts vs delivered outputs; do not treat attempt count as
--             delivered work. Inspect cases/worker after reconcile+run for a non-empty answer.
SELECT m.member_id,
       m.request_id,
       bad.attempt_id AS earlier_attempt_id,
       bad.status AS earlier_status,
       bad.error_code AS earlier_error_code,
       bad.started_at AS earlier_started_at,
       good.attempt_id AS producing_attempt_id,
       good.status AS producing_status,
       good.started_at AS producing_started_at,
       po.artifact_id AS verified_artifact_id
FROM batch_members m
JOIN processing_attempts bad
  ON bad.request_id = m.request_id
 AND bad.status IN ('failed', 'interrupted')
JOIN processing_attempts good
  ON good.request_id = m.request_id
 AND good.status = 'succeeded'
 AND good.started_at > bad.started_at
JOIN processing_outputs po
  ON po.attempt_id = good.attempt_id
ORDER BY m.member_id, bad.started_at, good.started_at;

-- 3. Which succeeded products have no location recorded as available?
-- Question: succeeded attempts with a published output whose catalogue locations are all
--           missing/corrupt, or that have no location row at all.
-- Parameters: none.
-- Expected columns: member_id, succeeded_attempt_id, artifact_id, location_statuses.
-- Empty result: every succeeded product currently has at least one location marked available.
-- Next check: run refresh / inspect files; a missing location row does not rewrite the
--             historical succeeded attempt. Catalogue status is last checked evidence, not a
--             live filesystem proof — opening the path (or refresh) is required to know
--             present disk state. ANY missing location among several copies is not enough to
--             conclude the product is unavailable if another copy remains available.
SELECT m.member_id,
       a.attempt_id AS succeeded_attempt_id,
       po.artifact_id,
       GROUP_CONCAT(DISTINCT l.status) AS location_statuses
FROM batch_members m
JOIN processing_attempts a
  ON a.request_id = m.request_id
 AND a.status = 'succeeded'
JOIN processing_outputs po
  ON po.attempt_id = a.attempt_id
LEFT JOIN processing_artifact_locations l
  ON l.artifact_id = po.artifact_id
GROUP BY m.member_id, a.attempt_id, po.artifact_id
HAVING SUM(CASE WHEN l.status = 'available' THEN 1 ELSE 0 END) = 0
ORDER BY m.member_id;

-- 4. Which members rely on old observations?
-- Question: members whose newest batch observation is older than the investigator cutoff.
-- Parameters: :batch_id (text batch primary key), :before (UTC text timestamp, exclusive upper
--             bound on observed_at of the latest observation).
-- Expected columns: member_id, observation_id, observed_at, state, reason.
-- Empty result: every member in the batch has a latest observation at or after :before
--               (or the batch has no members).
-- Next check: if rows appear, re-plan/refresh/run or open a new report after new observations;
--             do not confuse observed_at (when evidence was appended) with report generation time.
-- Timestamps: observed_at comes from batch_observations at append time (UTC text).
--             :before is the analyst cutoff. Report export time is separate and is not stored
--             as an observation.
SELECT m.member_id,
       o.observation_id,
       o.observed_at,
       o.state,
       o.reason
FROM batch_members m
JOIN batch_observations o
  ON o.batch_id = m.batch_id
 AND o.member_id = m.member_id
WHERE m.batch_id = :batch_id
  AND o.observation_id = (
    SELECT MAX(x.observation_id)
    FROM batch_observations x
    WHERE x.batch_id = m.batch_id
      AND x.member_id = m.member_id
  )
  AND o.observed_at < :before
ORDER BY m.member_id;
