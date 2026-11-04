{{
  config(
    materialized='view'
  )
}}

-- One row per event x item. GA4 stores items as a repeated record, so a single
-- add_to_cart carrying three products produces three rows here.

select
    e.user_pseudo_id,
    e.session_id,
    e.event_name,
    e.event_ts,
    e.event_date,

    item.item_id,
    item.item_name,

    -- Known defect (spec 13.5 #1): view_item and add_to_cart resolve this
    -- field differently, so the same product can appear with the product name
    -- on one event and null on the other. Not yet fixed in theme.liquid.
    nullif(item.item_variant, '(not set)') as item_variant,

    item.item_brand,
    item.item_category,
    item.price,
    item.quantity,
    item.price * item.quantity as item_revenue

from {{ ref('stg_shop_events') }} e,
unnest(e.items) as item
