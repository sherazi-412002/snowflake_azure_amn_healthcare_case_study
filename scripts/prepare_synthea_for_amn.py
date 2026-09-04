from __future__ import annotations

import sys
from pathlib import Path
from typing import Iterable

import pandas as pd


# ============================================================
# Project paths
# ============================================================

PROJECT_ROOT = Path(__file__).resolve().parent.parent

SYNTHEA_DIR = PROJECT_ROOT / "datasets" / "synthea"
CMS_FILE = PROJECT_ROOT / "datasets" / "cms" / "hospitals_reference.csv"

OUTPUT_DIR = PROJECT_ROOT / "datasets" / "processed" / "synthea"
MAPPING_DIR = OUTPUT_DIR / "mappings"


# ============================================================
# Input files
# ============================================================

ORGANIZATIONS_FILE = SYNTHEA_DIR / "organizations.csv"
PROVIDERS_FILE = SYNTHEA_DIR / "providers.csv"
PATIENTS_FILE = SYNTHEA_DIR / "patients.csv"
ENCOUNTERS_FILE = SYNTHEA_DIR / "encounters.csv"
CLAIMS_FILE = SYNTHEA_DIR / "claims.csv"


# ============================================================
# Helper functions
# ============================================================

def require_file(path: Path) -> None:
    """Raise an error when a required input file is missing."""
    if not path.exists():
        raise FileNotFoundError(f"Required file not found: {path}")


def normalize_headers(df: pd.DataFrame) -> pd.DataFrame:
    """
    Convert column names to uppercase snake case.

    Examples:
        Facility ID -> FACILITY_ID
        Hospital overall rating -> HOSPITAL_OVERALL_RATING
        City/Town -> CITY_TOWN
    """
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


def clean_string_columns(df: pd.DataFrame) -> pd.DataFrame:
    """Trim extra spaces from text columns."""
    df = df.copy()

    for column in df.select_dtypes(include=["object", "string"]).columns:
        df[column] = df[column].astype("string").str.strip()

    return df


def find_column(
    df: pd.DataFrame,
    candidates: Iterable[str],
    required: bool = True,
) -> str | None:
    """
    Find the first matching column from a list of possible names.
    """
    available_columns = set(df.columns)

    for candidate in candidates:
        normalized = (
            candidate.strip()
            .upper()
            .replace("/", "_")
            .replace("-", "_")
            .replace(" ", "_")
        )

        if normalized in available_columns:
            return normalized

    if required:
        raise KeyError(
            f"Required column not found.\n"
            f"Expected one of: {list(candidates)}\n"
            f"Available columns: {df.columns.tolist()}"
        )

    return None


def create_id_mapping(
    source_ids: pd.Series,
    prefix: str,
    width: int,
    source_column: str,
    target_column: str,
) -> pd.DataFrame:
    """
    Create readable IDs.

    Examples:
        UUID -> ORG0001
        UUID -> PAT000001
        UUID -> ENC00000001
    """
    unique_ids = (
        source_ids.astype("string")
        .dropna()
        .str.strip()
    )

    unique_ids = (
        unique_ids[unique_ids.ne("")]
        .drop_duplicates()
        .reset_index(drop=True)
    )

    readable_ids = [
        f"{prefix}{number:0{width}d}"
        for number in range(1, len(unique_ids) + 1)
    ]

    return pd.DataFrame(
        {
            source_column: unique_ids,
            target_column: readable_ids,
        }
    )


def replace_ids(
    series: pd.Series,
    mapping: pd.DataFrame,
    source_column: str,
    target_column: str,
) -> pd.Series:
    """Replace UUID values using a mapping DataFrame."""
    lookup = mapping.set_index(source_column)[target_column]

    return (
        series.astype("string")
        .str.strip()
        .map(lookup)
    )


