from __future__ import annotations

import random
import sys
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Iterable

import pandas as pd
from faker import Faker


# ============================================================
# Configuration
# ============================================================

RANDOM_SEED = 42

# Development-stage data volume
NUM_RECRUITERS = 500
NUM_CANDIDATES = 150_000
NUM_EMPLOYEES = 50_000
NUM_STAFFING_REQUESTS = 75_000
NUM_SCHEDULES = 525_000
PAYROLL_MONTHS = 6

fake = Faker("en_US")
Faker.seed(RANDOM_SEED)
random.seed(RANDOM_SEED)


# ============================================================
# Project paths
# ============================================================

PROJECT_ROOT = Path(__file__).resolve().parent.parent

CMS_FILE = (
    PROJECT_ROOT
    / "datasets"
    / "cms"
    / "hospitals_reference.csv"
)

SYNTHEA_ORGANIZATIONS_FILE = (
    PROJECT_ROOT
    / "datasets"
    / "processed"
    / "synthea"
    / "organizations_amn.csv"
)

OUTPUT_DIR = Path(r"G:\My Drive\AMN_1M_Data\hr")


# ============================================================
# AMN business values
# ============================================================

HEALTHCARE_ROLES = [
    {
        "role": "Registered Nurse",
        "department": "General Nursing",
        "hourly_rate_min": 38,
        "hourly_rate_max": 65,
    },
    {
        "role": "ICU Nurse",
        "department": "Intensive Care Unit",
        "hourly_rate_min": 50,
        "hourly_rate_max": 85,
    },
    {
        "role": "Emergency Room Nurse",
        "department": "Emergency Department",
        "hourly_rate_min": 48,
        "hourly_rate_max": 80,
    },
    {
        "role": "Travel Nurse",
        "department": "Travel Nursing",
        "hourly_rate_min": 55,
        "hourly_rate_max": 95,
    },
    {
        "role": "Physician",
        "department": "Medical Services",
        "hourly_rate_min": 110,
        "hourly_rate_max": 220,
    },
    {
        "role": "Allied Health Professional",
        "department": "Allied Health",
        "hourly_rate_min": 35,
        "hourly_rate_max": 70,
    },
    {
        "role": "Respiratory Therapist",
        "department": "Respiratory Care",
        "hourly_rate_min": 38,
        "hourly_rate_max": 65,
    },
    {
        "role": "Radiologic Technologist",
        "department": "Radiology",
        "hourly_rate_min": 35,
        "hourly_rate_max": 62,
    },
    {
        "role": "Laboratory Technician",
        "department": "Laboratory",
        "hourly_rate_min": 28,
        "hourly_rate_max": 48,
    },
    {
        "role": "Physical Therapist",
        "department": "Rehabilitation",
        "hourly_rate_min": 42,
        "hourly_rate_max": 72,
    },
]

EMPLOYMENT_TYPES = [
    "Travel Contract",
    "Local Contract",
    "Per Diem",
    "Permanent Placement",
]

SHIFT_TYPES = [
    ("Day", "07:00", "19:00", 12),
    ("Night", "19:00", "07:00", 12),
    ("Morning", "07:00", "15:00", 8),
    ("Evening", "15:00", "23:00", 8),
]

CANDIDATE_STATUSES = [
    "Applied",
    "Screening",
    "Interview",
    "Credential Review",
    "Offer",
    "Hired",
    "Rejected",
    "Withdrawn",
]

REQUEST_PRIORITIES = [
    "Low",
    "Medium",
    "High",
    "Critical",
]

REQUEST_STATUSES = [
    "Open",
    "Partially Filled",
    "Filled",
    "Cancelled",
]

SOURCE_CHANNELS = [
    "AMN Careers Portal",
    "LinkedIn",
    "Employee Referral",
    "Recruitment Event",
    "Job Board",
    "Direct Application",
]

CERTIFICATIONS = [
    "BLS",
    "ACLS",
    "PALS",
    "NRP",
    "TNCC",
    "CPI",
]


# ============================================================
# General helper functions
# ============================================================

