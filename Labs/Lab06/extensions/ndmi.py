"""NDMI (Normalized Difference Moisture Index) for canopy moisture screening.

Equation (Gao 1996 NDWI for vegetation liquid water; Sentinel practice names it NDMI):
  NDMI = (NIR - SWIR1) / (NIR + SWIR1)
Sentinel-2: NIR = B08 (nir), SWIR1 = B11 (swir16).

Source: Gao, B.-C. (1996). NDWI - A normalized difference water index for remote
sensing of vegetation liquid water from space. Remote Sensing of Environment,
58(3), 257–266. https://doi.org/10.1016/S0034-4257(96)00067-3
"""
import numpy as np
from eo_processing.products import ProductResult, normalized_difference


class NDMI:
    name = "ndmi"
    version = "1.0.0"
    required_bands = ("nir", "swir16")
    output_roles = ("index", "moist")
    primary_role = "index"
    nominal_range = (-1.0, 1.0)
    default_parameters = {"epsilon": 0.000001, "moist_threshold": 0.1}

    def calculate(self, bands, valid, parameters, pixel_area_m2):
        index = normalized_difference(bands["nir"], bands["swir16"], parameters["epsilon"])
        index = np.where(valid, index, np.nan).astype("float32")
        observed = np.isfinite(index)
        moist = np.full(index.shape, np.nan, dtype="float32")
        moist[observed] = (index[observed] > parameters["moist_threshold"]).astype("float32")
        moist_pixels = int(np.count_nonzero(moist == 1))
        return ProductResult(
            {"index": index, "moist": moist},
            {
                "mean_ndmi": float(index[observed].mean()) if observed.any() else None,
                "moist_pixels": moist_pixels,
                "moist_area_m2": float(moist_pixels * pixel_area_m2),
                "observed_area_m2": float(observed.sum() * pixel_area_m2),
                "moist_threshold": float(parameters["moist_threshold"]),
            },
        )


PRODUCT = NDMI()
