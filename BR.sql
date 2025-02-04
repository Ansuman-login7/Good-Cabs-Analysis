#Business Request-1: The report generates data upon Total trips,Avg. fare/km,Avg. fare/trip and the % contribution of each city's trips to the overall trips.This report also helps in assessing trip volume,pricing efficiency and each city's contribution to overall trip count#

WITH city_trips AS (
    SELECT 
        dc.city_name,
        COUNT(ft.trip_id) AS total_trips,
        AVG(ft.fare_amount / NULLIF(ft.distance_travelled_km, 0)) AS avg_fare_per_km,
        SUM(ft.fare_amount) / COUNT(ft.trip_id) AS avg_fare_per_trip
    FROM fact_trips AS ft
    INNER JOIN dim_city AS dc ON ft.city_id = dc.city_id
    GROUP BY dc.city_name
)
SELECT 
    c.city_name,
    c.total_trips,
    c.avg_fare_per_km,
    c.avg_fare_per_trip,
    (c.total_trips / (SELECT COUNT(trip_id) FROM fact_trips) * 100) AS percentage_contribution
FROM city_trips AS c
ORDER BY percentage_contribution DESC;

#Business Request-2: Generate a report that evaluates the target performance for trips at the monthly and city level. For each City and Month,compare the actual with the target trips and categorise performance by:
	Request 1: Actual trips > target trips, then mark "Above Target".
	Request 2: Actual trips < target trips, then mark "Below Target".
	Request 3: Calculating % difference between actual and target trips#

With b as (select city_id,monthname(date) as month_name,month(date) as month,count(trip_id) as actual_trips 
	from fact_trips 
    group by city_id,monthname(date),month(date))
        
	select a.city_name,b.month_name,b.actual_trips,c.total_target_trips,
    case when (b.actual_trips - c.total_target_trips) < 0 then "Below Target" else "Above Target" end as performance_status,
    round((b.actual_trips - c.total_target_trips)/c.total_target_trips*100,2) as percentage_difference 
    from b
	inner join dim_city as a
	on a.city_id = b.city_id
	inner join (select *, monthname(month) as month_name from targets_db.monthly_target_trips) as c
	on c.city_id = b.city_id and c.month_name = b.month_name
order by a.city_name, b.month;

#Business Request-3: Generate a Report that shows the percentage distribution of repeat passengers by no. of trips they have taken in each city.Calculate % of repeat passengers who took 2 trips,3 trips and upto 10 trips#

WITH trip_distribution AS (
    SELECT 
        b.city_name, 
        a.trip_count, 
        sum(a.repeat_passenger_count) AS trip_sum
    FROM dim_repeat_trip_distribution a
    INNER JOIN dim_city b ON a.city_id = b.city_id
    GROUP BY b.city_name, a.trip_count
),
city_totals AS (
    SELECT 
        city_name, 
        SUM(trip_sum) AS city_sum 
    FROM trip_distribution 
    GROUP BY city_name
),
percentage_calculation AS (
    SELECT 
        t.city_name, 
        t.trip_count, 
        round((t.trip_sum / c.city_sum) * 100,2) AS percentage
    FROM trip_distribution t
    INNER JOIN city_totals c ON t.city_name = c.city_name
)
SELECT 
    city_name, 
    SUM(CASE WHEN trip_count = '2-Trips' THEN percentage ELSE 0 END) AS `2-Trips`,
    SUM(CASE WHEN trip_count = '3-Trips' THEN percentage ELSE 0 END) AS `3-Trips`,
    SUM(CASE WHEN trip_count = '4-Trips' THEN percentage ELSE 0 END) AS `4-Trips`,
    SUM(CASE WHEN trip_count = '5-Trips' THEN percentage ELSE 0 END) AS `5-Trips`,
    SUM(CASE WHEN trip_count = '6-Trips' THEN percentage ELSE 0 END) AS `6-Trips`,
    SUM(CASE WHEN trip_count = '7-Trips' THEN percentage ELSE 0 END) AS `7-Trips`,
    SUM(CASE WHEN trip_count = '8-Trips' THEN percentage ELSE 0 END) AS `8-Trips`,
    SUM(CASE WHEN trip_count = '9-Trips' THEN percentage ELSE 0 END) AS `9-Trips`,
    SUM(CASE WHEN trip_count = '10-Trips' THEN percentage ELSE 0 END) AS `10-Trips`
