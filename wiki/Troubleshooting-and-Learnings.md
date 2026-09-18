# Troubleshooting & Engineering Learnings

| Challenge | Root Cause | Resolution |
|:---|:---|:---|
| **ADLS 403 Forbidden in Portal** | User had Subscription Contributor but lacked Storage Data-Plane permissions. | Added `Storage Blob Data Contributor` RBAC role assignment via Terraform. |
| **Snowflake SQL Error: Invalid Identifier `ROWS_WRITTEN`** | Query referenced non-existent audit column. | Updated queries to use `ROWS_INSERTED`, `ROWS_UPDATED`, and `ROWS_REJECTED`. |
| **Azure SQL Connectivity Timeout** | Server firewall blocked Azure IP traffic and user was uninitialized. | Enabled `Allow Azure services to access this server` and configured credentials in Key Vault. |
| **Incremental Procedure Column Mismatch** | Delta table loaded `SPECIALTY` instead of `REQUIRED_ROLE` and `DEPARTMENT`. | Standardized delta schema and updated stored procedure mappings. |
| **Power BI Template Blank Visuals** | `.pbit` template only held theme metadata without visual containers. | Re-built report using native Power BI Project (`.pbip`) format with Tabular Model Definition Language (TMDL). |