def require_file(path: Path) -> None:
    """Stop execution if a required file is missing."""
    if not path.exists():
        raise FileNotFoundError(f"Required file not found: {path}")


def normalize_headers(df: pd.DataFrame) -> pd.DataFrame:
    """Convert headers to uppercase snake case."""
    df = df.copy()

    df.columns = (
        df.columns.astype(str)
        .str.strip()
        .str.upper()
        .str.replace("/", "_", regex=False)
        .str.replace("-", "_", regex=False)
        .str.replace(" ", "_", regex=False)
        .str.replace(r"[^A-Z0-9_]", "", regex=True)
        .str.replace(r"_+", "_", regex=True)
        .str.strip("_")
    )

    return df


def find_column(
    df: pd.DataFrame,
    candidates: Iterable[str],
    required: bool = True,
) -> str | None:
    """Find a column using several possible names."""
    available = set(df.columns)

    for candidate in candidates:
        normalized = (
            candidate.strip()
            .upper()
            .replace("/", "_")
            .replace("-", "_")
            .replace(" ", "_")
        )

        if normalized in available:
            return normalized

    if required:
        raise KeyError(
            f"Required column was not found.\n"
            f"Expected one of: {list(candidates)}\n"
            f"Available columns: {df.columns.tolist()}"
        )

    return None


def random_date_between(
    start_date: date,
    end_date: date,
) -> date:
    """Return one random date between two dates."""
    if end_date < start_date:
        start_date, end_date = end_date, start_date

    difference = (end_date - start_date).days

    return start_date + timedelta(
        days=random.randint(0, max(difference, 0))
    )


def month_start(reference_date: date, months_back: int) -> date:
    """Return the first day of a previous month."""
    year = reference_date.year
    month = reference_date.month - months_back

    while month <= 0:
        month += 12
        year -= 1

    return date(year, month, 1)


def generate_id(
    prefix: str,
    number: int,
    width: int,
) -> str:
    return f"{prefix}{number:0{width}d}"


def print_summary(name: str, df: pd.DataFrame) -> None:
    print(
        f"{name:<25} "
        f"rows={len(df):>9,} | "
        f"columns={len(df.columns):>3}"
    )


# ============================================================
# Load hospitals
# ============================================================

def load_hospitals() -> pd.DataFrame:
    """
    Load official CMS hospitals.

    When organizations_amn.csv exists, only hospitals used by
    Synthea are selected. This creates overlap between the
    healthcare and workforce datasets.
    """
    require_file(CMS_FILE)

    cms = pd.read_csv(
        CMS_FILE,
        dtype=str,
        low_memory=False,
    )

    cms = normalize_headers(cms)

    hospital_id_col = find_column(
        cms,
        ["HOSPITAL_ID", "FACILITY_ID"],
    )

    hospital_name_col = find_column(
        cms,
        ["HOSPITAL_NAME", "FACILITY_NAME"],
    )

    city_col = find_column(
        cms,
        ["CITY", "CITY_TOWN"],
        required=False,
    )

    state_col = find_column(
        cms,
        ["STATE"],
    )

    type_col = find_column(
        cms,
        ["HOSPITAL_TYPE"],
        required=False,
    )

    ownership_col = find_column(
        cms,
        ["OWNERSHIP", "HOSPITAL_OWNERSHIP"],
        required=False,
    )

    selected_columns = {
        hospital_id_col: "hospital_id",
        hospital_name_col: "hospital_name",
        state_col: "state",
    }

    if city_col:
        selected_columns[city_col] = "city"

    if type_col:
        selected_columns[type_col] = "hospital_type"

    if ownership_col:
        selected_columns[ownership_col] = "ownership"

    hospitals = cms[list(selected_columns)].rename(
        columns=selected_columns
    )

    hospitals = hospitals.dropna(
        subset=["hospital_id", "hospital_name"]
    )

    hospitals = hospitals.drop_duplicates(
        subset=["hospital_id"]
    )

    for column in hospitals.columns:
        hospitals[column] = (
            hospitals[column]
            .astype("string")
            .str.strip()
        )

    # Use only hospitals already assigned to Synthea organizations.
    if SYNTHEA_ORGANIZATIONS_FILE.exists():
        synthea_orgs = pd.read_csv(
            SYNTHEA_ORGANIZATIONS_FILE,
            dtype=str,
            low_memory=False,
        )

        synthea_orgs = normalize_headers(synthea_orgs)

        synthea_hospital_col = find_column(
            synthea_orgs,
            ["HOSPITAL_ID"],
            required=False,
        )

        if synthea_hospital_col:
            used_hospital_ids = set(
                synthea_orgs[synthea_hospital_col]
                .dropna()
                .astype(str)
                .str.strip()
            )

            matching_hospitals = hospitals[
                hospitals["hospital_id"].isin(
                    used_hospital_ids
                )
            ].copy()

            if not matching_hospitals.empty:
                hospitals = matching_hospitals

                print(
                    "Using hospitals already assigned to "
                    "Synthea organizations."
                )

    if hospitals.empty:
        raise ValueError(
            "No usable hospitals were found."
        )

    print(
        f"Available hospitals for HR generation: "
        f"{len(hospitals):,}"
    )

    return hospitals.reset_index(drop=True)


