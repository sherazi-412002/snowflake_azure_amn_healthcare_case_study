-- =====================================================================================
-- AMN Healthcare Operational Database (Azure SQL Database)
-- Script 003: Update Data (Operational State Transitions & Modifications)
-- =====================================================================================
-- Purpose:
--   Executes operational state updates across candidate hiring, schedule tracking,
--   staffing fulfillment, and payroll calculation.
--
-- Note:
--   Every UPDATE statement explicitly refreshes `last_modified_at = SYSUTCDATETIME()`
--   to trigger Azure Data Factory incremental ingestion into Snowflake RAW.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. Candidate Workflow Updates: Credentialing & Placement
-- -------------------------------------------------------------------------------------
-- Scenario A: Advance Candidate CAND-503 from Interviewing to Placed
UPDATE dbo.candidates
SET
    candidate_status        = 'PLACED',
    credential_status       = 'VERIFIED',
    background_check_status = 'PASSED',
    employee_id             = 'EMP-8807',
    last_modified_at        = SYSUTCDATETIME()
WHERE candidate_id = 'CAND-503'
  AND is_deleted = 0;

-- Scenario B: Update Candidate CAND-508 with verified credentials and progress to INTERVIEWING
UPDATE dbo.candidates
SET
    candidate_status        = 'INTERVIEWING',
    credential_status       = 'IN_REVIEW',
    background_check_status = 'IN_PROGRESS',
    certifications          = 'BLS,ACLS,NRP,C-EFM,STABLE',
    last_modified_at        = SYSUTCDATETIME()
WHERE candidate_id = 'CAND-508'
  AND is_deleted = 0;


-- -------------------------------------------------------------------------------------
-- 2. Staffing Request Updates: Order Fulfillment & Rate Adjustments
-- -------------------------------------------------------------------------------------
-- Scenario A: Update REQ-2026-001 following the placement of CAND-503 (EMP-8807)
UPDATE dbo.staffing_requests
SET
    filled_staff     = filled_staff + 1,
    open_positions   = CASE WHEN open_positions > 1 THEN open_positions - 1 ELSE 0 END,
    request_status   = CASE WHEN open_positions - 1 = 0 THEN 'FILLED' ELSE 'IN_PROGRESS' END,
    last_modified_at = SYSUTCDATETIME()
WHERE request_id = 'REQ-2026-001'
  AND is_deleted = 0;

-- Scenario B: Increase bill rate and priority on high-demand ICU request REQ-2026-003
UPDATE dbo.staffing_requests
SET
    hourly_bill_rate = 110.00,
    priority         = 'Critical',
    last_modified_at = SYSUTCDATETIME()
WHERE request_id = 'REQ-2026-003'
  AND is_deleted = 0;


-- -------------------------------------------------------------------------------------
-- 3. Schedule Updates: Shift Completion & Overtime Logging
-- -------------------------------------------------------------------------------------
-- Scenario A: Clinician EMP-8801 completes shift SCH-10011 with 1.5 hours of emergency overtime
UPDATE dbo.schedules
SET
    worked_hours     = 13.50,
    overtime_hours   = 1.50,
    schedule_status  = 'COMPLETED',
    last_modified_at = SYSUTCDATETIME()
WHERE schedule_id = 'SCH-10011'
  AND is_deleted = 0;

-- Scenario B: Bulk-mark all past scheduled shifts as COMPLETED if currently in SCHEDULED state
UPDATE dbo.schedules
SET
    worked_hours     = planned_hours,
    schedule_status  = 'COMPLETED',
    last_modified_at = SYSUTCDATETIME()
WHERE work_date < CAST(SYSUTCDATETIME() AS DATE)
  AND schedule_status = 'SCHEDULED'
  AND is_deleted = 0;


-- -------------------------------------------------------------------------------------
-- 4. Payroll Updates: Calculation & Payment Disbursement
-- -------------------------------------------------------------------------------------
-- Scenario A: Recalculate gross and net pay for approved payroll record PAY-202602-005
UPDATE dbo.payroll
SET
    regular_hours      = 60.00,
    regular_pay        = 60.00 * hourly_pay_rate,
    bonus              = 200.00,
    gross_pay          = (60.00 * hourly_pay_rate) + 200.00,
    tax_amount         = ((60.00 * hourly_pay_rate) + 200.00) * 0.20,
    net_pay            = ((60.00 * hourly_pay_rate) + 200.00) - (((60.00 * hourly_pay_rate) + 200.00) * 0.20) - benefits_deduction,
    payment_status     = 'PAID',
    last_modified_at   = SYSUTCDATETIME()
WHERE payroll_id = 'PAY-202602-005'
  AND is_deleted = 0;

-- Scenario B: Batch-approve pending payroll records
UPDATE dbo.payroll
SET
    payment_status   = 'APPROVED',
    last_modified_at = SYSUTCDATETIME()
WHERE payment_status = 'PENDING'
  AND is_deleted = 0;
GO
