select
    user_pseudo_id,
    session_id,
    min(event_ts) as session_start,
    max(event_ts) as session_end,
    timestamp_diff(max(event_ts), min(event_ts), second) as session_duration_seconds,
    count(*) as event_count,
    countif(event_name = 'purchase') > 0 as had_purchase
from {{ ref('stg_events') }}
group by 1, 2