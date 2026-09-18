-- =====================================================================================
-- AMN Healthcare Operational Database (Azure SQL Database)
-- Script 004: Delete Data (Soft-Delete Watermark & Safe Hard-Delete)
-- =====================================================================================
-- Purpose:
--   Demonstrates both deletion strategies used in modern cloud data architectures:
--     1. Soft Deletes (Recommended for ADF/Snowflake Lakehouse pipelines):
--        Sets `is_deleted = 1` and updates `last_modified_at = SYSUTCDATETIME()`.
--        ADF captures the tombstone record and Snowflake MERGE handles the downstream removal/flagging.
--     2. Hard Deletes (Administrative maintenance / cleanup):
--        Uses explicit transaction control (BEGIN TRAN / COMMIT / ROLLBACK) and
--        proper child-to-parent deletion order to respect foreign key constraints.
-- =====================================================================================

-- =====================================================================================
-- SECTION 1: Soft-Delete Queries (Incremental Pipeline Compatible)
-- =====================================================================================

-- 1. Soft-delete a cancelled candidate application (e.g., candidate withdrew application)
UPDATE dbo.candidates
SET
    candidate_status = 'WITHDRAWN',
    is_deleted       = 1,
    last_modified_at = SYSUTCDATETIME()
WHERE candidate_id = 'CAND-508';

-- 2. Soft-delete an unfulfilled or cancelled staffing order
UPDATE dbo.staffing_requests
SET
    request_status   = 'CANCELLED',
    is_deleted       = 1,
    last_modified_at = SYSUTCDATETIME()
WHERE request_id = 'REQ-2026-006';

-- 3. Soft-delete a cancelled shift due to hospital low census
UPDATE dbo.schedules
SET
    schedule_status  = 'CANCELLED',
    is_deleted       = 1,
    last_modified_at = SYSUTCDATETIME()
WHERE schedule_id = 'SCH-10011';

-- 4. Soft-delete a duplicate/voided payroll draft entry
UPDATE dbo.payroll
SET
    payment_status   = 'VOID',
    is_deleted       = 1,
    last_modified_at = SYSUTCDATETIME()
WHERE payroll_id = 'PAY-202602-004'
  AND payment_status = 'PENDING';


-- =====================================================================================
-- SECTION 2: Safe Hard-Delete Operations (Transaction-Guarded)
-- =====================================================================================

-- Hard Delete Scenario A: Purge a specific test schedule record safely
BEGIN TRANSACTION;
    BEGIN TRY
        DELETE FROM dbo.schedules
        WHERE schedule_id = 'SCH-10009'
          AND is_deleted = 0;

        PRINT 'Successfully deleted schedule record SCH-10009.';
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        PRINT 'Error occurred during deletion. Transaction rolled back.';
        THROW;
    END CATCH;
GO

-- Hard Delete Scenario B: Purge test candidates and associated staffing request with FK safety
BEGIN TRANSACTION;
    BEGIN TRY
        -- 1. Delete dependent candidate references first
        DELETE FROM dbo.candidates
        WHERE request_id = 'REQ-2026-007';

        -- 2. Delete the parent staffing request
        DELETE FROM dbo.staffing_requests
        WHERE request_id = 'REQ-2026-007';

        PRINT 'Successfully purged request REQ-2026-007 and associated candidate records.';
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        PRINT 'Foreign key conflict or execution error. Transaction rolled back.';
        THROW;
    END CATCH;
GO

-- Hard Delete Scenario C: Purge stale soft-deleted tombstone records older than 90 days
-- (Run as an automated maintenance task after downstream Snowflake data lake has synced)
BEGIN TRANSACTION;
    BEGIN TRY
        DELETE FROM dbo.schedules
        WHERE is_deleted = 1
          AND last_modified_at < DATEADD(DAY, -90, SYSUTCDATETIME());

        DELETE FROM dbo.payroll
        WHERE is_deleted = 1
          AND last_modified_at < DATEADD(DAY, -90, SYSUTCDATETIME());

        DELETE FROM dbo.candidates
        WHERE is_deleted = 1
          AND last_modified_at < DATEADD(DAY, -90, SYSUTCDATETIME());

        DELETE FROM dbo.staffing_requests
        WHERE is_deleted = 1
          AND last_modified_at < DATEADD(DAY, -90, SYSUTCDATETIME());

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
GO
