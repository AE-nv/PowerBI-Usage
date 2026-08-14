WITH capacity_versions AS (
    SELECT
        CapacityId,
        CapacityName,
        ActivityTime,
        ROW_NUMBER() OVER (
            PARTITION BY CapacityId, CapacityName
            ORDER BY ActivityTime ASC
        ) AS rn_per_name
    FROM {{ ref('stg_pbi_activity_events') }}
    WHERE CapacityId IS NOT NULL
),

latest_capacity AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY CapacityId
            ORDER BY ActivityTime DESC
        ) AS rn
    FROM capacity_versions
    WHERE rn_per_name = 1
)

SELECT
    CapacityId,
    CapacityName,
    ActivityTime AS LastUpdated
FROM latest_capacity
WHERE rn = 1;