def keep_existing_columns(
    df: pd.DataFrame,
    desired_columns: list[str],
    dataset_name: str,
) -> pd.DataFrame:
    """
    Keep only requested columns that are present.

    Missing optional columns are reported but do not stop execution.
    """
    existing_columns = [
        column
        for column in desired_columns
        if column in df.columns
    ]

    missing_columns = [
        column
        for column in desired_columns
        if column not in df.columns
    ]

    if missing_columns:
        print(
            f"[WARNING] {dataset_name}: skipped missing columns: "
            f"{missing_columns}"
        )

    return df[existing_columns].copy()


def print_summary(name: str, df: pd.DataFrame) -> None:
    """Print row and column counts."""
    print(
        f"{name:<24} "
        f"rows={len(df):>9,} | "
        f"columns={len(df.columns):>3}"
    )


# ============================================================
# Read input datasets
# ============================================================

def load_inputs() -> dict[str, pd.DataFrame]:
    required_files = [
        ORGANIZATIONS_FILE,
        PROVIDERS_FILE,
        PATIENTS_FILE,
        ENCOUNTERS_FILE,
        CLAIMS_FILE,
        CMS_FILE,
    ]

    for file_path in required_files:
        require_file(file_path)

    datasets = {
        "organizations": pd.read_csv(
            ORGANIZATIONS_FILE,
            dtype=str,
            low_memory=False,
        ),
        "providers": pd.read_csv(
            PROVIDERS_FILE,
            dtype=str,
            low_memory=False,
        ),
        "patients": pd.read_csv(
            PATIENTS_FILE,
            dtype=str,
            low_memory=False,
        ),
        "encounters": pd.read_csv(
            ENCOUNTERS_FILE,
            dtype=str,
            low_memory=False,
        ),
        "claims": pd.read_csv(
            CLAIMS_FILE,
            dtype=str,
            low_memory=False,
        ),
        "cms": pd.read_csv(
            CMS_FILE,
            dtype=str,
            low_memory=False,
        ),
    }

    return {
        name: clean_string_columns(normalize_headers(df))
        for name, df in datasets.items()
    }


# ============================================================
# Prepare AMN-ready data
# ============================================================

