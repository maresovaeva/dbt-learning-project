{{
  config(
    materialized='table'
  )
}}

-- Ecommerce funnel, one row per step.
--
-- All four steps are listed even though only view_item and add_to_cart are
-- implemented. Unimplemented steps are flagged and return NULL rates rather
-- than 0: a 0 reads as "measured, nobody converted", a NULL reads as
-- "not measured". The distinction matters — begin_checkout and purchase
-- require the Shopify Customer Events API, which is not built yet.

with funnel_steps as (

    -- implementation_status is maintained by hand. Update it here when an
    -- event ships; nothing else in this model needs to change.
    select 1 as step_number, 'view_item'      as step_name, 'implemented'     as implementation_status union all
    select 2,                'add_to_cart',                 'implemented'                             union all
    select 3,                'begin_checkout',              'not_implemented'                         union all
    select 4,                'purchase',                    'not_implemented'

),

funnel_events as (

    select
        event_name,
        user_pseudo_id,
        -- session_id alone is not unique; pair it with the user.
        concat(user_pseudo_id, '-', cast(session_id as string)) as session_key
    from {{ ref('stg_shop_events') }}
    where event_name in ('view_item', 'add_to_cart', 'begin_checkout', 'purchase')

),

aggregated as (

    select
        event_name,
        count(*)                       as events,
        count(distinct user_pseudo_id) as users,
        count(distinct session_key)    as sessions
    from funnel_events
    group by 1

),

joined as (

    select
        s.step_number,
        s.step_name,
        s.implementation_status,

        -- Counts are NULL where the event is not instrumented, so they never
        -- get read as a measured zero.
        case when s.implementation_status = 'implemented'
             then coalesce(a.events, 0) end as events,
        case when s.implementation_status = 'implemented'
             then coalesce(a.users, 0) end as users,
        case when s.implementation_status = 'implemented'
             then coalesce(a.sessions, 0) end as sessions

    from funnel_steps s
    left join aggregated a
        on a.event_name = s.step_name

)

select
    step_number,
    step_name,
    implementation_status,
    events,
    users,
    sessions,

    -- Share of users who reached step 1 and also reached this step.
    round(safe_divide(
        users,
        first_value(users) over (order by step_number)
    ), 4) as pct_of_first_step,

    -- Step-to-step conversion. NULL on step 1 (no predecessor) and on any
    -- step where either side is not instrumented.
    round(safe_divide(
        users,
        lag(users) over (order by step_number)
    ), 4) as step_conversion_rate,

    users - lag(users) over (order by step_number) as user_drop_off

from joined
order by step_number