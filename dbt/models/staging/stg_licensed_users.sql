SELECT DISTINCT
    UserId,
    DisplayName,
    LOWER(UserPrincipalName) AS UserPrincipalName
FROM {{ source('lakehouse', 'pbi_licensed_users') }}