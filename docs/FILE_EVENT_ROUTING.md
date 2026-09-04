# AMN landing-file event routing

`TR_LANDING_CSV_CREATED` listens for non-empty BlobCreated events under `/landing/blobs/` whose names end in `.csv`. It passes the event's `folderPath` and `fileName` to `PL_FILE_EVENT_ROUTER`.

The router accepts only these canonical files:

| ADLS path | Child pipeline |
|---|---|
| `landing/cms/hospitals/hospitals_reference.csv` | `PL_COPY_HOSPITALS` |
| `landing/hr/candidates/candidates.csv` | `PL_COPY_CANDIDATES` |
| `landing/hr/staffing_requests/staffing_requests.csv` | `PL_COPY_STAFFING_REQUESTS` |
| `landing/hr/schedules/schedules.csv` | `PL_COPY_SCHEDULES` |
| `landing/hr/payroll/payroll.csv` | `PL_COPY_PAYROLL` |

An unmatched CSV intentionally fails with `UNSUPPORTED_LANDING_FILE`; it never starts a child pipeline. This prevents an unexpected filename from causing a fixed-name ingestion pipeline to reload stale data.

## Safe activation test

1. Deploy with `landing_csv_trigger_activated = false`.
2. In ADF Studio, validate and publish `PL_FILE_EVENT_ROUTER` and `TR_LANDING_CSV_CREATED`.
3. Trigger a manual debug run of the router with one canonical `folderPath` and `fileName`. Confirm only the matching child pipeline runs.
4. Repeat for all five routes and confirm RAW, CURATED, and audit results in Snowflake.
5. Set `landing_csv_trigger_activated = true`, apply Terraform, and upload one non-empty canonical CSV.
6. In ADF Monitor, verify the trigger run, router run, and exactly one child run.

`TR_METADATA_INGEST_BATCH_READY` remains separate. It watches `/landing/blobs/control/AMN_BATCH_READY.json` and starts the metadata-driven batch pipeline. Do not use both triggers for the same delivery contract, or a batch could be ingested twice.
