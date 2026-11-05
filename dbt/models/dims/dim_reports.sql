WITH name_changes AS (
    SELECT
        ReportId,
        ReportName,
        ActivityTime,
        ROW_NUMBER() OVER (
            PARTITION BY ReportId, ReportName
            ORDER BY ActivityTime DESC
        ) AS rn_per_name
    FROM {{ ref('stg_pbi_activity_events') }}
    WHERE ReportId IS NOT NULL
),

current_reports AS (
    SELECT DISTINCT
        report_id
    FROM {{ ref('stg_current_reports_inventory') }}
    WHERE report_id IS NOT NULL
),

latest_name AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY ReportId
            ORDER BY ActivityTime DESC
        ) AS rn
    FROM name_changes
    WHERE rn_per_name = 1
)

SELECT
    lr.ReportId,
    lr.ReportName,
    lr.ActivityTime AS LastUpdated,
    CASE
        WHEN cr.report_id IS NULL THEN 'Yes'
        ELSE 'No'
    END AS IsDeleted
FROM latest_name lr
LEFT JOIN current_reports cr
    ON lr.ReportId = cr.report_id
WHERE lr.rn = 1;
