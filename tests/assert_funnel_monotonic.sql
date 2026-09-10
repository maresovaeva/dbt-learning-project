-- Funnel counts should never increase down the funnel.
-- This test fails (returns rows) if that invariant is broken.
select *
from {{ ref('fct_funnel_purchase') }}
where not (
    total_sessions >= sessions_viewed_item
    and sessions_viewed_item >= sessions_added_to_cart
    and sessions_added_to_cart >= sessions_purchased
)