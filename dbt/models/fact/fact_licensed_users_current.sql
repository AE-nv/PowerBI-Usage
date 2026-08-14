WITH licensed_users AS (
    SELECT
        UserId,
        DisplayName,
        UserPrincipalName
    FROM {{ ref('stg_licensed_users') }}
),

user_view_activity AS (
    SELECT
        UserId AS UserPrincipalName,
        CAST(MAX(ActivityTime) AS DATE) AS last_activity_date
    FROM {{ ref('fact_activities') }}
    WHERE activity_name = 'ViewReport'
      AND UserId IS NOT NULL
    GROUP BY UserId
)

SELECT
    -- We compare against yesterday because the data refresh runs overnight.
    lu.UserId,
    du.UserKey,
    lu.DisplayName,
    lu.UserPrincipalName,
    uva.last_activity_date,
    CASE
        WHEN uva.last_activity_date IS NULL THEN NULL
        ELSE DATEDIFF(DAY, uva.last_activity_date, DATEADD(DAY, -1, CAST(GETDATE() AS DATE)))
    END AS days_inactive,
    CASE
        WHEN uva.last_activity_date IS NULL THEN 'No activity recorded'
        WHEN DATEDIFF(DAY, uva.last_activity_date, DATEADD(DAY, -1, CAST(GETDATE() AS DATE))) < 30 THEN 'Active within 30 days'
        WHEN DATEDIFF(DAY, uva.last_activity_date, DATEADD(DAY, -1, CAST(GETDATE() AS DATE))) >= 30 
            AND DATEDIFF(DAY, uva.last_activity_date, DATEADD(DAY, -1, CAST(GETDATE() AS DATE))) < 60
        THEN 'Idle between 30 and 60 days'
        ELSE 'Idle for more than 60 days'
    END AS user_activity_status
FROM licensed_users lu
LEFT JOIN {{ ref('dim_users') }} du
    ON lu.UserPrincipalName = du.UserId
LEFT JOIN user_view_activity uva
    ON lu.UserPrincipalName = uva.UserPrincipalName


