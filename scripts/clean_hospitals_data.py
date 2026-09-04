import pandas as pd
import os

# =====================================================
# Configuration
# =====================================================

INPUT_FILE = "../datasets/cms/hospitals_reference_raw.csv"
OUTPUT_FILE = "../datasets/cms/hospitals_reference.csv"

# =====================================================
# Read CSV
# =====================================================

print("Reading hospital dataset...")

df = pd.read_csv(INPUT_FILE)

print(f"Total Records : {len(df)}")
print(f"Total Columns : {len(df.columns)}")

# =====================================================
# Show Available Columns
# =====================================================

print("\nColumns Found:")
print(df.columns.tolist())

# =====================================================
# Rename Columns
# NOTE:
# Update these names if your downloaded CSV
# uses slightly different column names.
# =====================================================

rename_columns = {

    "Facility ID": "hospital_id",

    "Facility Name": "hospital_name",

    "City/Town": "city",

    "State": "state",

    "Hospital Type": "hospital_type",

    "Hospital Ownership": "ownership",

    "Emergency Services": "emergency_services",

    "Hospital overall rating": "hospital_rating"

}

df.rename(columns=rename_columns, inplace=True)

# =====================================================
# Keep Only Required Columns
# =====================================================

required_columns = [

    "hospital_id",

    "hospital_name",

    "city",

    "state",

    "hospital_type",

    "ownership",

    "emergency_services",

    "hospital_rating"

]

existing_columns = [c for c in required_columns if c in df.columns]

df = df[existing_columns]

# =====================================================
# Remove Duplicate Hospitals
# =====================================================

df.drop_duplicates(
    subset="hospital_id",
    inplace=True
)

# =====================================================
# Fill Missing Values
# =====================================================

df.fillna({

    "hospital_rating": "Not Available",

    "ownership": "Unknown",

    "hospital_type": "Unknown",

    "emergency_services": "Unknown"

}, inplace=True)

# =====================================================
# Remove Extra Spaces
# =====================================================

for col in df.select_dtypes(include="object").columns:
    df[col] = df[col].str.strip()

# =====================================================
# Sort
# =====================================================

df.sort_values(
    by="hospital_name",
    inplace=True
)

# =====================================================
# Save
# =====================================================

os.makedirs("../datasets/cms", exist_ok=True)

df.to_csv(
    OUTPUT_FILE,
    index=False
)

# =====================================================
# Summary
# =====================================================

print("\nCleaning Complete!")

print(f"Final Records : {len(df)}")

print(f"Final Columns : {len(df.columns)}")

print(f"Saved To : {OUTPUT_FILE}")