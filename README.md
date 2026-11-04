# dbt Learning Project: GA4 Ecommerce Analytics

Two connected pieces of work on GA4 data in BigQuery:

1. **Analysis** of the [public GA4 ecommerce sample](https://console.cloud.google.com/marketplace/product/bigquery-public-data/ga4-ecommerce-sample) (Jan 2021) — retention, session patterns and a purchase funnel, built to practise production dbt patterns and to answer a real question: where do retention and purchase conversion break down?
2. **Instrumentation** of a live store — tracking spec, GTM implementation, consent, and a funnel modelled from data collected through a pipeline I built end to end.

**Full write-up of the analysis:** see [`CASE_STUDY.md`](CASE_STUDY.md) for the question, findings, and data quality issues found and fixed along the way.

## Project structure

```
models/
  staging/       stg_events        — one row per GA4 event, unnested from raw event_params
                 stg_shop_events   — one row per GA4 event from my own instrumented store
                 stg_shop_items    — one row per event x item, unnested from the items array
  intermediate/  int_sessions      — one row per session
  marts/         fct_sessions_daily     — daily session volume, engagement, purchase conversion
                 fct_user_retention     — day-1 retention by cohort date
                 fct_funnel_purchase    — view_item → add_to_cart → purchase funnel (sample data)
                 fct_shop_funnel        — same funnel on my own instrumented data
analyses/
  retention_analysis.ipynb   — Python/Jupyter analysis and interpretation, pulling from the marts above
tests/
  assert_funnel_monotonic.sql — singular test guarding against funnel step counts increasing down-funnel
assets/
  chart PNGs referenced in CASE_STUDY.md
```

Models prefixed `shop_` read from my own store's export; everything else reads from the public sample.

## Instrumentation

A Shopify test store, instrumented end to end:

```
tracking spec  →  dataLayer pushes (theme.liquid)  →  GTM Custom Event triggers
               →  GA4 ecommerce tags  →  daily BigQuery export  →  dbt
```

Every hop was verified separately rather than inferred from the one before it. The events in `fct_shop_funnel` exist because of a spec I wrote, pushes I implemented, tags I configured and QA'd, and an export I set up — not because a platform provided them.

What this covers that the sample-data analysis does not:

- An ecommerce tracking spec that forces decisions before implementation: quantity semantics, variant identity, what counts as a success signal, and who owns each unanswered question
- Firing `add_to_cart` on the application's confirmed cart update rather than on a click, so failed adds aren't counted as successes
- Consent Mode v2 measured rather than assumed — consent state in the request, cookie behaviour under refusal, and the resulting gap between GA4's modelled UI figures and the raw export
- Why warehouse numbers legitimately read lower than the GA4 interface on consent-heavy EU traffic

**Volume is deliberately small.** It's a dev store and the traffic is mine. The artefact is the pipeline and the reasoning, not the figures.

## Running this project

Requires a BigQuery connection with access to the `bigquery-public-data` project (the GA4 sample dataset is public). The `shop_` models additionally read a private export and will not build without it.

```bash
# dbt
pip install dbt-bigquery
gcloud auth application-default login
dbt build

# Public-sample models only
dbt build --exclude stg_shop_events+

# Notebook
pip install -r requirements.txt
jupyter notebook analyses/retention_analysis.ipynb
```

Both sources must sit in the same BigQuery location as the target dataset (`US` here) — BigQuery cannot join across regions.

CI runs `dbt build` on every push and PR to `main` (`.github/workflows/dbt_ci.yml`).

## Notable design decisions

- **`stg_events` and `fct_sessions_daily` are incremental**, filtered/merged on event/session date rather than full-refreshing each run.
- **`fct_funnel_purchase` counts event *presence* per session, not strict order** (e.g. add-to-cart doesn't have to follow view-item). Verified this affects only ~0.26% of sessions — see the model's SQL comment and `CASE_STUDY.md` for detail.
- **`session_id` from GA4 is not globally unique** across users — every model that counts sessions uses `count(*)` on rows already deduplicated to `(user_pseudo_id, session_id)`, not `count(distinct session_id)`. Two real bugs from getting this wrong were caught and fixed during development (see `CASE_STUDY.md`).
- **`fct_shop_funnel` returns `NULL`, not `0`, for steps that aren't instrumented yet**, and carries an `implementation_status` column saying which is which. A zero reads as "measured, nobody converted"; a null reads as "not measured". Conflating the two is how a mart produces confident, wrong answers.

## Known gaps

Stated rather than hidden:

- `begin_checkout` and `purchase` are specified but not implemented on the instrumented store. Shopify's checkout runs on its own infrastructure where theme code and the GTM container don't execute; the sanctioned route is the Customer Events API.
- `item_variant` carries the product name rather than a variant name on the test store, because Shopify's generated products are titled that way. The mechanism is correct; the source data isn't realistic.
- `stg_events`' incremental filter anchors on `current_timestamp()` rather than the data's own max date — fragile for backfills.