# ============================================================
# Generate recruiters
# ============================================================

def generate_recruiters() -> pd.DataFrame:
    records = []

    for number in range(1, NUM_RECRUITERS + 1):
        records.append(
            {
                "recruiter_id": generate_id(
                    "REC",
                    number,
                    4,
                ),
                "recruiter_name": fake.name(),
                "email": fake.unique.company_email(),
                "phone": fake.phone_number(),
                "region": random.choice(
                    [
                        "Northeast",
                        "Midwest",
                        "South",
                        "West",
                        "National",
                    ]
                ),
                "specialization": random.choice(
                    [
                        "Nursing",
                        "Physicians",
                        "Allied Health",
                        "Travel Staffing",
                        "Permanent Placement",
                    ]
                ),
                "hire_date": fake.date_between(
                    start_date="-8y",
                    end_date="-3m",
                ).isoformat(),
                "employment_status": random.choices(
                    ["Active", "On Leave"],
                    weights=[95, 5],
                    k=1,
                )[0],
            }
        )

    return pd.DataFrame(records)


# ============================================================
# Generate staffing requests
# ============================================================

def generate_staffing_requests(
    hospitals: pd.DataFrame,
) -> pd.DataFrame:

    records = []
    today = date.today()

    hospital_records = hospitals.to_dict("records")

    for number in range(
        1,
        NUM_STAFFING_REQUESTS + 1,
    ):
        hospital = random.choice(hospital_records)
        role = random.choice(HEALTHCARE_ROLES)

        request_date = random_date_between(
            today - timedelta(days=365),
            today,
        )

        assignment_start = request_date + timedelta(
            days=random.randint(7, 45)
        )

        duration_weeks = random.choice(
            [4, 8, 12, 13, 16, 26]
        )

        assignment_end = assignment_start + timedelta(
            weeks=duration_weeks
        )

        required_staff = random.randint(1, 15)
        filled_staff = random.randint(0, required_staff)

        if filled_staff == 0:
            request_status = "Open"
        elif filled_staff < required_staff:
            request_status = "Partially Filled"
        else:
            request_status = "Filled"

        records.append(
            {
                "request_id": generate_id(
                    "REQ",
                    number,
                    6,
                ),
                "hospital_id": hospital["hospital_id"],
                "hospital_name": hospital["hospital_name"],
                "city": hospital.get("city"),
                "state": hospital["state"],
                "required_role": role["role"],
                "department": role["department"],
                "employment_type": random.choice(
                    EMPLOYMENT_TYPES
                ),
                "shift_preference": random.choice(
                    [shift[0] for shift in SHIFT_TYPES]
                ),
                "required_staff": required_staff,
                "filled_staff": filled_staff,
                "open_positions": (
                    required_staff - filled_staff
                ),
                "priority": random.choices(
                    REQUEST_PRIORITIES,
                    weights=[10, 45, 35, 10],
                    k=1,
                )[0],
                "request_status": request_status,
                "request_date": request_date.isoformat(),
                "assignment_start_date": (
                    assignment_start.isoformat()
                ),
                "assignment_end_date": (
                    assignment_end.isoformat()
                ),
                "duration_weeks": duration_weeks,
                "hourly_bill_rate": round(
                    random.uniform(
                        role["hourly_rate_max"] + 20,
                        role["hourly_rate_max"] + 90,
                    ),
                    2,
                ),
            }
        )

    return pd.DataFrame(records)


