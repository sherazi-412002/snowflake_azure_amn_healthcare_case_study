-- =====================================================================================
-- AMN Healthcare Operational Database (Azure SQL Database)
-- Script 002: Insert Data (Initial Seed & Operational Workloads)
-- =====================================================================================
-- Purpose:
--   Inserts realistic operational sample records across all four core entities:
--     1. staffing_requests  (Orders from partner health systems)
--     2. candidates         (Clinician profiles & pipeline statuses)
--     3. schedules          (Shift rosters and worked logs)
--     4. payroll            (Clinician payroll cycle transactions)
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. Insert Staffing Requests
-- -------------------------------------------------------------------------------------
INSERT INTO dbo.staffing_requests (
    request_id, hospital_id, hospital_name, city, state, required_role, department,
    employment_type, shift_preference, required_staff, filled_staff, open_positions,
    priority, request_status, request_date, assignment_start_date, assignment_end_date,
    duration_weeks, hourly_bill_rate, is_deleted, created_at, last_modified_at
)
VALUES
    ('REQ-2026-001', 'HOSP-101', 'Memorial Hermann Hospital', 'Houston', 'TX', 'ICU Registered Nurse', 'Intensive Care Unit', 'Travel Nurse', 'Night', 5, 2, 3, 'High', 'OPEN', '2026-01-10', '2026-02-01', '2026-05-03', 13, 115.00, 0, SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('REQ-2026-002', 'HOSP-102', 'Cedars-Sinai Medical Center', 'Los Angeles', 'CA', 'Emergency Room RN', 'Emergency', 'Travel Nurse', 'Day', 4, 4, 0, 'Critical', 'FILLED', '2026-01-12', '2026-02-15', '2026-05-17', 13, 135.00, 0, SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('REQ-2026-003', 'HOSP-103', 'Mayo Clinic Hospital', 'Rochester', 'MN', 'Telemetry RN', 'Cardiology', 'Per Diem', 'Rotating', 2, 0, 2, 'Medium', 'OPEN', '2026-01-15', '2026-03-01', '2026-05-31', 13, 98.00, 0, SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('REQ-2026-004', 'HOSP-104', 'Johns Hopkins Hospital', 'Baltimore', 'MD', 'Surgical Technologist', 'Operating Room', 'Direct Hire', 'Day', 3, 1, 2, 'High', 'IN_PROGRESS', '2026-01-18', '2026-02-20', '2026-08-20', 26, 85.00, 0, SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('REQ-2026-005', 'HOSP-105', 'Cleveland Clinic', 'Cleveland', 'OH', 'NICU Nurse Specialist', 'Neonatal ICU', 'Travel Nurse', 'Night', 2, 2, 0, 'Critical', 'FILLED', '2026-01-20', '2026-02-10', '2026-05-12', 13, 125.00, 0, SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('REQ-2026-006', 'HOSP-106', 'Massachusetts General Hospital', 'Boston', 'MA', 'Oncology Nurse Practitioner', 'Oncology', 'Locum Tenens', 'Day', 1, 0, 1, 'Medium', 'OPEN', '2026-01-22', '2026-03-15', '2026-09-15', 26, 145.00, 0, SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('REQ-2026-007', 'HOSP-107', 'Stanford Health Care', 'Palo Alto', 'CA', 'Labor & Delivery RN', 'Obstetrics', 'Travel Nurse', 'Night', 3, 0, 3, 'High', 'OPEN', '2026-01-25', '2026-03-01', '2026-05-31', 13, 130.00, 0, SYSUTCDATETIME(), SYSUTCDATETIME());

-- -------------------------------------------------------------------------------------
-- 2. Insert Candidates
-- -------------------------------------------------------------------------------------
INSERT INTO dbo.candidates (
    candidate_id, request_id, hospital_id, hospital_name, recruiter_id, candidate_name,
    email, phone, profession, department, experience_years, license_state, license_status,
    certifications, source_channel, application_date, candidate_status, background_check_status,
    credential_status, employee_id, is_deleted, created_at, last_modified_at
)
VALUES
    ('CAND-501', 'REQ-2026-001', 'HOSP-101', 'Memorial Hermann Hospital', 'REC-01', 'Sarah Jenkins, RN', 'sarah.jenkins@clinicianmail.com', '555-019-2831', 'Registered Nurse', 'Intensive Care Unit', 6, 'TX', 'ACTIVE', 'BLS,ACLS,CCRN', 'AMN Portal', '2026-01-11', 'PLACED', 'PASSED', 'VERIFIED', 'EMP-8801', 0, SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('CAND-502', 'REQ-2026-001', 'HOSP-101', 'Memorial Hermann Hospital', 'REC-01', 'Marcus Vance, RN', 'marcus.vance@clinicianmail.com', '555-019-4412', 'Registered Nurse', 'Intensive Care Unit', 4, 'TX', 'ACTIVE', 'BLS,ACLS', 'Referral', '2026-01-13', 'PLACED', 'PASSED', 'VERIFIED', 'EMP-8802', 0, SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('CAND-503', 'REQ-2026-001', 'HOSP-101', 'Memorial Hermann Hospital', 'REC-02', 'Elena Rostova, RN', 'elena.rostova@clinicianmail.com', '555-019-9943', 'Registered Nurse', 'Intensive Care Unit', 8, 'TX', 'ACTIVE', 'BLS,ACLS,CCRN', 'LinkedIn', '2026-01-16', 'INTERVIEWING', 'PASSED', 'IN_REVIEW', NULL, 0, SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('CAND-504', 'REQ-2026-002', 'HOSP-102', 'Cedars-Sinai Medical Center', 'REC-03', 'David Kim, BSN', 'david.kim@clinicianmail.com', '555-021-3388', 'Emergency Nurse', 'Emergency', 5, 'CA', 'ACTIVE', 'BLS,ACLS,PALS,TNCC', 'AMN Portal', '2026-01-14', 'PLACED', 'PASSED', 'VERIFIED', 'EMP-8803', 0, SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('CAND-505', 'REQ-2026-002', 'HOSP-102', 'Cedars-Sinai Medical Center', 'REC-03', 'Rachel Chen, RN', 'rachel.chen@clinicianmail.com', '555-021-7711', 'Emergency Nurse', 'Emergency', 7, 'CA', 'ACTIVE', 'BLS,ACLS,TNCC', 'Indeed', '2026-01-15', 'PLACED', 'PASSED', 'VERIFIED', 'EMP-8804', 0, SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('CAND-506', 'REQ-2026-004', 'HOSP-104', 'Johns Hopkins Hospital', 'REC-04', 'James Morales, CST', 'james.morales@clinicianmail.com', '555-033-1122', 'Surgical Tech', 'Operating Room', 3, 'MD', 'ACTIVE', 'NBSTSA,BLS', 'Direct', '2026-01-20', 'PLACED', 'PASSED', 'VERIFIED', 'EMP-8805', 0, SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('CAND-507', 'REQ-2026-005', 'HOSP-105', 'Cleveland Clinic', 'REC-05', 'Olivia Taylor, RN', 'olivia.taylor@clinicianmail.com', '555-044-8899', 'NICU Nurse', 'Neonatal ICU', 5, 'OH', 'ACTIVE', 'BLS,NRP,RNC-NIC', 'AMN Portal', '2026-01-21', 'PLACED', 'PASSED', 'VERIFIED', 'EMP-8806', 0, SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('CAND-508', 'REQ-2026-007', 'HOSP-107', 'Stanford Health Care', 'REC-02', 'Hannah Scott, RN', 'hannah.scott@clinicianmail.com', '555-055-6677', 'Labor & Delivery RN', 'Obstetrics', 9, 'CA', 'ACTIVE', 'BLS,ACLS,NRP,C-EFM', 'Referral', '2026-01-26', 'APPLIED', 'PENDING', 'PENDING', NULL, 0, SYSUTCDATETIME(), SYSUTCDATETIME());

-- -------------------------------------------------------------------------------------
-- 3. Insert Schedules
-- -------------------------------------------------------------------------------------
INSERT INTO dbo.schedules (
    schedule_id, employee_id, request_id, hospital_id, hospital_name, work_date,
    shift_type, shift_start_time, shift_end_time, planned_hours, worked_hours,
    overtime_hours, schedule_status, is_deleted, created_at, last_modified_at
)
VALUES
    ('SCH-10001', 'EMP-8801', 'REQ-2026-001', 'HOSP-101', 'Memorial Hermann Hospital', '2026-02-02', 'Night', '19:00', '07:30', 12.00, 12.50, 0.50, 'COMPLETED', 0, SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('SCH-10002', 'EMP-8801', 'REQ-2026-001', 'HOSP-101', 'Memorial Hermann Hospital', '2026-02-04', 'Night', '19:00', '07:30', 12.00, 12.00, 0.00, 'COMPLETED', 0, SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('SCH-10003', 'EMP-8801', 'REQ-2026-001', 'HOSP-101', 'Memorial Hermann Hospital', '2026-02-06', 'Night', '19:00', '07:30', 12.00, 14.00, 2.00, 'COMPLETED', 0, SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('SCH-10004', 'EMP-8802', 'REQ-2026-001', 'HOSP-101', 'Memorial Hermann Hospital', '2026-02-03', 'Night', '19:00', '07:30', 12.00, 12.00, 0.00, 'COMPLETED', 0, SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('SCH-10005', 'EMP-8802', 'REQ-2026-001', 'HOSP-101', 'Memorial Hermann Hospital', '2026-02-05', 'Night', '19:00', '07:30', 12.00, 13.50, 1.50, 'COMPLETED', 0, SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('SCH-10006', 'EMP-8803', 'REQ-2026-002', 'HOSP-102', 'Cedars-Sinai Medical Center', '2026-02-16', 'Day', '07:00', '19:30', 12.00, 12.00, 0.00, 'COMPLETED', 0, SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('SCH-10007', 'EMP-8803', 'REQ-2026-002', 'HOSP-102', 'Cedars-Sinai Medical Center', '2026-02-18', 'Day', '07:00', '19:30', 12.00, 12.00, 0.00, 'COMPLETED', 0, SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('SCH-10008', 'EMP-8804', 'REQ-2026-002', 'HOSP-102', 'Cedars-Sinai Medical Center', '2026-02-17', 'Day', '07:00', '19:30', 12.00, 12.00, 0.00, 'COMPLETED', 0, SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('SCH-10009', 'EMP-8805', 'REQ-2026-004', 'HOSP-104', 'Johns Hopkins Hospital', '2026-02-22', 'Day', '06:30', '15:00', 8.00, 8.00, 0.00, 'COMPLETED', 0, SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('SCH-10010', 'EMP-8806', 'REQ-2026-005', 'HOSP-105', 'Cleveland Clinic', '2026-02-11', 'Night', '19:00', '07:30', 12.00, 12.00, 0.00, 'COMPLETED', 0, SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('SCH-10011', 'EMP-8801', 'REQ-2026-001', 'HOSP-101', 'Memorial Hermann Hospital', '2026-02-10', 'Night', '19:00', '07:30', 12.00, 0.00, 0.00, 'SCHEDULED', 0, SYSUTCDATETIME(), SYSUTCDATETIME());

-- -------------------------------------------------------------------------------------
-- 4. Insert Payroll Records
-- -------------------------------------------------------------------------------------
INSERT INTO dbo.payroll (
    payroll_id, employee_id, hospital_id, hospital_name, payroll_month,
    regular_hours, overtime_hours, hourly_pay_rate, regular_pay, overtime_pay, bonus,
    gross_pay, tax_amount, benefits_deduction, net_pay, payment_status,
    is_deleted, created_at, last_modified_at
)
VALUES
    ('PAY-202602-001', 'EMP-8801', 'HOSP-101', 'Memorial Hermann Hospital', '2026-02', 144.00, 10.50, 75.00, 10800.00, 1181.25, 500.00, 12481.25, 2496.25, 350.00, 9635.00, 'PAID', 0, SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('PAY-202602-002', 'EMP-8802', 'HOSP-101', 'Memorial Hermann Hospital', '2026-02', 144.00, 6.00, 72.00, 10368.00, 648.00, 250.00, 11266.00, 2253.20, 320.00, 8692.80, 'PAID', 0, SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('PAY-202602-003', 'EMP-8803', 'HOSP-102', 'Cedars-Sinai Medical Center', '2026-02', 80.00, 0.00, 88.00, 7040.00, 0.00, 1000.00, 8040.00, 1768.80, 280.00, 5991.20, 'PAID', 0, SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('PAY-202602-004', 'EMP-8804', 'HOSP-102', 'Cedars-Sinai Medical Center', '2026-02', 72.00, 4.00, 85.00, 6120.00, 510.00, 0.00, 6630.00, 1458.60, 290.00, 4881.40, 'PAID', 0, SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('PAY-202602-005', 'EMP-8805', 'HOSP-104', 'Johns Hopkins Hospital', '2026-02', 48.00, 0.00, 52.00, 2496.00, 0.00, 0.00, 2496.00, 499.20, 150.00, 1846.80, 'APPROVED', 0, SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('PAY-202602-006', 'EMP-8806', 'HOSP-105', 'Cleveland Clinic', '2026-02', 96.00, 8.00, 82.00, 7872.00, 984.00, 500.00, 9356.00, 2058.32, 310.00, 6987.68, 'PAID', 0, SYSUTCDATETIME(), SYSUTCDATETIME());
GO
