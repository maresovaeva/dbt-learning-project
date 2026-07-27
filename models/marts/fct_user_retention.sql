with first_seen as (
    select
        user_pseudo_id,
        min(date(session_start)) as first_session_date
    from {{ ref('int_sessions') }}
    group by 1
),

activity as (
    select
        user_pseudo_id,
        date(session_start) as active_date
    from {{ ref('int_sessions') }}
)

select
    f.first_session_date,
    count(distinct f.user_pseudo_id) as cohort_size,
    count(distinct case when a.active_date = date_add(f.first_session_date, interval 1 day)
        then a.user_pseudo_id end) as retained_day_1,
    round(count(distinct case when a.active_date = date_add(f.first_session_date, interval 1 day)
        then a.user_pseudo_id end) / count(distinct f.user_pseudo_id), 4) as day_1_retention_rate
from first_seen f
left join activity a on f.user_pseudo_id = a.user_pseudo_id
group by 1
order by 1