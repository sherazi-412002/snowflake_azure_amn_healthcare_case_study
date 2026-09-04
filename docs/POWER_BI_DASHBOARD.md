# AMN Power BI Dashboard

## Connection

- Server: `PMNFHRD-OP32945.snowflakecomputing.com`
- Warehouse: `AMN_BI_WH`
- Database: `AMN_DEV`
- Role: `AMN_BI_ROLE`
- Schema: `MARTS`
- Mode: DirectQuery for the five-minute end-to-end freshness target

Power BI must not connect to `RAW` or `CURATED`.

## Model

Load these views:

- `DIM_DATE`
- `DIM_HOSPITAL`
- `DIM_CANDIDATE`
- `FACT_STAFFING_REQUEST`
- `FACT_PLACEMENT_SCHEDULE`
- `FACT_PAYROLL`
- `VW_RECRUITING_FUNNEL`
- `VW_EXECUTIVE_KPIS`
- `VW_PIPELINE_RUNS`
- `VW_PIPELINE_LATEST_STATUS`

Use one-to-many, single-direction relationships from dimensions to facts. Keep operational views on a separate report page and do not relate run IDs to business facts.

## Pages

1. Executive Staffing Overview: open requests, fill rate, average time to fill, active placements, open positions, hospital/state/role trends.
2. Recruiting & Candidates: candidate funnel, profession, location, source channel, recruiter, credentials, and background checks.
3. Scheduling & Payroll: planned/worked/overtime hours, gross/net payroll, overtime cost, hospital and monthly trends.
4. Pipeline Operations: latest load, success rate, duration, SLA, throughput, rejected rows, and errors.

## Required slicers

- Date
- Hospital
- State
- Required role / profession
- Department
- Recruiter
- Request status

## Visual design

- Dark navy header, medium blue navigation, teal highlights, white cards.
- Green for healthy/SLA met, amber for warning, red for failure/breach.
- Keep no more than six KPI cards on a page.
- Show the data-as-of timestamp and current filter context on every page.

## SLA

The published ingestion run currently completes in approximately 2 minutes 48 seconds. DirectQuery keeps report queries within the remaining dashboard-update window. Measure end-to-end freshness from ADF start until the refreshed visual returns the latest `CURATED_AT` timestamp.
