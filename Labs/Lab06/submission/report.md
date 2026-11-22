# Lab 06 investigation

Name and package version: Bartłomiej Woźniczka · eo_processing / agh-eo-processing **1.0.0**

## Common exercise

Expected requests, first-run attempts, second-run attempts: Expected **6** requests (demo `members: 6`). First `run`: **6** processing attempts started and succeeded. Second `run` on the same `work/demo/batch.json`: **0** new attempts (`launched_attempts: []`); all six members reused verified outputs (`attempts_used: 1` each). Catalogue still holds exactly 6 `processing_attempts` rows.

Why six requests are not six acquisition dates: The demo pairs **3 Sentinel-2 acquisition dates** (2025-06-04 / S2A, 2025-06-05 / S2C, 2025-06-10 / S2B) with **2 AOIs** (river and east near Kraków). Each request is one (scene × AOI × MNDWI product), so 3 × 2 = 6 requests, not six different acquisition days.

How a third input band enters the processing interface: Trace: `planning.py` freezes scene/AOI/product/`parameters`/mask/`grid` and looks up inputs for `(*required_bands, "scl")`; `preparation.py` calibrates reflectance, screens native pixels with SCL, aligns to a common grid and returns a `bands` dict; `products.py` defines science (`MNDWI`: green+swir16 → index/water via (G−SWIR)/(G+SWIR), params `epsilon`/`threshold`); `runner.py` calls `product.calculate` at L135, verifies layers, writes GeoTIFFs/`valid_mask`, records attempts; `database.py` stores requests/inputs/outputs/artifacts; `qc.py` only appends assessments from measured metrics (no reprocessing). To add a 3-band optical product: change the product declaration’s `required_bands` to three roles (and keep `output_roles`/`calculate` consistent)—do not touch the shared core. Acquire those three assets plus SCL in the input bundle/config. Runner/planner/preparation already loop over whatever `required_bands` declares, so they need no edits.

Cloudy/clear river comparison: raw coverage, usable coverage, candidate water area: River AOI, threshold 0.0, SCL screening. **4 June (cloudy S2A):** raw_valid_fraction=1.0, usable/clear≈**0.476**, candidate water **130 000 m²** (325 px) - QC rejected under min 0.5. **5 June (clear S2C):** raw=1.0, usable≈**0.994**, candidate water **231 200 m²** (578 px) - accepted at 0.5. The ~101 200 m² gap is not evidence of a real extent change: cloudy date masks most of the AOI as unknown (SCL cloud/shadow dense), so water is counted only on the remaining clear subset; fair comparison needs common valid coverage (and similar illumination/season), not raw candidate totals.

What disabling cloud screening changed, and what this means scientifically: Same 4 June river scene with `mask_policy=nodata_only` became a **new request** and attempt. usable/valid_fraction jumped to **1.0** and candidate water to **233 600 m²** (near the clear-date total), but assess outcome=`review` because cloud screening was off. Finite coverage ≠ scientific usefulness: clouds still enter the reflectance/MNDWI calculation; `nodata_only` only drops missing/defective SCL 0-1, not cloud classes.

Effect of changing the MNDWI threshold; request identity evidence: Clear river 5 June: threshold **0.0** → **231 200 m²** (`request-2bb2003c…`); threshold **0.15** → **181 600 m²** and a **new** request (`request-749866393b…`) because parameters are part of the frozen scientific identity. Both are candidate classifications; choose/validate a threshold with reference water, visual checks on clear dates, or sensitivity tests—not by maximizing area. Do not edit frozen `batch.json`; re-plan from config.

QC policy change: assessment IDs before/after, and processing-attempt count: Stricter `assess --minimum-valid-fraction 0.995` on the demo batch appended assessments **8–13** (all rejected; even ~0.994 clear dates fail 0.995) and started **0** processing attempts (still 8 attempts total after nodata+threshold experiments). Old `succeeded` attempts stay succeeded: QC is a separate appended judgment on measured metrics. Changing the QC minimum reuses existing receipts; changing cloud-mask policy needs a different scientific request/reprocess (as with nodata_only).

One useful SQL query and what its actual output tells me: Using `queries.sql` “succeeded but latest QC rejected” plus assessments for one attempt: clear river June 5 attempt has assessment **3** accepted at min=0.5 and **10** rejected at min=0.995 on the same metrics—policy history without re-running processing. MNDWI attempts also expose three named outputs (`index`, `water`, `valid_mask`).