# ============================================================
# Generate candidates
# ============================================================

def generate_candidates(
    recruiters: pd.DataFrame,
    staffing_requests: pd.DataFrame,
) -> pd.DataFrame:

    records = []

    recruiter_records = recruiters.to_dict("records")
    request_records = staffing_requests.to_dict("records")

    # Ensure enough hired candidates to create all employees.
    hired_candidate_positions = set(
        random.sample(
            range(NUM_CANDIDATES),
            NUM_EMPLOYEES,
        )
    )

    for index in range(NUM_CANDIDATES):
        number = index + 1
        recruiter = random.choice(recruiter_records)
        request = random.choice(request_records)

        if index in hired_candidate_positions:
            candidate_status = "Hired"
        else:
            candidate_status = random.choices(
                [
                    "Applied",
                    "Screening",
                    "Interview",
                    "Credential Review",
                    "Offer",
                    "Rejected",
                    "Withdrawn",
                ],
                weights=[22, 18, 17, 13, 7, 18, 5],
                k=1,
            )[0]

        application_date = fake.date_between(
            start_date="-18m",
            end_date="today",
        )

        experience_years = random.randint(1, 25)

        certification_count = random.randint(1, 3)

        records.append(
            {
                "candidate_id": generate_id(
                    "CAN",
                    number,
                    6,
                ),
                "request_id": request["request_id"],
                "hospital_id": request["hospital_id"],
                "hospital_name": request["hospital_name"],
                "recruiter_id": recruiter["recruiter_id"],
                "candidate_name": fake.name(),
                "email": fake.unique.email(),
                "phone": fake.phone_number(),
                "profession": request["required_role"],
                "department": request["department"],
                "experience_years": experience_years,
                "license_state": request["state"],
                "license_status": random.choices(
                    ["Active", "Pending", "Expired"],
                    weights=[88, 9, 3],
                    k=1,
                )[0],
                "certifications": "|".join(
                    random.sample(
                        CERTIFICATIONS,
                        k=certification_count,
                    )
                ),
                "source_channel": random.choice(
                    SOURCE_CHANNELS
                ),
                "application_date": (
                    application_date.isoformat()
                ),
                "candidate_status": candidate_status,
                "background_check_status": (
                    "Completed"
                    if candidate_status == "Hired"
                    else random.choice(
                        [
                            "Not Started",
                            "In Progress",
                            "Completed",
                        ]
                    )
                ),
                "credential_status": (
                    "Verified"
                    if candidate_status == "Hired"
                    else random.choice(
                        [
                            "Pending",
                            "Under Review",
                            "Verified",
                        ]
                    )
                ),
                "employee_id": pd.NA,
            }
        )

    return pd.DataFrame(records)


# ============================================================
# Generate employees from hired candidates
# ============================================================

