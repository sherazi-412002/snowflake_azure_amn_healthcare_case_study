-- =====================================================================================
-- AMN Healthcare Operational Database (Azure SQL Database)
-- Script 001: Table Creation DDL & Watermark Indexes
-- =====================================================================================
-- Purpose:
--   Establishes the operational tables simulated for AMN Healthcare staffing workflows:
--     1. staffing_requests  - Hospital job orders and demand
--     2. candidates         - Clinician applicants, credentialing, and placement
--     3. schedules          - Shift scheduling, actual worked hours, and overtime
--     4. payroll            - Monthly compensation, gross/net pay, and disbursements
--
--   Includes watermark metadata columns (is_deleted, created_at, last_modified_at)
--   for Azure Data Factory (ADF) incremental extraction into Snowflake.
-- =====================================================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'staffing_requests' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    CREATE TABLE dbo.staffing_requests (
        request_id             VARCHAR(50)     NOT NULL,
        hospital_id            VARCHAR(50)     NOT NULL,
        hospital_name          VARCHAR(150)    NOT NULL,
        city                   VARCHAR(100)    NOT NULL,
        state                  VARCHAR(50)     NOT NULL,
        required_role          VARCHAR(100)    NOT NULL,
        department             VARCHAR(100)    NOT NULL,
        employment_type        VARCHAR(50)     NOT NULL,
        shift_preference       VARCHAR(50)     NOT NULL,
        required_staff         INT             NOT NULL DEFAULT 1,
        filled_staff           INT             NOT NULL DEFAULT 0,
        open_positions         INT             NOT NULL DEFAULT 1,
        priority               VARCHAR(20)     NOT NULL DEFAULT 'Medium',
        request_status         VARCHAR(50)     NOT NULL DEFAULT 'OPEN',
        request_date           DATE            NOT NULL,
        assignment_start_date  DATE            NOT NULL,
        assignment_end_date    DATE            NOT NULL,
        duration_weeks         INT             NOT NULL DEFAULT 13,
        hourly_bill_rate       DECIMAL(10, 2)  NOT NULL,
        is_deleted             BIT             NOT NULL DEFAULT 0,
        created_at             DATETIME2(7)    NOT NULL DEFAULT SYSUTCDATETIME(),
        last_modified_at       DATETIME2(7)    NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT pk_staffing_requests PRIMARY KEY CLUSTERED (request_id)
    );

    CREATE NONCLUSTERED INDEX ix_staffing_requests_last_modified
        ON dbo.staffing_requests (last_modified_at)
        INCLUDE (is_deleted, request_status);
END;
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'candidates' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    CREATE TABLE dbo.candidates (
        candidate_id            VARCHAR(50)     NOT NULL,
        request_id              VARCHAR(50)     NULL,
        hospital_id             VARCHAR(50)     NULL,
        hospital_name           VARCHAR(150)    NULL,
        recruiter_id            VARCHAR(50)     NOT NULL,
        candidate_name          VARCHAR(150)    NOT NULL,
        email                   VARCHAR(150)    NOT NULL,
        phone                   VARCHAR(50)     NULL,
        profession              VARCHAR(100)    NOT NULL,
        department              VARCHAR(100)    NOT NULL,
        experience_years        INT             NOT NULL DEFAULT 0,
        license_state           VARCHAR(50)     NOT NULL,
        license_status          VARCHAR(50)     NOT NULL DEFAULT 'ACTIVE',
        certifications          VARCHAR(255)    NULL,
        source_channel          VARCHAR(50)     NOT NULL DEFAULT 'Direct',
        application_date        DATE            NOT NULL,
        candidate_status        VARCHAR(50)     NOT NULL DEFAULT 'APPLIED',
        background_check_status VARCHAR(50)     NOT NULL DEFAULT 'PENDING',
        credential_status       VARCHAR(50)     NOT NULL DEFAULT 'PENDING',
        employee_id             VARCHAR(50)     NULL,
        is_deleted              BIT             NOT NULL DEFAULT 0,
        created_at              DATETIME2(7)    NOT NULL DEFAULT SYSUTCDATETIME(),
        last_modified_at        DATETIME2(7)    NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT pk_candidates PRIMARY KEY CLUSTERED (candidate_id),
        CONSTRAINT fk_candidates_staffing_request FOREIGN KEY (request_id)
            REFERENCES dbo.staffing_requests (request_id)
    );

    CREATE NONCLUSTERED INDEX ix_candidates_last_modified
        ON dbo.candidates (last_modified_at)
        INCLUDE (is_deleted, candidate_status, employee_id);
