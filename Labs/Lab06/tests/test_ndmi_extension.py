"""Independent checks for the personal NDMI extension (not the shared MNDWI suite)."""
from pathlib import Path
import numpy as np
from eo_processing.products import load_product, normalized_difference

EXTENSION = Path(__file__).resolve().parents[1] / "extensions" / "ndmi.py"


def test_ndmi_matches_independent_normalized_difference():
    product, meta = load_product("ndmi", EXTENSION)
    assert meta["required_bands"] == ["nir", "swir16"]
    rng = np.random.default_rng(0)
    nir = rng.uniform(0.05, 0.45, size=(8, 8)).astype("float32")
    swir = rng.uniform(0.02, 0.35, size=(8, 8)).astype("float32")
    valid = np.ones((8, 8), dtype=bool)
    valid[0, 0] = False
    expected = normalized_difference(nir, swir, 1e-6)
    expected[~valid] = np.nan
    result = product.calculate({"nir": nir, "swir16": swir}, valid, {"epsilon": 1e-6, "moist_threshold": 0.1}, 400.0)
    assert np.allclose(result.layers["index"], expected, equal_nan=True)
    observed = np.isfinite(expected)
    assert result.layers["moist"][~observed].tolist() == [] or np.all(np.isnan(result.layers["moist"][~observed]))
    assert np.all(np.isnan(result.layers["index"][~valid]))