def generate_employees(
    candidates: pd.DataFrame,
    staffing_requests: pd.DataFrame,
) -> tuple[pd.DataFrame, pd.DataFrame]:

    hired_candidates = candidates[
        candidates["candidate_status"] == "Hired"
    ].head(NUM_EMPLOYEES).copy()

    if len(hired_candidates) < NUM_EMPLOYEES:
        raise ValueError(
            "There are not enough hired candidates "
            "to generate the requested employees."
        )

    requests_lookup = staffing_requests.set_index(
        "request_id"
    ).to_dict("index")

    employee_records = []

    for number, candidate in enumerate(
        hired_candidates.to_dict("records"),
        start=1,
    ):
        employee_id = generate_id(
            "EMP",
            number,
            6,
        )

        request = requests_lookup[
            candidate["request_id"]
        ]

        role_details = next(
            role
            for role in HEALTHCARE_ROLES
            if role["role"] == candidate["profession"]
        )

        assignment_start = datetime.strptime(
            request["assignment_start_date"],
            "%Y-%m-%d",
        ).date()

        assignment_end = datetime.strptime(
            request["assignment_end_date"],
            "%Y-%m-%d",
        ).date()

        hourly_rate = round(
            random.uniform(
                role_details["hourly_rate_min"],
                role_details["hourly_rate_max"],
            ),
            2,
        )

        employee_records.append(
            {
                "employee_id": employee_id,
                "candidate_id": candidate["candidate_id"],
                "request_id": candidate["request_id"],
                "hospital_id": candidate["hospital_id"],
                "hospital_name": candidate["hospital_name"],
                "employee_name": candidate["candidate_name"],
                "email": candidate["email"],
                "phone": candidate["phone"],
                "role": candidate["profession"],
                "department": candidate["department"],
                "employment_type": request[
                    "employment_type"
                ],
                "license_state": candidate["license_state"],
                "license_status": candidate["license_status"],
                "hire_date": candidate["application_date"],
                "assignment_start_date": (
                    assignment_start.isoformat()
                ),
                "assignment_end_date": (
                    assignment_end.isoformat()
                ),
                "hourly_pay_rate": hourly_rate,
                "employment_status": random.choices(
                    [
                        "Active",
                        "Assignment Completed",
                        "On Leave",
                    ],
                    weights=[82, 15, 3],
                    k=1,
                )[0],
            }
        )

        candidates.loc[
            candidates["candidate_id"]
            == candidate["candidate_id"],
            "employee_id",
        ] = employee_id

    return pd.DataFrame(employee_records), candidates


# ============================================================
# Generate schedules
# ============================================================

def generate_schedules(
    employees: pd.DataFrame,
) -> pd.DataFrame:

    records = []
    employee_records = employees.to_dict("records")

    for number in range(1, NUM_SCHEDULES + 1):
        employee = random.choice(employee_records)

        assignment_start = datetime.strptime(
            employee["assignment_start_date"],
            "%Y-%m-%d",
        ).date()

        assignment_end = datetime.strptime(
            employee["assignment_end_date"],
            "%Y-%m-%d",
        ).date()

        work_date = random_date_between(
            assignment_start,
            assignment_end,
        )

        shift_name, start_time, end_time, planned_hours = (
            random.choice(SHIFT_TYPES)
        )

        worked_hours = max(
            0,
            round(
                planned_hours
                + random.choice(
                    [-1, 0, 0, 0, 1, 2]
                ),
                2,
            ),
        )

        overtime_hours = max(
            0,
            worked_hours - 8,
        )

        records.append(
            {
                "schedule_id": generate_id(
                    "SCH",
                    number,
                    8,
                ),
                "employee_id": employee["employee_id"],
                "request_id": employee["request_id"],
                "hospital_id": employee["hospital_id"],
                "hospital_name": employee["hospital_name"],
                "work_date": work_date.isoformat(),
                "shift_type": shift_name,
                "shift_start_time": start_time,
                "shift_end_time": end_time,
                "planned_hours": planned_hours,
                "worked_hours": worked_hours,
                "overtime_hours": overtime_hours,
                "schedule_status": random.choices(
                    [
                        "Completed",
                        "Scheduled",
                        "Cancelled",
                        "No Show",
                    ],
                    weights=[72, 20, 6, 2],
                    k=1,
                )[0],
            }
        )

    return pd.DataFrame(records)


# ============================================================
# Generate payroll
# ============================================================