def prepare_data(
    data: dict[str, pd.DataFrame],
) -> dict[str, pd.DataFrame]:

    organizations = data["organizations"].copy()
    providers = data["providers"].copy()
    patients = data["patients"].copy()
    encounters = data["encounters"].copy()
    claims = data["claims"].copy()
    cms = data["cms"].copy()

    # ========================================================
    # Detect Synthea columns
    # ========================================================

    organization_old_id = find_column(
        organizations,
        ["ID"],
    )

    provider_old_id = find_column(
        providers,
        ["ID"],
    )

    provider_organization = find_column(
        providers,
        ["ORGANIZATION", "ORGANIZATION_ID"],
        required=False,
    )

    patient_old_id = find_column(
        patients,
        ["ID"],
    )

    encounter_old_id = find_column(
        encounters,
        ["ID"],
    )

    encounter_patient = find_column(
        encounters,
        ["PATIENT", "PATIENT_ID"],
    )

    encounter_provider = find_column(
        encounters,
        ["PROVIDER", "PROVIDER_ID"],
        required=False,
    )

    encounter_organization = find_column(
        encounters,
        ["ORGANIZATION", "ORGANIZATION_ID"],
        required=False,
    )

    claim_old_id = find_column(
        claims,
        ["ID", "CLAIM_ID", "CLAIMID"],
    )

    claim_patient = find_column(
        claims,
        ["PATIENTID", "PATIENT_ID", "PATIENT"],
        required=False,
    )

    claim_provider = find_column(
        claims,
        ["PROVIDERID", "PROVIDER_ID", "PROVIDER"],
        required=False,
    )

    claim_encounter = find_column(
        claims,
        [
            "APPOINTMENTID",
            "APPOINTMENT_ID",
            "ENCOUNTERID",
            "ENCOUNTER_ID",
            "ENCOUNTER",
        ],
        required=False,
    )

    # ========================================================
    # Detect CMS columns
    # ========================================================

    cms_hospital_id = find_column(
        cms,
        ["HOSPITAL_ID", "FACILITY_ID"],
    )

    cms_hospital_name = find_column(
        cms,
        ["HOSPITAL_NAME", "FACILITY_NAME"],
    )

    cms_city = find_column(
        cms,
        ["CITY", "CITY_TOWN"],
        required=False,
    )

    cms_state = find_column(
        cms,
        ["STATE"],
        required=False,
    )

    cms_type = find_column(
        cms,
        ["HOSPITAL_TYPE"],
        required=False,
    )

    cms_ownership = find_column(
        cms,
        ["OWNERSHIP", "HOSPITAL_OWNERSHIP"],
        required=False,
    )

    cms_emergency = find_column(
        cms,
        ["EMERGENCY_SERVICES"],
        required=False,
    )

    cms_rating = find_column(
        cms,
        [
            "HOSPITAL_RATING",
            "HOSPITAL_OVERALL_RATING",
        ],
        required=False,
    )

    # ========================================================
    # Remove duplicate primary records
    # ========================================================

    organizations = organizations.drop_duplicates(
        subset=[organization_old_id]
    ).copy()

    providers = providers.drop_duplicates(
        subset=[provider_old_id]
    ).copy()

    patients = patients.drop_duplicates(
        subset=[patient_old_id]
    ).copy()

    encounters = encounters.drop_duplicates(
        subset=[encounter_old_id]
    ).copy()

    claims = claims.drop_duplicates(
        subset=[claim_old_id]
    ).copy()

    cms = cms.drop_duplicates(
        subset=[cms_hospital_id]
    ).copy()

    cms = cms[
        cms[cms_hospital_id].notna()
        & cms[cms_hospital_name].notna()
    ].copy()

    if cms.empty:
        raise ValueError(
            "No usable hospital records were found in the CMS dataset."
        )

    # ========================================================
    # Create readable ID mappings
    # ========================================================

    organization_mapping = create_id_mapping(
        organizations[organization_old_id],
        prefix="ORG",
        width=4,
        source_column="OLD_ORGANIZATION_ID",
        target_column="ORGANIZATION_ID",
    )

    provider_mapping = create_id_mapping(
        providers[provider_old_id],
        prefix="PRV",
        width=6,
        source_column="OLD_PROVIDER_ID",
        target_column="PROVIDER_ID",
    )

    patient_mapping = create_id_mapping(
        patients[patient_old_id],
        prefix="PAT",
        width=6,
        source_column="OLD_PATIENT_ID",
        target_column="PATIENT_ID",
    )

    encounter_mapping = create_id_mapping(
        encounters[encounter_old_id],
        prefix="ENC",
        width=8,
        source_column="OLD_ENCOUNTER_ID",
        target_column="ENCOUNTER_ID",
    )

    claim_mapping = create_id_mapping(
        claims[claim_old_id],
        prefix="CLM",
        width=8,
        source_column="OLD_CLAIM_ID",
        target_column="CLAIM_ID",
    )

    # ========================================================
    # Replace primary IDs
    # ========================================================

    organizations[organization_old_id] = replace_ids(
        organizations[organization_old_id],
        organization_mapping,
        "OLD_ORGANIZATION_ID",
        "ORGANIZATION_ID",
    )

    organizations = organizations.rename(
        columns={organization_old_id: "ORGANIZATION_ID"}
    )

    providers[provider_old_id] = replace_ids(
        providers[provider_old_id],
        provider_mapping,
        "OLD_PROVIDER_ID",
        "PROVIDER_ID",
    )

    providers = providers.rename(
        columns={provider_old_id: "PROVIDER_ID"}
    )

    patients[patient_old_id] = replace_ids(
        patients[patient_old_id],
        patient_mapping,
        "OLD_PATIENT_ID",
        "PATIENT_ID",
    )

    patients = patients.rename(
        columns={patient_old_id: "PATIENT_ID"}
    )

    encounters[encounter_old_id] = replace_ids(
        encounters[encounter_old_id],
        encounter_mapping,
        "OLD_ENCOUNTER_ID",
        "ENCOUNTER_ID",
    )

    encounters = encounters.rename(
        columns={encounter_old_id: "ENCOUNTER_ID"}
    )

    claims[claim_old_id] = replace_ids(
        claims[claim_old_id],
        claim_mapping,
        "OLD_CLAIM_ID",
        "CLAIM_ID",
    )

    claims = claims.rename(
        columns={claim_old_id: "CLAIM_ID"}
    )

    # ========================================================
    # Replace provider foreign keys
    # ========================================================

    if provider_organization:
        providers[provider_organization] = replace_ids(
            providers[provider_organization],
            organization_mapping,
            "OLD_ORGANIZATION_ID",
            "ORGANIZATION_ID",
        )

        providers = providers.rename(
            columns={
                provider_organization: "ORGANIZATION_ID"
            }
        )

    # ========================================================
    # Replace encounter foreign keys
    # ========================================================

    encounters[encounter_patient] = replace_ids(
        encounters[encounter_patient],
        patient_mapping,
        "OLD_PATIENT_ID",
        "PATIENT_ID",
    )

    encounters = encounters.rename(
        columns={encounter_patient: "PATIENT_ID"}
    )

    if encounter_provider:
        encounters[encounter_provider] = replace_ids(
            encounters[encounter_provider],
            provider_mapping,
            "OLD_PROVIDER_ID",
            "PROVIDER_ID",
        )

        encounters = encounters.rename(
            columns={
                encounter_provider: "PROVIDER_ID"
            }
        )

    if encounter_organization:
        encounters[encounter_organization] = replace_ids(
            encounters[encounter_organization],
            organization_mapping,
            "OLD_ORGANIZATION_ID",
            "ORGANIZATION_ID",
        )

        encounters = encounters.rename(
            columns={
                encounter_organization: "ORGANIZATION_ID"
            }
        )

    # ========================================================
    # Replace claim foreign keys
    # ========================================================

    if claim_patient:
        claims[claim_patient] = replace_ids(
            claims[claim_patient],
            patient_mapping,
            "OLD_PATIENT_ID",
            "PATIENT_ID",
        )

        claims = claims.rename(
            columns={claim_patient: "PATIENT_ID"}
        )

    if claim_provider:
        claims[claim_provider] = replace_ids(
            claims[claim_provider],
            provider_mapping,
            "OLD_PROVIDER_ID",
            "PROVIDER_ID",
        )

        claims = claims.rename(
            columns={claim_provider: "PROVIDER_ID"}
        )

    if claim_encounter:
        claims[claim_encounter] = replace_ids(
            claims[claim_encounter],
            encounter_mapping,
            "OLD_ENCOUNTER_ID",
            "ENCOUNTER_ID",
        )

        claims = claims.rename(
            columns={claim_encounter: "ENCOUNTER_ID"}
        )

    # ========================================================
    # Assign CMS hospitals to Synthea organizations
    #
    # Priority:
    # 1. Choose a CMS hospital from the same state.
    # 2. If none exists, use another CMS hospital.
    #
    # random_state=42 keeps the assignment repeatable.
    # ========================================================

    organization_state = find_column(
        organizations,
        ["STATE"],
        required=False,
    )

    shuffled_cms = cms.sample(
        frac=1,
        random_state=42,
    ).reset_index(drop=True)

    cms_by_state: dict[str, pd.DataFrame] = {}

    if cms_state:
        for state_value, group in cms.groupby(
            cms_state,
            dropna=True,
        ):
            normalized_state = str(state_value).strip().upper()

            if normalized_state:
                cms_by_state[normalized_state] = (
                    group.reset_index(drop=True)
                )

    assigned_hospitals: list[pd.Series] = []
    state_positions: dict[str, int] = {}

    for row_number, (_, organization_row) in enumerate(
        organizations.reset_index(drop=True).iterrows()
    ):
        current_state = ""

        if organization_state:
            state_value = organization_row.get(
                organization_state
            )

            if pd.notna(state_value):
                current_state = (
                    str(state_value)
                    .strip()
                    .upper()
                )

        matching_hospitals = cms_by_state.get(
            current_state
        )

        if (
            matching_hospitals is not None
            and not matching_hospitals.empty
        ):
            position = state_positions.get(
                current_state,
                0,
            )

            selected_hospital = matching_hospitals.iloc[
                position % len(matching_hospitals)
            ]

            state_positions[current_state] = position + 1

        else:
            selected_hospital = shuffled_cms.iloc[
                row_number % len(shuffled_cms)
            ]

        assigned_hospitals.append(selected_hospital)

    assigned_cms = pd.DataFrame(
        assigned_hospitals
    ).reset_index(drop=True)

    organizations = organizations.reset_index(drop=True)

    organizations["HOSPITAL_ID"] = assigned_cms[
        cms_hospital_id
    ].astype("string")

    organizations["HOSPITAL_NAME"] = assigned_cms[
        cms_hospital_name
    ].astype("string")

    if cms_city:
        organizations["CMS_CITY"] = assigned_cms[
            cms_city
        ].astype("string")

    if cms_state:
        organizations["CMS_STATE"] = assigned_cms[
            cms_state
        ].astype("string")

    if cms_type:
        organizations["HOSPITAL_TYPE"] = assigned_cms[
            cms_type
        ].astype("string")

    if cms_ownership:
        organizations["OWNERSHIP"] = assigned_cms[
            cms_ownership
        ].astype("string")

    if cms_emergency:
        organizations["EMERGENCY_SERVICES"] = assigned_cms[
            cms_emergency
        ].astype("string")

    if cms_rating:
        organizations["HOSPITAL_RATING"] = assigned_cms[
            cms_rating
        ].astype("string")

    # ========================================================
    # Build organization-to-hospital mapping
    # ========================================================

    mapping_columns = [
        "ORGANIZATION_ID",
        "HOSPITAL_ID",
        "HOSPITAL_NAME",
    ]

    for optional_column in [
        "CMS_CITY",
        "CMS_STATE",
        "HOSPITAL_TYPE",
        "OWNERSHIP",
        "EMERGENCY_SERVICES",
        "HOSPITAL_RATING",
    ]:
        if optional_column in organizations.columns:
            mapping_columns.append(optional_column)

    organization_hospital_mapping = organizations[
        mapping_columns
    ].copy()

    # ========================================================
    # Add hospital information to providers
    # ========================================================

    if "ORGANIZATION_ID" in providers.columns:
        providers = providers.merge(
            organization_hospital_mapping[
                [
                    "ORGANIZATION_ID",
                    "HOSPITAL_ID",
                    "HOSPITAL_NAME",
                ]
            ],
            on="ORGANIZATION_ID",
            how="left",
        )

    # ========================================================
    # Add hospital information to encounters
    # ========================================================

    if "ORGANIZATION_ID" in encounters.columns:
        encounters = encounters.merge(
            organization_hospital_mapping[
                [
                    "ORGANIZATION_ID",
                    "HOSPITAL_ID",
                    "HOSPITAL_NAME",
                ]
            ],
            on="ORGANIZATION_ID",
            how="left",
        )

    # ========================================================
    # Add organization and hospital to claims through provider
    # ========================================================

    if (
        "PROVIDER_ID" in claims.columns
        and "PROVIDER_ID" in providers.columns
    ):
        provider_hospital_mapping = providers[
            [
                "PROVIDER_ID",
                "ORGANIZATION_ID",
                "HOSPITAL_ID",
                "HOSPITAL_NAME",
            ]
        ].drop_duplicates(subset=["PROVIDER_ID"])

        claims = claims.merge(
            provider_hospital_mapping,
            on="PROVIDER_ID",
            how="left",
        )

    # ========================================================
    # Keep only AMN-relevant columns
    # ========================================================

    organizations = keep_existing_columns(
        organizations,
        [
            "ORGANIZATION_ID",
            "HOSPITAL_ID",
            "HOSPITAL_NAME",
            "CMS_CITY",
            "CMS_STATE",
            "HOSPITAL_TYPE",
            "OWNERSHIP",
            "EMERGENCY_SERVICES",
            "HOSPITAL_RATING",
        ],
        "organizations",
    )

    providers = keep_existing_columns(
        providers,
        [
            "PROVIDER_ID",
            "ORGANIZATION_ID",
            "HOSPITAL_ID",
            "HOSPITAL_NAME",
            "NAME",
            "SPECIALITY",
            "GENDER",
        ],
        "providers",
    )

    patients = keep_existing_columns(
        patients,
        [
            "PATIENT_ID",
            "BIRTHDATE",
            "DEATHDATE",
            "GENDER",
            "RACE",
            "ETHNICITY",
            "CITY",
            "STATE",
        ],
        "patients",
    )

    encounters = keep_existing_columns(
        encounters,
        [
            "ENCOUNTER_ID",
            "PATIENT_ID",
            "PROVIDER_ID",
            "ORGANIZATION_ID",
            "HOSPITAL_ID",
            "HOSPITAL_NAME",
            "START",
            "STOP",
            "ENCOUNTERCLASS",
            "CODE",
            "DESCRIPTION",
            "BASE_ENCOUNTER_COST",
            "TOTAL_CLAIM_COST",
            "PAYER_COVERAGE",
            "REASONCODE",
            "REASONDESCRIPTION",
        ],
        "encounters",
    )

    claims = keep_existing_columns(
        claims,
        [
            "CLAIM_ID",
            "PATIENT_ID",
            "PROVIDER_ID",
            "ENCOUNTER_ID",
            "ORGANIZATION_ID",
            "HOSPITAL_ID",
            "HOSPITAL_NAME",
            "SERVICEDATE",
            "BILLABLEPERIODSTART",
            "BILLABLEPERIODEND",
            "DIAGNOSIS1",
            "DIAGNOSIS2",
            "TOTAL_CLAIM_COST",
            "AMOUNT_COVERED",
            "AMOUNT_OWED",
            "PRIMARYPATIENTINSURANCEID",
            "SECONDARYPATIENTINSURANCEID",
        ],
        "claims",
    )

    return {
        "organizations": organizations,
        "providers": providers,
        "patients": patients,
        "encounters": encounters,
        "claims": claims,
        "organization_mapping": organization_mapping,
        "provider_mapping": provider_mapping,
        "patient_mapping": patient_mapping,
        "encounter_mapping": encounter_mapping,
        "claim_mapping": claim_mapping,
        "organization_hospital_mapping": (
            organization_hospital_mapping
        ),
    }


