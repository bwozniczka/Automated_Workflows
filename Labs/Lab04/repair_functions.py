"""Three plausible implementations to investigate and repair. No syntax puzzles."""
import math

import numpy as np

import processing_store as store


def _normalize(value):
    """Make JSON-compatible and treat 1 and 1.0 as the same number."""
    if isinstance(value, dict):
        return {key: _normalize(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_normalize(item) for item in value]
    if isinstance(value, bool) or value is None:
        return value
    if isinstance(value, (int, float)):
        return float(value)
    return value


def make_request_spec(science, inputs, environment, runtime):
    """Return (normalized_spec, fingerprint). Read the contract before editing."""
    del runtime 
    settings = {key: value for key, value in science.items() if key != 'inputs'}
    ordered_inputs = []
    for role in ('red', 'nir'):
        record = inputs[role]
        ordered_inputs.append({
            'role': role,
            'artifact_id': record['artifact_id'],
            'sha256': record['sha256'],
            'size_bytes': record['size_bytes'],
            'raster': record['raster'],
            'lineage': record['lineage'],
        })
    spec = _normalize({
        'stage': science['stage'],
        'settings': settings,
        'inputs': ordered_inputs,
        'environment': environment,
        'equivalence_policy': environment.get('policy', 'exact_environment_v1'),
    })
    fingerprint = store.digest(spec)
    return spec, fingerprint


def _finite_number(value, label, *, positive=False):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError(f'{label} must be a finite number')
    if positive and value <= 0:
        raise ValueError(f'{label} must be positive')


def validate_pair(red, nir):
    """Raise ValueError if metadata cannot justify a red/NIR calculation."""
    if red['lineage'].get('asset_key') != 'red':
        raise ValueError('First input must be the red band')
    if nir['lineage'].get('asset_key') != 'nir':
        raise ValueError('Second input must be the NIR band')

    for key in ('collection', 'item_id', 'aoi_key', 'recipe_version'):
        if red['lineage'].get(key) != nir['lineage'].get(key):
            raise ValueError(f'Inputs disagree on {key}')

    for label, meta in (('red', red['raster']), ('nir', nir['raster'])):
        _finite_number(meta.get('scale'), f'{label} scale', positive=True)
        _finite_number(meta.get('offset'), f'{label} offset')

    red_raster, nir_raster = red['raster'], nir['raster']
    if red_raster.get('shape') != nir_raster.get('shape'):
        raise ValueError('Input shapes differ')
    if red_raster.get('crs') != nir_raster.get('crs'):
        raise ValueError('Input CRS differ')
    if red_raster.get('transform') != nir_raster.get('transform'):
        raise ValueError('Input transforms differ; require a matching grid')


def calculate_ndvi(red, nir, red_meta, nir_meta, epsilon):
    """Return float32 NDVI; invalid pixels must be NaN. Inputs are stored DN."""
    red_dn = np.asarray(red)
    nir_dn = np.asarray(nir)
    reflectance_red = red_dn.astype('float64') * red_meta['scale'] + red_meta['offset']
    reflectance_nir = nir_dn.astype('float64') * nir_meta['scale'] + nir_meta['offset']
    valid = (
        (red_dn != red_meta['nodata'])
        & (nir_dn != nir_meta['nodata'])
        & (np.abs(reflectance_nir + reflectance_red) > epsilon)
    )
    result = np.full(red_dn.shape, np.nan, dtype=np.float32)
    with np.errstate(divide='ignore', invalid='ignore'):
        result[valid] = (
            (reflectance_nir[valid] - reflectance_red[valid])
            / (reflectance_nir[valid] + reflectance_red[valid])
        ).astype(np.float32)
    return result
