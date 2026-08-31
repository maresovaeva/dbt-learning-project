{{
  config(
    materialized='incremental',
    unique_key=['user_pseudo_id', 'session_id'],
    incremental_strategy='merge'
  )
}}

select
    user_pseudo_id,
    session_id,
    min(event_ts) as session_start,
    max(event_ts) as session_end,
    timestamp_diff(max(event_ts), min(event_ts), second) as session_duration_seconds,
    count(*) as event_count,
    countif(event_name = 'purchase') > 0 as had_purchase
from {{ ref('stg_events') }}

{% if is_incremental() %}
where session_id in (
    select session_id from {{ ref('stg_events') }}
    where event_ts > (
        select coalesce(max(session_end), timestamp('1970-01-01')) from {{ this }}
    )
)
{% endif %}

group by 1, 2