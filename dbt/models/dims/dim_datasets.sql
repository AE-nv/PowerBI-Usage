WITH dataset_versions AS (
    SELECT
        DatasetId,
        DatasetName,
        ActivityTime,
        ROW_NUMBER() OVER (
            PARTITION BY DatasetId, DatasetName
            ORDER BY ActivityTime ASC
        ) AS rn_per_name
    FROM {{ ref('stg_pbi_activity_events') }}
    WHERE DatasetId IS NOT NULL
),

latest_dataset AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY DatasetId
            ORDER BY ActivityTime DESC
        ) AS rn
    FROM dataset_versions
    WHERE rn_per_name = 1
)

SELECT
    DatasetId,
    DatasetName,
    ActivityTime AS LastUpdated
FROM latest_dataset
WHERE rn = 1;