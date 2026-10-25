# Built-in food catalogue audit

Audit date: 2026-10-18. Scope: the 16 starter rows inserted by
`LocalDatabase._seedFoods()` in `lib/data/local_database.dart`. This is the
manual-search catalogue; Gemini proposals are not sourced from these entries.

## How to read the stored quantities

The `foods` table stores `serving`, `unit`, and kcal/macros **for that serving**.
For `g` and `ml` foods only, `Food.perHundredNutrition` converts that serving to
per 100 g/ml. Thus the 100 g sprouted moong and cucumber rows are stored per
100 g; almonds are stored per 28 g and normalized by multiplying by 100/28.
Entries whose units say `cup`, `piece`, `medium`, or `large` remain per listed
serving; the parenthetical cup weight is descriptive, not an automatic gram
conversion. Values below are the literal values currently seeded, before any
normalization.

“Reference candidate” means an authoritative database has a potentially
matching food/state, but I did not verify its nutrient record against all four
stored numbers. It is not a claim of exact validation. No commercial product
label or recipe specification was available for these generic foods.

| Seed name | Stored basis | kcal | Protein g | Carbs g | Fat g | State, reference and audit status |
|---|---:|---:|---:|---:|---:|---|
| Sprouted moong | 100 g | 30 | 3.0 | 6.0 | 0.2 | State unclear (raw sprout vs cooked/germinated Indian moong). USDA FoodData Central lists “Mung beans, mature seeds, sprouted, raw” (NDB 11043), a possible raw-state match, but exact nutrients were not independently confirmed. **Unverified estimate; clarify state and compare IFCT/USDA row.** |
| Cucumber | 100 g | 15 | 0.7 | 3.6 | 0.1 | State/peel unspecified. USDA FDC lists “Cucumber, with peel, raw” (NDB 11205); the seeded rounded values are consistent with a generic raw cucumber entry, but no exact source row is asserted. **Approximate match; label as raw/with peel only if confirmed.** |
| Cooked basmati rice | 1 cup (158 g) | 205 | 4.3 | 45 | 0.4 | Cooked, but cultivar not established. The cup mass and values resemble generic cooked long-grain white rice; that is not enough to verify basmati. **Ambiguous proxy; no conversion applied.** |
| Roti / chapati | 1 medium | 120 | 3.5 | 20 | 3 | Prepared flatbread; flour type, diameter, cooked mass and added fat unspecified. Roti and chapati are synonyms here, not two separate rows. **Recipe-dependent estimate; serving mass needed.** |
| Dal tadka | 1 cup | 210 | 12 | 30 | 5 | Prepared lentil dish; lentil type, dilution, tadka oil/ghee, and cup mass unspecified. **Recipe-dependent estimate; no authoritative exact match.** |
| Idli | 1 piece | 58 | 2 | 12 | 0.4 | Prepared fermented rice/urad cake; piece mass and recipe unspecified. **Plausible rough estimate, serving mass and recipe needed.** |
| Plain dosa | 1 medium | 168 | 4 | 28 | 4 | Prepared; diameter, batter ratio and pan oil unspecified. **Recipe-dependent estimate; “medium” has no gram basis.** |
| Paneer | 100 g | 265 | 18 | 2 | 20 | Fresh cheese; moisture, milk fat and preparation vary. No product or IFCT/FDC row was tied to these exact values. **Unverified generic estimate; high variation.** |
| Plain curd | 1 cup (245 g) | 149 | 8.5 | 11.4 | 8 | Fermented dairy; fat level unspecified. Values resemble whole-milk plain yogurt but “curd” is not a uniquely equivalent product. **Candidate proxy only; clarify fat level and local product.** |
| Poha | 1 cup | 250 | 5 | 42 | 7 | Prepared flattened-rice dish; dry vs cooked is unstated, as are vegetables/oil and cup mass. **Ambiguous serving/state; likely prepared dish but unverified.** |
| Upma | 1 cup | 220 | 6 | 35 | 7 | Prepared semolina dish; oil, additions and cup mass vary. **Recipe-dependent estimate; no exact standard basis.** |
| Chole | 1 cup | 280 | 12 | 42 | 7 | Prepared chickpea curry; gravy, oil and cup mass vary. **Recipe-dependent estimate; no exact standard basis.** |
| Boiled egg | 1 large | 78 | 6.3 | 0.6 | 5.3 | Hard-boiled whole egg; “large” is a conventional piece size, not grams in app data. USDA FDC has hard-boiled egg records, but the exact source record and nutrient values were not independently compared. **Likely standard estimate; verify exact size/reference.** |
| Chicken breast, cooked | 100 g | 165 | 31 | 0 | 3.6 | Cooked, meat-only is implied but skin, cooking method and added oil are unspecified. USDA FDC SR Legacy has cooked roasted breast meat-only (NDB 5064), a candidate match; exact nutrient row not independently confirmed. **Likely standard cooked reference; confirm method/skin.** |
| Banana | 1 medium | 105 | 1.3 | 27 | 0.4 | Raw, medium edible portion implied; weight not stored. USDA FDC has raw banana entries, but no exact record was matched here. **Likely standard estimate; edible gram basis unverified.** |
| Almonds | 28 g | 164 | 6 | 6 | 14 | Raw/roasted and salted state not specified. USDA FDC has raw whole almond records; exact row was not verified. **Common rounded estimate; state should be specified.** |

