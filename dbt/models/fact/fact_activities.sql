SELECT
    Id AS activity_id,
    CAST(ActivityTime AS DATE) AS date_key, -- Joins to dim_date
    UserId,    -- Joins to dim_users
    AppId,     -- Joins to dim_apps
    ReportId,  -- Joins to dim_reports
    DatasetId, -- Joins to dim_datasets
    WorkspaceId, -- Joins to dim_workspaces
    CapacityId, -- Joins to dim_capacities
    Activity AS activity_name, -- Joins to dim_activity_types
    -- Keep the raw time for detail, but don't join on it
    ActivityTime 
FROM {{ ref('stg_pbi_activity_events') }}