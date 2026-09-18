# Power BI DirectQuery Dashboard

## Semantic Model Topology
The reporting semantic model connects directly to Snowflake's `AMN_DEV.MARTS` schema using the **DirectQuery** engine via `AMN_BI_WH`.

```
                      +-------------------+
                      |   DIM_HOSPITAL    |
                      +-------------------+
                         | 1         | 1
                         |           +-----------------------+
                         | *                                 | *
             +-----------------------+           +-----------------------+
             | FACT_STAFFING_REQUEST |           | FACT_PLACEMENT_SCHED  |
             +-----------------------+           +-----------------------+
                         | *                                 | *
                         |                                   |
                         | 1                                 | 1
                      +-------------------+                  |
                      |     DIM_DATE      |------------------+
                      +-------------------+                  |
                         | 1                                 |
                         |                                   |
                         | *                                 | *
             +-----------------------+           +-----------------------+
             |     DIM_CANDIDATE     |           |     FACT_PAYROLL      |
             +-----------------------+           +-----------------------+
```

## 4-Page Executive Reporting Suite
1. **Executive Overview:** High-level demand, placements, fill rates, invoiced revenue, and clinical time-to-fill.
2. **Recruiting & Candidate Supply:** Candidate qualification funnel conversion, specialty breakdowns, and recruiter productivity.
3. **Staffing Operations:** Departmental open shifts, hospital demand distribution, and urgent requisitions.
4. **Payroll & Pipeline Health:** Regular vs. Overtime hours, gross vs. net payroll, and real-time pipeline SLA compliance (99.9%).
