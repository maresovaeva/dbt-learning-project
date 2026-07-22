{{
  config(
    materialized='incremental',
    unique_key=['user_pseudo_id', 'event_ts', 'event_name'],
    incremental_strategy='merge',
    partition_by={
      'field': 'event_ts',
      'data_type': 'timestamp',
      'granularity': 'day'
    },
    cluster_by=['user_pseudo_id']
  )
}}

select
    user_pseudo_id,
    event_name,
    timestamp_micros(event_timestamp) as event_ts,
    (select value.string_value from unnest(event_params)
        where key = 'page_location') as page_location,
    (select value.int_value from unnest(event_params)
        where key = 'ga_session_id') as session_id
from {{ source('ga4', 'events_*') }}
where _table_suffix between '20210101' and '20210131'

{% if is_incremental() %}
  and timestamp_micros(event_timestamp) > (
    select coalesce(
      max(event_ts),
      timestamp('1970-01-01')
    )
    from {{ this }}
    where event_ts > timestamp_sub(current_timestamp(), interval 3 day)
  )
{% endif %}