# ============================================================
# Validation
# ============================================================

def validate_outputs(
    prepared: dict[str, pd.DataFrame],
) -> None:

    print("\nValidating AMN-ready datasets...\n")

    organizations = prepared["organizations"]
    providers = prepared["providers"]
    patients = prepared["patients"]
    encounters = prepared["encounters"]
    claims = prepared["claims"]

    validations: list[tuple[str, bool]] = [
        (
            "Organization IDs are unique",
            not organizations[
                "ORGANIZATION_ID"
            ].duplicated().any(),
        ),
        (
            "Provider IDs are unique",
            not providers[
                "PROVIDER_ID"
            ].duplicated().any(),
        ),
        (
            "Patient IDs are unique",
            not patients[
                "PATIENT_ID"
            ].duplicated().any(),
        ),
        (
            "Encounter IDs are unique",
            not encounters[
                "ENCOUNTER_ID"
            ].duplicated().any(),
        ),
        (
            "Claim IDs are unique",
            not claims[
                "CLAIM_ID"
            ].duplicated().any(),
        ),
        (
            "Every organization has a CMS hospital ID",
            organizations[
                "HOSPITAL_ID"
            ].notna().all(),
        ),
    ]

    valid_organization_ids = set(
        organizations["ORGANIZATION_ID"].dropna()
    )

    if "ORGANIZATION_ID" in providers.columns:
        validations.append(
            (
                "Provider organization references are valid",
                providers["ORGANIZATION_ID"]
                .dropna()
                .isin(valid_organization_ids)
                .all(),
            )
        )

    valid_patient_ids = set(
        patients["PATIENT_ID"].dropna()
    )

    if "PATIENT_ID" in encounters.columns:
        validations.append(
            (
                "Encounter patient references are valid",
                encounters["PATIENT_ID"]
                .dropna()
                .isin(valid_patient_ids)
                .all(),
            )
        )

    valid_provider_ids = set(
        providers["PROVIDER_ID"].dropna()
    )

    if "PROVIDER_ID" in encounters.columns:
        validations.append(
            (
                "Encounter provider references are valid",
                encounters["PROVIDER_ID"]
                .dropna()
                .isin(valid_provider_ids)
                .all(),
            )
        )

    if "PATIENT_ID" in claims.columns:
        validations.append(
            (
                "Claim patient references are valid",
                claims["PATIENT_ID"]
                .dropna()
                .isin(valid_patient_ids)
                .all(),
            )
        )

    failed_validations: list[str] = []

    for validation_name, passed in validations:
        status = "PASS" if passed else "FAIL"
        print(f"[{status}] {validation_name}")

        if not passed:
            failed_validations.append(validation_name)

    if failed_validations:
        print(
            "\nWarning: some validation checks failed."
        )
    else:
        print("\nAll major relationship checks passed.")