FROM percentage_calculation
GROUP BY city_name;


#Business Request-4: Generate a report that calculates the total new passengers for each city and ranks them well based on this value. Identify the highest and lowest no. of  new passengers for both Top-3 and Bottom-3 cities categorizing them as "Top-3" and "Bottom-3" respectively.#

WITH ranked_cities AS (
    SELECT 
        b.city_name, 
        SUM(a.new_passengers) AS total_new_passengers, 
        RANK() OVER (ORDER BY SUM(a.new_passengers) DESC) AS rnk
    FROM fact_passenger_summary a
    INNER JOIN dim_city b ON a.city_id = b.city_id
    GROUP BY b.city_name
)
SELECT 
    city_name, 
    total_new_passengers, 
    CASE 
        WHEN rnk <= 3 THEN 'Top 3'
        WHEN rnk >= 8 THEN 'Bottom 3' 
        ELSE 'Others' 
    END AS city_category
FROM ranked_cities;

#Business Request-5: Generate a report that identifies the month with highest revenue for each city.For each city,display month_name,revenue amount for the month and % contribution of the month's revenue to city's total revenue# 

WITH monthly_revenue AS (
    SELECT 
        b.city_name, 
        MONTHNAME(a.date) AS month_name, 
        SUM(a.fare_amount) AS revenue
    FROM fact_trips a
    INNER JOIN dim_city b ON a.city_id = b.city_id
    GROUP BY b.city_name, month_name
),
ranked_revenue AS (
    SELECT 
        city_name, 
        month_name, 
        revenue, 
        RANK() OVER (PARTITION BY city_name ORDER BY revenue DESC) AS rnk, 
        SUM(revenue) OVER (PARTITION BY city_name) AS total_revenue
    FROM monthly_revenue
)
SELECT 
    city_name, 
    month_name AS highest_revenue_month, 
    revenue AS Revenue_INR, 
    (revenue / total_revenue) * 100 AS percentage_contribution
FROM ranked_revenue
WHERE rnk = 1;

#Business Request-6 : Generate a report that calculates two metrices,
(a)Monthly Repeat Passenger Rate: Calculate the repeat passenger rate for each city and month by comparing the no. of repeat passenger to total passenger.
(b)City Wide Passenger Rate: Calculate the overall repeat passenger rate for each city,considering all passengers across months.
   These Metrics will provide insights into monthly repeat trends as well as the overall repeat behaviour of each city.#

WITH monthly_passenger_data AS (
    SELECT 
        b.city_name, 
        MONTHNAME(a.month) AS month, 
        MONTH(a.month) AS month_num, 
        a.total_passengers, 
        a.repeat_passengers,
        (a.repeat_passengers / a.total_passengers) * 100 AS monthly_repeat_passenger_rate
    FROM fact_passenger_summary a
    INNER JOIN dim_city b ON a.city_id = b.city_id
),
city_wide_totals AS (
    SELECT 
        city_name, 
        SUM(total_passengers) AS sum_total_passengers, 
        SUM(repeat_passengers) AS sum_repeat_passengers,
        Round(SUM(repeat_passengers) / SUM(total_passengers),2) * 100 AS city_wide_repeat_rate
    FROM fact_passenger_summary a
    INNER JOIN dim_city b ON a.city_id = b.city_id
    GROUP BY city_name
)
SELECT 
    m.city_name, 
    m.month, 
    m.total_passengers, 
    m.repeat_passengers, 
    m.monthly_repeat_passenger_rate, 
    c.city_wide_repeat_rate
FROM monthly_passenger_data m
INNER JOIN city_wide_totals c ON m.city_name = c.city_name
ORDER BY m.city_name, m.month_num;
