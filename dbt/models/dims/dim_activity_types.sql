SELECT DISTINCT
    Activity AS ActivityName,
    CASE 
        WHEN Activity IN ('ViewReport') THEN 'view'
        WHEN Activity IN ('DownloadReport', 'ExportReport', 'PrintReport', 'ShareReport') THEN 'export'
        WHEN Activity IN ('CreateReport', 'UpdateReportContent') THEN 'contribute'
        ELSE 'other'
    END AS ActivityTypeName
FROM {{ ref('stg_pbi_activity_events') }}