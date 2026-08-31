# dbt Learning Project — GA4 Event Analytics

A hands-on dbt Core project built end-to-end against a public GA4 e-commerce dataset, as a practical bridge from Digital Analytics Manager toward Analytics Engineer. Not a tutorial clone — every model, test, and CI step here was built and debugged from scratch.

## Stack
- **Warehouse:** Google BigQuery
- **dbt:** dbt-core 1.12.0 + dbt-bigquery
- **Source data:** `bigquery-public-data.ga4_obfuscated_sample_ecommerce` (Google Merchandise Store, Jan 2021)
- **CI:** GitHub Actions, running `dbt build` on every push and pull request

## Project structure
models/
├── staging/ stg_events (incremental, partitioned, unnested GA4 event_params)
├── intermediate/ int_sessions (session-level aggregation)
└── marts/
├── fct_sessions_daily daily session volume, engagement, purchase rate
├── fct_user_retention day-1 retention by cohort date
└── fct_funnel_purchase view_item → add_to_cart → purchase conversion


## Notable design decisions
- **Composite session key** (`user_pseudo_id` + `session_id`) — GA4's `ga_session_id` is not globally unique on its own.
- **Incremental + partitioned staging model** with a bounded-lookback filter guarded by `coalesce()` — an earlier version had a silent NULL-comparison bug that would have quietly stopped ingesting new data. See commit history / project journal for details.
- **Custom generic test** (`tests/generic/test_non_negative.sql`) enforcing no negative durations or counts, beyond dbt's built-in `not_null`/`unique`.

## Running locally
```bash
dbt debug          # verify connection
dbt build          # run + test everything
dbt docs generate && dbt docs serve   # browse lineage graph and column docs
```

## Workflow
New work happens on a feature branch, opened as a pull request, and merged only after GitHub Actions CI passes. `main` only ever contains code that's already been validated.

## Status
Actively in progress. See the project journal for the full build log, including every real infrastructure problem hit and how it was resolved.