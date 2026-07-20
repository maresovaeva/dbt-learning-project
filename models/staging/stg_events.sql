select
    user_pseudo_id,
    event_name,
    timestamp_micros(event_timestamp) as event_ts,
    (select value.string_value from unnest(event_params) where key = 'page_location') as page_location,
    (select value.int_value from unnest(event_params) where key = 'ga_session_id') as session_id
from {{ source('ga4', 'events_20210131') }}