def generate_payroll(
    employees: pd.DataFrame,
) -> pd.DataFrame:

    records = []
    today = date.today()
    payroll_number = 1

    for employee in employees.to_dict("records"):
        hourly_rate = float(
            employee["hourly_pay_rate"]
        )

        for months_back in range(PAYROLL_MONTHS):
            payroll_month = month_start(
                today,
                months_back,
            )

            regular_hours = random.randint(120, 176)
            overtime_hours = random.randint(0, 36)

            regular_pay = round(
                regular_hours * hourly_rate,
                2,
            )

            overtime_pay = round(
                overtime_hours * hourly_rate * 1.5,
                2,
            )

            bonus = round(
                random.choices(
                    [0, random.uniform(250, 2_500)],
                    weights=[75, 25],
                    k=1,
                )[0],
                2,
            )

            gross_pay = round(
                regular_pay + overtime_pay + bonus,
                2,
            )

            tax_amount = round(
                gross_pay
                * random.uniform(0.16, 0.25),
                2,
            )

            benefits_deduction = round(
                random.uniform(120, 450),
                2,
            )

            net_pay = round(
                gross_pay
                - tax_amount
                - benefits_deduction,
                2,
            )

            records.append(
                {
                    "payroll_id": generate_id(
                        "PAY",
                        payroll_number,
                        8,
                    ),
                    "employee_id": employee["employee_id"],
                    "hospital_id": employee["hospital_id"],
                    "hospital_name": employee["hospital_name"],
                    "payroll_month": (
                        payroll_month.strftime("%Y-%m")
                    ),
                    "regular_hours": regular_hours,
                    "overtime_hours": overtime_hours,
                    "hourly_pay_rate": hourly_rate,
                    "regular_pay": regular_pay,
                    "overtime_pay": overtime_pay,
                    "bonus": bonus,
                    "gross_pay": gross_pay,
                    "tax_amount": tax_amount,
                    "benefits_deduction": (
                        benefits_deduction
                    ),
                    "net_pay": net_pay,
                    "payment_status": random.choices(
                        ["Paid", "Processing", "On Hold"],
                        weights=[94, 5, 1],
                        k=1,
                    )[0],
                }
            )

            payroll_number += 1

    return pd.DataFrame(records)


# ============================================================
# Validation
# ============================================================

def validate_data(
    recruiters: pd.DataFrame,
    staffing_requests: pd.DataFrame,
    candidates: pd.DataFrame,
    employees: pd.DataFrame,
    schedules: pd.DataFrame,
    payroll: pd.DataFrame,
    hospitals: pd.DataFrame,
) -> None:

    print("\nValidating generated relationships...\n")

    valid_hospital_ids = set(
        hospitals["hospital_id"]
    )

    valid_recruiter_ids = set(
        recruiters["recruiter_id"]
    )

    valid_request_ids = set(
        staffing_requests["request_id"]
    )

    valid_candidate_ids = set(
        candidates["candidate_id"]
    )

    valid_employee_ids = set(
        employees["employee_id"]
    )

    validations = [
        (
            "Recruiter IDs are unique",
            not recruiters["recruiter_id"]
            .duplicated()
            .any(),
        ),
        (
            "Staffing request IDs are unique",
            not staffing_requests["request_id"]
            .duplicated()
            .any(),
        ),
        (
            "Candidate IDs are unique",
            not candidates["candidate_id"]
            .duplicated()
            .any(),
        ),
        (
            "Employee IDs are unique",
            not employees["employee_id"]
            .duplicated()
            .any(),
        ),
        (
            "Schedule IDs are unique",
            not schedules["schedule_id"]
            .duplicated()
            .any(),
        ),
        (
            "Payroll IDs are unique",
            not payroll["payroll_id"]
            .duplicated()
            .any(),
        ),
        (
            "Staffing request hospitals are valid",
            staffing_requests["hospital_id"]
            .isin(valid_hospital_ids)
            .all(),
        ),
        (
            "Candidate recruiters are valid",
            candidates["recruiter_id"]
            .isin(valid_recruiter_ids)
            .all(),
        ),
        (
            "Candidate requests are valid",
            candidates["request_id"]
            .isin(valid_request_ids)
            .all(),
        ),
        (
            "Employee candidates are valid",
            employees["candidate_id"]
            .isin(valid_candidate_ids)
            .all(),
        ),
        (
            "Employee requests are valid",
            employees["request_id"]
            .isin(valid_request_ids)
            .all(),
        ),
        (
            "Employee hospitals are valid",
            employees["hospital_id"]
            .isin(valid_hospital_ids)
            .all(),
        ),
        (
            "Schedule employees are valid",
            schedules["employee_id"]
            .isin(valid_employee_ids)
            .all(),
        ),
        (
            "Payroll employees are valid",
            payroll["employee_id"]
            .isin(valid_employee_ids)
            .all(),
        ),
    ]

    failed = []

    for validation_name, passed in validations:
        status = "PASS" if passed else "FAIL"
        print(f"[{status}] {validation_name}")

        if not passed:
            failed.append(validation_name)

    if failed:
        raise ValueError(
            "One or more relationship validations failed."
        )

    print("\nAll HR relationship checks passed.")