# ============================================================
# Save outputs
# ============================================================

def save_outputs(
    prepared: dict[str, pd.DataFrame],
) -> None:

    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    MAPPING_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    prepared["organizations"].to_csv(
        OUTPUT_DIR / "organizations_amn.csv",
        index=False,
    )

    prepared["providers"].to_csv(
        OUTPUT_DIR / "providers_amn.csv",
        index=False,
    )

    prepared["patients"].to_csv(
        OUTPUT_DIR / "patients_amn.csv",
        index=False,
    )

    prepared["encounters"].to_csv(
        OUTPUT_DIR / "encounters_amn.csv",
        index=False,
    )

    prepared["claims"].to_csv(
        OUTPUT_DIR / "claims_amn.csv",
        index=False,
    )

    # Separate technical mapping files.
    # These are useful for debugging but are not loaded as business data.

    prepared["organization_mapping"].to_csv(
        MAPPING_DIR / "organization_id_mapping.csv",
        index=False,
    )

    prepared["provider_mapping"].to_csv(
        MAPPING_DIR / "provider_id_mapping.csv",
        index=False,
    )

    prepared["patient_mapping"].to_csv(
        MAPPING_DIR / "patient_id_mapping.csv",
        index=False,
    )

    prepared["encounter_mapping"].to_csv(
        MAPPING_DIR / "encounter_id_mapping.csv",
        index=False,
    )

    prepared["claim_mapping"].to_csv(
        MAPPING_DIR / "claim_id_mapping.csv",
        index=False,
    )

    prepared["organization_hospital_mapping"].to_csv(
        MAPPING_DIR / "organization_hospital_mapping.csv",
        index=False,
    )


# ============================================================
# Main
# ============================================================

def main() -> None:
    try:
        print("=" * 72)
        print("Preparing Synthea data for the AMN Healthcare project")
        print("=" * 72)

        source_data = load_inputs()

        print("\nSource dataset summary:\n")

        for name, dataframe in source_data.items():
            print_summary(name, dataframe)

        prepared_data = prepare_data(source_data)

        validate_outputs(prepared_data)
        save_outputs(prepared_data)

        print("\nFinal AMN-ready dataset summary:\n")

        for name in [
            "organizations",
            "providers",
            "patients",
            "encounters",
            "claims",
        ]:
            print_summary(
                name,
                prepared_data[name],
            )

        print("\nFiles saved successfully:")
        print(f"AMN datasets : {OUTPUT_DIR}")
        print(f"ID mappings  : {MAPPING_DIR}")

        print("\nPreparation completed successfully.")

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