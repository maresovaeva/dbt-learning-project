with funnel_events as (
    select
        session_id,
        user_pseudo_id,
        max(case when event_name = 'view_item' then 1 else 0 end) as viewed_item,
        max(case when event_name = 'add_to_cart' then 1 else 0 end) as added_to_cart,
        max(case when event_name = 'purchase' then 1 else 0 end) as purchased
    from {{ ref('stg_events') }}
    group by 1, 2
)
select
    count(*) as total_sessions,
    countif(viewed_item = 1) as sessions_viewed_item,
    countif(viewed_item = 1 and added_to_cart = 1) as sessions_added_to_cart,
    countif(viewed_item = 1 and added_to_cart = 1 and purchased = 1) as sessions_purchased,
    round(countif(viewed_item = 1 and added_to_cart = 1)
        / nullif(countif(viewed_item = 1), 0), 4) as view_to_cart_rate,
    round(countif(viewed_item = 1 and added_to_cart = 1 and purchased = 1)
        / nullif(countif(viewed_item = 1 and added_to_cart = 1), 0), 4) as cart_to_purchase_rate
from funnel_events