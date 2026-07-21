select
    date(session_start) as session_date,
    count(distinct session_id) as total_sessions,
    count(distinct user_pseudo_id) as total_users,
    round(avg(session_duration_seconds), 1) as avg_session_duration_seconds,
    round(avg(event_count), 1) as avg_events_per_session,
    countif(had_purchase) as sessions_with_purchase,
    round(countif(had_purchase) / count(*), 4) as purchase_rate
from {{ ref('int_sessions') }}
group by 1
order by 1