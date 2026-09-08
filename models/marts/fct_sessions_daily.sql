{{
  config(
    materialized='incremental',
    unique_key='session_date',
    incremental_strategy='merge',
    partition_by={
      'field': 'session_date',
      'data_type': 'date',
      'granularity': 'day'
    }
  )
}}

select
    date(session_start) as session_date,
    count(*) as total_sessions,
    count(distinct user_pseudo_id) as total_users,
    round(avg(session_duration_seconds), 1) as avg_session_duration_seconds,
    round(avg(event_count), 1) as avg_events_per_session,
    countif(had_purchase) as sessions_with_purchase,
    round(countif(had_purchase) / count(*), 4) as purchase_rate
from {{ ref('int_sessions') }}

{% if is_incremental() %}
where date(session_start) >= (
    select coalesce(date_sub(max(session_date), interval 3 day), date('1970-01-01'))
    from {{ this }}
)
{% endif %}

group by 1