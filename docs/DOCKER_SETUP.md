# Docker Setup for the AMN Case Study

Docker provides a consistent local environment for the repository's Python data-generation scripts, profiling utilities, tests, and Snowflake client code.

Docker does **not** run Snowflake, Azure Data Factory (ADF), Azure Data Lake Storage, or Power BI. Those remain managed cloud services. The container is the development and pipeline-tooling layer that connects to them.

## 1. Install Docker

Install Docker Desktop and confirm that Docker Compose is available:

```powershell
docker --version
docker compose version
```

Expected result: both commands print version information.

## 2. Understand the Docker files

The repository contains:

- `Dockerfile`: Python 3.12 development image running as a non-root user.
- `compose.yaml`: builds the image and mounts the repository at `/app`.
- `requirements.txt`: Python dependencies used by the existing and future scripts.
- `.dockerignore`: excludes local environments, caches, secrets, and archives from the image.
- `.env.example`: safe template for local Snowflake connection variables.

## 3. Build the development image

From the repository root, run:

```powershell
docker compose build
```

The first build downloads the Python base image and installs dependencies. Later builds reuse cached layers unless requirements change.

Checkpoint:

```powershell
docker image ls amn-case-study
```

Expected result: an image named `amn-case-study` with the `dev` tag is listed.

## 4. Verify Python dependencies

```powershell
docker compose run --rm amn-dev python --version
docker compose run --rm amn-dev python -c "import pandas, faker, snowflake.connector; print('Dependencies OK')"
```

Expected result: Python prints its version and then `Dependencies OK`.

`--rm` deletes only the stopped one-off container. It does not delete the image or repository data.

## 5. Prepare the existing datasets

The CMS cleaning script currently uses file paths relative to the `scripts` directory, so set that as its container working directory:

```powershell
docker compose run --rm --workdir /app/scripts amn-dev python clean_hospitals_data.py
```

Run the remaining preparation scripts from `/app`:

```powershell
docker compose run --rm amn-dev python scripts/prepare_synthea_for_amn.py
docker compose run --rm amn-dev python scripts/generate_amn_hr_data.py
```

The Compose file mounts the local repository at `/app`. Files created under `/app/datasets` inside the container therefore appear in the local `datasets` folder.

Checkpoint:

```powershell
Get-ChildItem datasets\cms\hospitals_reference.csv
Get-ChildItem datasets\processed\synthea\*.csv
Get-ChildItem datasets\hr\*.csv
```

Expected result: each command lists non-empty CSV files.

## 6. Open an interactive container shell

Use this when exploring data or debugging scripts:

```powershell
docker compose run --rm amn-dev sh
```

Inside the container:

```sh
pwd
ls
python scripts/generate_amn_hr_data.py
```

Type `exit` to stop and remove the one-off container.

## 7. Configure Snowflake variables

Create a local environment file:

```powershell
Copy-Item .env.example .env
```

Fill in the required development values:

```dotenv
SNOWFLAKE_ACCOUNT=your_account_identifier
SNOWFLAKE_USER=your_development_user
SNOWFLAKE_PASSWORD=your_local_development_secret
SNOWFLAKE_WAREHOUSE=AMN_INGEST_WH
SNOWFLAKE_DATABASE=AMN_DEV
SNOWFLAKE_SCHEMA=RAW
SNOWFLAKE_ROLE=your_ingestion_role
```

Security rules:

- Never commit `.env`.
- Use only development credentials locally.
- Prefer Snowflake key-pair authentication over passwords.
- Use Azure Key Vault and managed identities/service principals for shared and production environments.
- Never bake credentials into the image or Dockerfile.

Verify that variables enter the container without printing their values:

```powershell
docker compose run --rm amn-dev python -c "import os; assert os.getenv('SNOWFLAKE_ACCOUNT'); print('Snowflake environment is configured')"
```

## 8. Run future tools in Docker

As implementation files are added, use the same pattern:

```powershell
# Run profiling
docker compose run --rm amn-dev python scripts/profile_data.py

# Run a Snowflake bootstrap utility
docker compose run --rm amn-dev python scripts/bootstrap_snowflake.py

# Run tests
docker compose run --rm amn-dev python -m pytest
```

The second and third examples are future commands; their scripts/tests must be implemented before use.

## 9. Development workflow

Use this repeatable sequence:

1. Change code locally.
2. Run the script or test through `docker compose run --rm`.
3. Inspect generated data and logs locally.
4. Rebuild only after changing `Dockerfile` or `requirements.txt`.

```powershell
docker compose build
docker compose run --rm amn-dev python scripts/prepare_synthea_for_amn.py
```

Because the repository is mounted, Python source changes do not normally require an image rebuild.

## 10. Troubleshooting

### Docker daemon is unavailable

Start Docker Desktop and wait until it reports that the engine is running.

### A dependency was added

Add it to `requirements.txt`, then rebuild:

```powershell
docker compose build --no-cache
```

Use `--no-cache` only when normal rebuilding does not install the expected dependency.

### Generated files cannot be written

The image uses a non-root Linux user for safer execution. On Windows with Docker Desktop, bind-mounted files normally remain writable. If a corporate Docker policy blocks the mount, confirm that Docker Desktop is allowed to access this workspace directory.

### Snowflake connection fails

Check the account identifier, role grants, network policy, warehouse name, and whether `.env` exists. Do not print the password while debugging.

### The CMS script cannot find its input

Run it with the required working directory:

```powershell
docker compose run --rm --workdir /app/scripts amn-dev python clean_hospitals_data.py
```

## 11. Where Docker fits in the full implementation

```text
Developer laptop / CI
  Docker container
    - prepare synthetic data
    - profile and validate files
    - run unit and integration tests
    - execute Snowflake client utilities
             |
             v
Azure Storage -> ADF -> Snowflake -> Power BI
```

For production ingestion, deploy ADF and Snowflake objects using infrastructure as code and CI/CD. Do not keep an always-running laptop container as the production scheduler.

## Docker completion checklist

- [ ] Docker and Compose versions are available.
- [ ] `docker compose build` succeeds.
- [ ] Dependency verification prints `Dependencies OK`.
- [ ] All existing data-preparation scripts run in containers.
- [ ] Generated datasets appear on the host.
- [ ] `.env` is local and uncommitted.
- [ ] The container can authenticate to the Snowflake development account.
- [ ] No credentials exist in the Dockerfile, image, or repository.
