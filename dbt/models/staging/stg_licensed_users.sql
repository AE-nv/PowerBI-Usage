SELECT DISTINCT
    UserId,
    DisplayName,
    UserPrincipalName
FROM {{ source('lakehouse', 'pbi_licensed_users') }}