# ============================================================
# Save outputs
# ============================================================

def save_outputs(
    recruiters: pd.DataFrame,
    staffing_requests: pd.DataFrame,
    candidates: pd.DataFrame,
    employees: pd.DataFrame,
    schedules: pd.DataFrame,
    payroll: pd.DataFrame,
) -> None:

    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    recruiters.to_csv(
        OUTPUT_DIR / "recruiters.csv",
        index=False,
    )

    staffing_requests.to_csv(
        OUTPUT_DIR / "staffing_requests.csv",
        index=False,
    )

    candidates.to_csv(
        OUTPUT_DIR / "candidates.csv",
        index=False,
    )

    employees.to_csv(
        OUTPUT_DIR / "employees.csv",
        index=False,
    )

    schedules.to_csv(
        OUTPUT_DIR / "schedules.csv",
        index=False,
    )

    payroll.to_csv(
        OUTPUT_DIR / "payroll.csv",
        index=False,
    )


# ============================================================
# Main
# ============================================================

def main() -> None:
    try:
        print("=" * 72)
        print("Generating AMN Healthcare workforce data")
        print("=" * 72)

        hospitals = load_hospitals()

        print("\nGenerating recruiters...")
        recruiters = generate_recruiters()

        print("Generating hospital staffing requests...")
        staffing_requests = (
            generate_staffing_requests(hospitals)
        )

        print("Generating healthcare candidates...")
        candidates = generate_candidates(
            recruiters,
            staffing_requests,
        )

        print("Creating employees from hired candidates...")
        employees, candidates = generate_employees(
            candidates,
            staffing_requests,
        )

        print("Generating employee schedules...")
        schedules = generate_schedules(employees)

        print("Generating payroll records...")
        payroll = generate_payroll(employees)

        validate_data(
            recruiters=recruiters,
            staffing_requests=staffing_requests,
            candidates=candidates,
            employees=employees,
            schedules=schedules,
            payroll=payroll,
            hospitals=hospitals,
        )

        save_outputs(
            recruiters=recruiters,
            staffing_requests=staffing_requests,
            candidates=candidates,
            employees=employees,
            schedules=schedules,
            payroll=payroll,
        )

        print("\nGenerated dataset summary:\n")

        print_summary("recruiters", recruiters)
        print_summary(
            "staffing_requests",
            staffing_requests,
        )
        print_summary("candidates", candidates)
        print_summary("employees", employees)
        print_summary("schedules", schedules)
        print_summary("payroll", payroll)

        print("\nFiles saved successfully:")
        print(f"  {OUTPUT_DIR}")

        print("\nHR data generation completed successfully.")

    except (
        FileNotFoundError,
        KeyError,
        ValueError,
        pd.errors.ParserError,
    ) as error:
        print(
            f"\nERROR: {error}",
            file=sys.stderr,
        )
        sys.exit(1)

    except Exception as error:
        print(
            f"\nUnexpected error: "
            f"{type(error).__name__}: {error}",
            file=sys.stderr,
        )
        sys.exit(1)


if __name__ == "__main__":
    main()