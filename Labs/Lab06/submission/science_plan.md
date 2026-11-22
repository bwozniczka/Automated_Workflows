# My scientific product

Name: Bartłomiej Woźniczka

Scientific question: Where within a small park/forest AOI west of Kraków is the canopy relatively moist versus drier on clear June dates, and how sensitive is that moist-candidate map to the NDMI threshold?

Product name, method/equation and authoritative source: **NDMI** (Normalized Difference Moisture Index). NDMI = (NIR − SWIR1) / (NIR + SWIR1). Source: Gao, B.-C. (1996). NDWI — A normalized difference water index for remote sensing of vegetation liquid water from space. *Remote Sensing of Environment*, 58(3), 257–266. https://doi.org/10.1016/S0034-4257(96)00067-3 (Sentinel practice labels this NIR–SWIR form NDMI).

Required bands and why they measure the relevant property: **nir** (B08) and **swir16** (B11). Liquid water in leaves absorbs more strongly in SWIR than in NIR, so higher NDMI indicates greater canopy moisture / leaf water content relative to drier or non-vegetated surfaces.

AOI name(s), exact bbox(es), and reason for selecting them: **wolski** - WGS84 bbox `[19.85, 50.05, 19.88, 50.07]` (Las Wolski / Bielany park–forest edge west of Kraków). Chosen for mixed canopy useful to moisture screening, distinct from the lab demo river/east boxes, still inside Sentinel-2 tile T34UDA.

Acquisition IDs and dates; why these dates are appropriate: `S2C_T34UDA_20250605T095638_L2A` (2025-06-05, tile cloud ~5.8%) and `S2C_T34UDA_20250615T095047_L2A` (2025-06-15, tile cloud ~0%). Same season, leaf-on June; ten days apart for a second clear look without a large phenology jump. Search retained in `work/search_results.json`; bundle in `work/personal/inputs/manifest.json`.

Preparation choices: calibration source, target grid, SCL exclusions, domain restrictions: Collection 1 STAC scale/offset applied only in processing; **20 m** target grid (matches native SWIR); default SCL policy excluding 0,1,2,3,7,8,9,10,11 (keep vegetation/nonveg/water); no land-only restriction so moisture over mixed pixels remains visible for QC discussion.

Output layers, metric(s), and their units: `index` (NDMI, unitless −1…1), `moist` (1 = NDMI > moist_threshold, 0 = observed below, NaN = unknown), plus runner `valid_mask`. Metrics: `mean_ndmi`, `moist_area_m2` (m² on 20 m grid), `observed_area_m2`, `moist_threshold`.

One scientifically meaningful parameter to vary: **moist_threshold** (default 0.1; comparison run at 0.2).

What observation or reference could reveal a wrong implementation? Independent NDMI arithmetic on several real clear pixels from calibrated nir/swir16; known water bodies should not dominate a canopy-moisture map; cloud/SCL-masked pixels must stay NaN. Sign error (SWIR−NIR) would invert moist vs dry patterns.

Main limitation or confounding factor: Mixed pixels at forest edges, residual thin cloud/shadow, soil brightness under sparse canopy, and threshold subjectivity—moist area is a candidate classification, not a laboratory moisture measurement.
