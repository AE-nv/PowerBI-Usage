{{ config(materialized='table') }}
 
WITH n AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
    FROM (VALUES
        (0),(0),(0),(0),(0),(0),(0),(0),(0),(0)
    ) a(x)
    CROSS JOIN (VALUES
        (0),(0),(0),(0),(0),(0),(0),(0),(0),(0)
    ) b(x)
    CROSS JOIN (VALUES
        (0),(0),(0),(0),(0),(0),(0),(0),(0),(0)
    ) c(x)
    CROSS JOIN (VALUES
        (0),(0),(0),(0),(0),(0),(0),(0),(0),(0)
    ) d(x)
),
 
date_spine AS (
    SELECT
        DATEADD(DAY, n, CAST('2022-01-01' AS DATE)) AS date_day
    FROM n
    WHERE n <= DATEDIFF(DAY, '2022-01-01', '2030-12-31')
),
 
date_windows AS (
    SELECT
        CAST(GETDATE() AS DATE) AS today,
        DATEADD(MONTH, -1, CAST(GETDATE() AS DATE)) AS last_1_month_start,
        DATEADD(MONTH, -2, CAST(GETDATE() AS DATE)) AS last_2_months_start,
        DATEADD(MONTH, -4, CAST(GETDATE() AS DATE)) AS last_4_months_start,
        DATEADD(MONTH, -3, CAST(GETDATE() AS DATE)) AS last_3_months_start,
        DATEADD(MONTH, -6, CAST(GETDATE() AS DATE)) AS last_6_months_start,
        DATEADD(YEAR, -1, CAST(GETDATE() AS DATE)) AS last_1_year_start,
        DATEADD(YEAR, -2, CAST(GETDATE() AS DATE)) AS last_2_years_start
),

date_with_month_name AS (
    SELECT
        ds.date_day,
        CASE MONTH(ds.date_day)
            WHEN 1 THEN 'January'
            WHEN 2 THEN 'February'
            WHEN 3 THEN 'March'
            WHEN 4 THEN 'April'
            WHEN 5 THEN 'May'
            WHEN 6 THEN 'June'
            WHEN 7 THEN 'July'
            WHEN 8 THEN 'August'
            WHEN 9 THEN 'September'
            WHEN 10 THEN 'October'
            WHEN 11 THEN 'November'
            WHEN 12 THEN 'December'
        END AS month_name
    FROM date_spine ds
)
 
SELECT
    dmn.date_day AS date_key,
    YEAR(dmn.date_day) AS calendar_year,
    MONTH(dmn.date_day) AS calendar_month,
    dmn.month_name,
    LEFT(dmn.month_name, 3) AS month_name_short,
    DATEPART(QUARTER, dmn.date_day) AS calendar_quarter,
    DATEPART(WEEKDAY, dmn.date_day) AS day_of_week,
    CASE
        WHEN DATEPART(WEEKDAY, dmn.date_day) IN (1, 7) THEN 'Weekend'
        ELSE 'Weekday'
    END AS day_type,
 
    CASE
        WHEN dmn.date_day BETWEEN dw.last_3_months_start AND dw.today THEN 'Yes'
        ELSE 'No'
    END AS is_in_last_3_months,
    CASE
        WHEN dmn.date_day BETWEEN dw.last_1_month_start AND dw.today THEN 'Last 1 month'
        WHEN dmn.date_day BETWEEN dw.last_2_months_start AND dw.today THEN 'Last 2 months'
        WHEN dmn.date_day BETWEEN dw.last_3_months_start AND dw.today THEN 'Last 3 months'
        WHEN dmn.date_day BETWEEN dw.last_4_months_start AND dw.today THEN 'Last 4 months'
        WHEN dmn.date_day BETWEEN dw.last_6_months_start AND dw.today THEN 'Last 6 months'
        WHEN dmn.date_day BETWEEN dw.last_1_year_start AND dw.today THEN 'Last 1 year'
        WHEN dmn.date_day BETWEEN dw.last_2_years_start AND dw.today THEN 'Last 2 years'
        ELSE 'Outside last 2 years'
    END AS relative_period_bucket
FROM date_with_month_name dmn
CROSS JOIN date_windows dw;
 
 