END;
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'schedules' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    CREATE TABLE dbo.schedules (
        schedule_id       VARCHAR(50)     NOT NULL,
        employee_id       VARCHAR(50)     NOT NULL,
        request_id        VARCHAR(50)     NULL,
        hospital_id       VARCHAR(50)     NOT NULL,
        hospital_name     VARCHAR(150)    NOT NULL,
        work_date         DATE            NOT NULL,
        shift_type        VARCHAR(50)     NOT NULL,
        shift_start_time  TIME(0)         NOT NULL,
        shift_end_time    TIME(0)         NOT NULL,
        planned_hours     DECIMAL(5, 2)   NOT NULL DEFAULT 12.00,
        worked_hours      DECIMAL(5, 2)   NOT NULL DEFAULT 0.00,
        overtime_hours    DECIMAL(5, 2)   NOT NULL DEFAULT 0.00,
        schedule_status   VARCHAR(50)     NOT NULL DEFAULT 'SCHEDULED',
        is_deleted        BIT             NOT NULL DEFAULT 0,
        created_at        DATETIME2(7)    NOT NULL DEFAULT SYSUTCDATETIME(),
        last_modified_at  DATETIME2(7)    NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT pk_schedules PRIMARY KEY CLUSTERED (schedule_id)
    );

    CREATE NONCLUSTERED INDEX ix_schedules_last_modified
        ON dbo.schedules (last_modified_at)
        INCLUDE (is_deleted, employee_id, work_date, schedule_status);
END;
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'payroll' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    CREATE TABLE dbo.payroll (
        payroll_id          VARCHAR(50)     NOT NULL,
        employee_id         VARCHAR(50)     NOT NULL,
        hospital_id         VARCHAR(50)     NOT NULL,
        hospital_name       VARCHAR(150)    NOT NULL,
        payroll_month       VARCHAR(20)     NOT NULL,
        regular_hours       DECIMAL(8, 2)   NOT NULL DEFAULT 0.00,
        overtime_hours      DECIMAL(8, 2)   NOT NULL DEFAULT 0.00,
        hourly_pay_rate     DECIMAL(10, 2)  NOT NULL,
        regular_pay         DECIMAL(12, 2)  NOT NULL DEFAULT 0.00,
        overtime_pay        DECIMAL(12, 2)  NOT NULL DEFAULT 0.00,
        bonus               DECIMAL(12, 2)  NOT NULL DEFAULT 0.00,
        gross_pay           DECIMAL(12, 2)  NOT NULL DEFAULT 0.00,
        tax_amount          DECIMAL(12, 2)  NOT NULL DEFAULT 0.00,
        benefits_deduction  DECIMAL(12, 2)  NOT NULL DEFAULT 0.00,
        net_pay             DECIMAL(12, 2)  NOT NULL DEFAULT 0.00,
        payment_status      VARCHAR(50)     NOT NULL DEFAULT 'PENDING',
        is_deleted          BIT             NOT NULL DEFAULT 0,
        created_at          DATETIME2(7)    NOT NULL DEFAULT SYSUTCDATETIME(),
        last_modified_at    DATETIME2(7)    NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT pk_payroll PRIMARY KEY CLUSTERED (payroll_id)
    );

    CREATE NONCLUSTERED INDEX ix_payroll_last_modified
        ON dbo.payroll (last_modified_at)
        INCLUDE (is_deleted, employee_id, payroll_month, payment_status);
END;
GO
