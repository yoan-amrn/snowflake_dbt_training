select
    c.region,
    c.nation,
    date_trunc('year', o.order_date) as order_year,
    count(*)                         as nb_orders,
    sum(o.total_price)               as revenue
from {{ ref('stg_orders') }} o
join {{ ref('stg_customers') }} c using (customer_key)
group by all
