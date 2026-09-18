-- =====================================================================================
-- AMN Healthcare Operational Database (Azure SQL Database)
-- Script 005: Verification & Incremental Watermark Diagnostics
-- =====================================================================================
-- Purpose:
--   Diagnostic and query script to inspect operational data state, verify CRUD operations,
--   and simulate Azure Data Factory (ADF) watermark delta detection queries.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. Table Row Counts & Soft-Delete Distribution
-- -------------------------------------------------------------------------------------
SELECT 'staffing_requests' AS table_name,
       COUNT(*) AS total_rows,
       SUM(CASE WHEN is_deleted = 0 THEN 1 ELSE 0 END) AS active_rows,
       SUM(CASE WHEN is_deleted = 1 THEN 1 ELSE 0 END) AS soft_deleted_rows,
       MAX(last_modified_at) AS max_watermark
FROM dbo.staffing_requests
UNION ALL
SELECT 'candidates',
       COUNT(*),
       SUM(CASE WHEN is_deleted = 0 THEN 1 ELSE 0 END),
       SUM(CASE WHEN is_deleted = 1 THEN 1 ELSE 0 END),
       MAX(last_modified_at)
FROM dbo.candidates
UNION ALL
SELECT 'schedules',
       COUNT(*),
       SUM(CASE WHEN is_deleted = 0 THEN 1 ELSE 0 END),
       SUM(CASE WHEN is_deleted = 1 THEN 1 ELSE 0 END),
       MAX(last_modified_at)
FROM dbo.schedules
UNION ALL
SELECT 'payroll',
       COUNT(*),
       SUM(CASE WHEN is_deleted = 0 THEN 1 ELSE 0 END),
       SUM(CASE WHEN is_deleted = 1 THEN 1 ELSE 0 END),
       MAX(last_modified_at)
FROM dbo.payroll;

-- -------------------------------------------------------------------------------------
-- 2. Query Active Operational Records with Joined Views
-- -------------------------------------------------------------------------------------
-- View Active Staffing Requests & Fulfillment Progress
SELECT
    r.request_id,
    r.hospital_name,
    r.city,
    r.state,
    r.required_role,
    r.department,
    r.required_staff,
    r.filled_staff,
    r.open_positions,
    r.priority,
    r.request_status,
    r.hourly_bill_rate,
    r.last_modified_at
FROM dbo.staffing_requests r
WHERE r.is_deleted = 0
ORDER BY r.request_date DESC;

-- View Candidates with Associated Request Details
SELECT
    c.candidate_id,
    c.candidate_name,
    c.profession,
    c.candidate_status,
    c.credential_status,
    c.employee_id,
    r.request_id,
    r.hospital_name,
    c.last_modified_at
FROM dbo.candidates c
LEFT JOIN dbo.staffing_requests r ON c.request_id = r.request_id
WHERE c.is_deleted = 0
ORDER BY c.application_date DESC;

-- View Scheduled Shifts with Overtime
SELECT
    s.schedule_id,
    s.employee_id,
    s.hospital_name,
    s.work_date,
    s.shift_type,
    s.planned_hours,
    s.worked_hours,
    s.overtime_hours,
    s.schedule_status,
    s.last_modified_at
FROM dbo.schedules s
WHERE s.is_deleted = 0
ORDER BY s.work_date DESC;

-- View Payroll Summary by Status
SELECT
    p.payment_status,
    COUNT(*) AS total_disbursements,
    SUM(p.gross_pay) AS total_gross_pay,
    SUM(p.tax_amount) AS total_tax,
    SUM(p.net_pay) AS total_net_disbursed
FROM dbo.payroll p
WHERE p.is_deleted = 0
GROUP BY p.payment_status;

-- -------------------------------------------------------------------------------------
-- 3. Simulate ADF Incremental Watermark Delta Query
-- -------------------------------------------------------------------------------------
-- Example: Simulate ADF retrieving rows modified since previous watermark timestamp
DECLARE @PreviousWatermark DATETIME2(7) = DATEADD(HOUR, -1, SYSUTCDATETIME());
DECLARE @CurrentWatermark  DATETIME2(7) = SYSUTCDATETIME();

-- A. Delta extract for staffing_requests
SELECT *
FROM dbo.staffing_requests
WHERE last_modified_at > @PreviousWatermark
  AND last_modified_at <= @CurrentWatermark;

-- B. Delta extract for candidates
SELECT *
FROM dbo.candidates
WHERE last_modified_at > @PreviousWatermark
  AND last_modified_at <= @CurrentWatermark;

-- C. Delta extract for schedules
SELECT *
FROM dbo.schedules
WHERE last_modified_at > @PreviousWatermark
  AND last_modified_at <= @CurrentWatermark;

-- D. Delta extract for payroll
SELECT *
FROM dbo.payroll
WHERE last_modified_at > @PreviousWatermark
  AND last_modified_at <= @CurrentWatermark;
GO
