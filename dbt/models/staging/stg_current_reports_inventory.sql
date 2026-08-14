SELECT DISTINCT
    report_id
FROM {{ source('lakehouse', 'pbi_current_reports_inventory') }}