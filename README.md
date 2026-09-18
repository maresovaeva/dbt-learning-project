# dbt Learning Project: GA4 Ecommerce Analytics

A dbt project analyzing the [BigQuery public GA4 ecommerce sample dataset](https://console.cloud.google.com/marketplace/product/bigquery-public-data/ga4-ecommerce-sample) (Jan 2021) — built to practice production dbt patterns (incremental models, testing, documentation) and to answer a real analytical question: where does user retention and purchase conversion break down?

**Full write-up:** see [`CASE_STUDY.md`](CASE_STUDY.md) for the question, findings, and data quality issues found and fixed along the way.

## Project structure

```
models/
  staging/       stg_events        — one row per GA4 event, unnested from raw event_params
  intermediate/  int_sessions      — one row per session
  marts/         fct_sessions_daily     — daily session volume, engagement, purchase conversion
                 fct_user_retention     — day-1 retention by cohort date
                 fct_funnel_purchase    — view_item → add_to_cart → purchase funnel
analyses/
  retention_analysis.ipynb   — Python/Jupyter analysis and interpretation, pulling from the marts above
tests/
  assert_funnel_monotonic.sql — singular test guarding against funnel step counts increasing down-funnel
assets/
  chart PNGs referenced in CASE_STUDY.md
```

## Running this project

Requires a BigQuery connection with access to the `bigquery-public-data` project (the GA4 sample dataset is public).

```bash
# dbt
pip install dbt-bigquery
gcloud auth application-default login
dbt build

# Notebook
pip install -r requirements.txt
jupyter notebook analyses/retention_analysis.ipynb
```

## Notable design decisions

- **`stg_events` and `fct_sessions_daily` are incremental**, filtered/merged on event/session date rather than full-refreshing each run.
- **`fct_funnel_purchase` counts event *presence* per session, not strict order** (e.g. add-to-cart doesn't have to follow view-item). Verified this affects only ~0.26% of sessions — see the model's SQL comment and `CASE_STUDY.md` for detail.
- **`session_id` from GA4 is not globally unique** across users — every model that counts sessions uses `count(*)` on rows already deduplicated to `(user_pseudo_id, session_id)`, not `count(distinct session_id)`. Two real bugs from getting this wrong were caught and fixed during development (see `CASE_STUDY.md`).