## Findings and actions

- **No duplicate seed rows by exact name.** “Roti / chapati” combines two common names. Several foods remain semantically ambiguous (moong sprout state, rice variety, curd fat level, preparation dishes, and chicken cooking/skin state).
- **Unit bases are explicit enough for current conversion behavior, but not always precise enough for nutrition accuracy.** Gram-based seeded foods are `g`; cup/piece descriptions are single recipe or serving totals. The parenthetical `158 g` and `245 g` do not drive calculations. Converting a cup-based entry to a gram quantity would need a deliberate basis change and should not be inferred from the display string.
- **No seeded entry shows an obvious 1,000× unit error.** Macro-derived energy is broadly in the expected range for these rounded estimates. Exact energy differences may result from fiber-specific Atwater factors and rounding, so that check is only a sanity test, not source verification.
- **No seed values were changed in this pass.** For recipe foods and ambiguous states, changing a generic value without a matching reference would imply false precision. No schema or catalogue migration was made.
- `trustedGramFoods` contains separate local reference estimates for sprouted moong and cucumber. Those values are used for manual catalogue lookups and related local normalization only; they are not a source for Gemini-generated nutrition.

## Sources and remaining verification

- [ICMR–National Institute of Nutrition, Indian Food Composition Tables 2017 (official PDF)](https://www.nin.res.in/ebooks/IFCT2017.pdf) and [NIN downloads](https://www.nin.res.in/downloads/). IFCT is the preferred Indian reference for matching Indian ingredients, but this pass did not establish exact table rows and preparation equivalence for all seeds. “Dal tadka”, “poha”, “upma”, “chole”, idli, dosa and paneer need ingredient/state and serving-mass matches before their seed values can be called verified.
- [USDA FoodData Central search: cucumber, with peel, raw (NDB 11205)](https://fdc.nal.usda.gov/food-search/?query=cucumber&type=SR%20Legacy).
- [USDA FoodData Central search: mung beans, mature seeds, sprouted, raw (NDB 11043)](https://fdc.nal.usda.gov/food-search/?query=sprouts&type=SR%20Legacy).
- [USDA FoodData Central search: cooked chicken breast records, including meat-only roasted (NDB 5064)](https://fdc.nal.usda.gov/food-search/?query=chicken%20breast&type=SR%20Legacy).
- [USDA FoodData Central search](https://fdc.nal.usda.gov/food-search/) is also the next lookup for rice, yogurt, egg, banana and almonds. FDC search results identify candidate records; they do not by themselves establish equivalence to these local serving labels.

To finish verification, record the exact reference record ID, raw/cooked state, edible portion and reference basis for each matched food. For prepared foods, first define a representative recipe and serving mass or use a specific manufacturer label; otherwise retain an explicitly approximate, user-editable search estimate.
