WITH workspace_versions AS (
    SELECT
        WorkspaceId,
        WorkspaceName,
        ActivityTime,
        ROW_NUMBER() OVER (
            PARTITION BY WorkspaceId, WorkspaceName
            ORDER BY ActivityTime ASC
        ) AS rn_per_name
    FROM {{ ref('stg_pbi_activity_events') }}
    WHERE WorkspaceId IS NOT NULL
),

latest_workspace AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY WorkspaceId
            ORDER BY ActivityTime DESC
        ) AS rn
    FROM workspace_versions
    WHERE rn_per_name = 1
)

SELECT
    WorkspaceId,
    WorkspaceName,
    ActivityTime AS LastUpdated
FROM latest_workspace
WHERE rn = 1;