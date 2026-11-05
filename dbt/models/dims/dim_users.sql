WITH user_versions AS (
    SELECT
        UserId,
        UserType,
        UserKey,
        ActivityTime,
        ROW_NUMBER() OVER (
            PARTITION BY UserId, UserType, UserKey
            ORDER BY ActivityTime DESC
        ) AS rn_per_version
    FROM {{ ref('stg_pbi_activity_events') }}
    WHERE UserId IS NOT NULL
),

latest_user AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY UserId
            ORDER BY ActivityTime DESC
        ) AS rn
    FROM user_versions
    WHERE rn_per_version = 1
)

SELECT
    UserId,
    UserType,
    UserKey,
    ActivityTime AS LastUpdated
FROM latest_user
WHERE rn = 1;