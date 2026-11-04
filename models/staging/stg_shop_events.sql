{{
  config(
    materialized='view'
  )
}}

-- One row per GA4 event from the Shopify test store.
--
-- Lineage note: these events exist because of the tracking spec written in
-- session 12 and implemented in session 13 — dataLayer pushes in theme.liquid,
-- picked up by GTM Custom Event triggers, sent by GA4 ecommerce tags, landed
-- here by the daily BigQuery export.

select
    user_pseudo_id,

    -- GA4 session id is only unique within a user, never globally.
    -- Same caveat as int_sessions: always pair it with user_pseudo_id.
    (select value.int_value from unnest(event_params)
        where key = 'ga_session_id') as session_id,

    event_name,
    timestamp_micros(event_timestamp) as event_ts,
    date(timestamp_micros(event_timestamp)) as event_date,

    (select value.string_value from unnest(event_params)
        where key = 'page_location') as page_location,

    -- Custom parameter from the JS - Page Type variable (session 9).
    (select value.string_value from unnest(event_params)
        where key = 'page_type') as page_type,

    ecommerce.transaction_id,
    ecommerce.purchase_revenue,

    -- Repeated record; unnested in stg_shop_items.
    items

from {{ source('ga4_shop', 'events_*') }}
