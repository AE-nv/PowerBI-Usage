WITH app_versions AS (
    SELECT
        AppId,
        AppName,
        ActivityTime,
        ROW_NUMBER() OVER (
            PARTITION BY AppId, AppName
            ORDER BY ActivityTime ASC
        ) AS rn_per_name
    FROM {{ ref('stg_pbi_activity_events') }}
    WHERE AppId IS NOT NULL
),

latest_app AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY AppId
            ORDER BY ActivityTime DESC
        ) AS rn
    FROM app_versions
    WHERE rn_per_name = 1
)

SELECT
    AppId,
    AppName,
    ActivityTime AS LastUpdated
FROM latest_app
WHERE rn = 1;