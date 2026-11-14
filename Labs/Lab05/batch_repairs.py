"""These functions run, but their decisions need repair. Read SCHEMA_CONTRACT.md."""

def classify_member(context):
    if context['active_attempt']:
        return {'state': 'unresolved', 'reason': 'Execution is still recorded as active'}
    if context['verified_result']:
        return {'state': 'complete', 'reason': 'Output verified'}
    if context.get('validation_error'):
        return {'state': 'failed', 'reason': context['validation_error']}
    last = context.get('last_attempt')
    if last and last.get('status') == 'failed':
        return {'state': 'failed', 'reason': last.get('error_code') or 'Application attempt failed'}
    if context['missing_inputs']:
        return {'state': 'blocked', 'reason': 'Required input bytes are unavailable'}
    if context['attempts_used'] >= context['max_attempts']:
        return {'state': 'failed', 'reason': 'Attempt budget exhausted'}
    return {'state': 'ready', 'reason': 'Inputs verified and attempt budget permits execution'}

def verify_result(member, evidence):
    if evidence.get('request_id') != member.get('request_id'):
        return False
    if not evidence.get('attempt_id') or not evidence.get('artifact_id'):
        return False
    size = evidence.get('size_bytes')
    actual_size = evidence.get('actual_size_bytes')
    if not isinstance(size, int) or size <= 0:
        return False
    if actual_size != size:
        return False
    sha = evidence.get('sha256')
    actual_sha = evidence.get('actual_sha256')
    if not sha or not actual_sha or sha != actual_sha:
        return False
    for flag in ('catalogue_link_verified', 'grid_verified', 'provenance_verified'):
        if evidence.get(flag) is not True:
            return False
    return True

def summarize_batch(rows):
    latest = {}
    for row in rows:
        member_id = row['member_id']
        observation_id = row['observation_id']
        previous = latest.get(member_id)
        if previous is None or observation_id > previous['observation_id']:
            latest[member_id] = row
    counts = {s: 0 for s in ('ready', 'complete', 'blocked', 'unresolved', 'failed', 'unobserved')}
    members = {s: [] for s in counts}
    for member_id, row in latest.items():
        state = row['state']
        if state is None or row['observation_id'] == -1:
            bucket = 'unobserved'
        else:
            bucket = state
        counts[bucket] += 1
        members[bucket].append(member_id)
    for bucket in members:
        members[bucket].sort()
    return {'expected': len(latest), 'counts': counts, 'members': members}