## My scientific product

Question and link to the science plan: Canopy moisture candidates over Las Wolski via NDMI — see `submission/science_plan.md`.

Exact commands for acquisition/registration, planning, processing, assessment and report:
```bash
python -m eo_processing search --bbox 19.85 50.05 19.88 50.07 --interval 2025-06-01T00:00:00Z/2025-06-15T23:59:59Z --max-items 20 --out work/search_results.json
python -m eo_processing acquire --config config/personal_acquisition.json --destination work/personal/inputs
python -m eo_processing init --database work/personal/catalogue.sqlite
python -m eo_processing register --database work/personal/catalogue.sqlite --bundle work/personal/inputs
python -m eo_processing plan --config config/personal_batch.json --out work/personal/batch.json
python -m eo_processing run --manifest work/personal/batch.json
python -m eo_processing assess --manifest work/personal/batch.json --minimum-valid-fraction 0.5
python -m eo_processing report --manifest work/personal/batch.json --out work/personal/report
```
Changed-parameter plan: `plan --config config/personal_batch_threshold02.json --out work/personal/batch_threshold02.json` then `run` / `report`.

Input bundle: manifest path, source item IDs, band list, checksums and where the retained subset files can be accessed: `work/personal/inputs/manifest.json` (complete; collection `sentinel-2-c1-l2a`). Items `S2C_T34UDA_20250605T095638_L2A`, `S2C_T34UDA_20250615T095047_L2A`; bands `nir`, `swir16`, `scl`. Checksums: 05-nir `c5ed5cae…c65bca`, 05-swir16 `ce344078…cca23b`, 05-scl `c351e634…14982ee`; 15-nir `f1d67461…ce2a6a86`, 15-swir16 `b83a4faf…bd1d7ae4`, 15-scl `4f95ad7f…9db992eb`. Subsets retained under `work/personal/inputs/` (local course machine).

Extension path/version, configuration paths and frozen manifests: `extensions/ndmi.py` v**1.0.0**; configs `config/personal_acquisition.json`, `config/personal_batch.json`, `config/personal_batch_threshold02.json`; frozen `work/personal/batch.json`, `work/personal/batch_threshold02.json`; reports `work/personal/report/`, `work/personal/report_threshold02/`.

Repeat/reuse evidence and changed-request evidence: First personal `run` launched **2** attempts; second `run` on the same manifest launched **0** (`launched_attempts: []`). Raising `moist_threshold` 0.1→0.2 created a **new** request (`request-66c5df58…` vs `request-21d5b59a…`) and a new attempt; moist area on 15 June fell **4 390 800 → 3 822 800 m²** while `mean_ndmi` stayed 0.317 (index unchanged; only classification cut).

Independent check, expected result, measured result and interpretation: (1) Hand/NumPy NDMI on sample reflectances matched `normalized_difference` and `PRODUCT.calculate` exactly (e.g. nir=0.30,swir=0.10 → 0.5). (2) Rebuilding `moist` from written `index.tif` with threshold 0.1 agreed pixel-wise with `moist.tif` (True). Disagreement would mean a threshold/NaN bug, not a plausible map.

Scientific finding, usable coverage and a suspected false detection or limitation: Both dates accepted (valid_fraction ≈1.0 / 0.9999). Mean NDMI ≈0.30 (5 Jun) and ≈0.32 (15 Jun); most of the park AOI exceeds moist_threshold=0.1, so the moist layer is a broad canopy-moisture candidate, not a sparse wet-spot map. Limitation / likely false detection: mixed edge pixels and bright soil under sparse canopy can push NDMI across a low threshold; absolute moist area is threshold-sensitive (shown by 0.2 cut) and is not lab-measured leaf water.

Core verification result: `python -m eo_processing check-core` → version 1.0.0, `identical_to_class_release: true`, `changed_files: []`.

Assistance used and how I verified it: Cursor agent helped wire the Lab 06 workflow, NDMI extension and report text. I verified by running acquire/run/assess myself in terminal, checking Gao (1996) band roles, confirming equation on sample pixels, moist↔index consistency on real outputs, and `check-core`. Rejected treating demo river AOI as “own AOI” and rejected disabling SCL for the scientific product (kept diagnostic nodata_only only in the common exercise).

## Optional debugging clinic

Why the file existed even though the real attempt failed:

My file mode correction, and why it preserves existing bytes:

Verification result, and why the main core still matches the release:

Why the original runner correction needed new manifests while this exercise does not:
