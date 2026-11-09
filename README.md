# Hotel analytics — simplified implementation kit

## Scope
Two-property pilot; one row per source booking in fact_booking. Five dimensions: hotel, date, channel, guest profile and room. All 12 core KPIs remain. Monthly nights and estimated revenue are attributed entirely to arrival month. This is not daily occupancy or calendar-month earned revenue. No capacity or profit assumptions are added.

## 1. Start in a NEW extracted folder
Do not merge this ZIP into the old kit: obsolete files would remain. Keep the old folder as a backup. Copy your unchanged hotel_bookings.csv into data/. The original CSV is not bundled.

Open PowerShell in hotel_project:

```powershell
py -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe scripts\01_explore.py
```

## 2. Review the evidence before loading
Open the CSV files in Excel (Data > From Text/CSV if columns do not separate correctly). Do not edit generated reference values. Evidence is described in docs/EVIDENCE_AND_DECISIONS.md. A JSON summary and its CSV rendering carry the same values; only show the CSV in slides. The original CSV stays untouched.

## 3. Existing installation only
Back up your PBIX and project database first. In MySQL Workbench run migration/remove_legacy_table.sql once. This drops the obsolete generated nightly table so its foreign key cannot block rebuilding the booking fact. New installations skip this step.

## 4. Load and transform
Requires MySQL 8.0+ and permission to create the dedicated hotel_analytics database.

```powershell
.\.venv\Scripts\python.exe scripts\02_load_mysql.py --rebuild --user root
```

Enter the MySQL password at the hidden prompt. --rebuild replaces raw contents and generated project tables. It is a full refresh, not an incremental historical archive. Do not use this database for unrelated work. MySQL DDL can commit independently; a failed rebuild may leave partial tables. Correct the error and rerun.

The loader checks the source fingerprint against EDA, loads raw text into psa_booking, executes SQL transformations, compares 11 aggregate totals with Python reference totals, and exports the six warehouse tables. A failed comparison stops execution; do not describe the run as validated.

## 5. Validate in Workbench
Open sql/03_validation.sql, execute all statements, and save screenshots of the result grids. Expected source/clean/fact rows: 119390 each. Duplicate key, missing-dimension and invalid-row counts: zero. Eligible stays: 74362; nights: 254085; revenue: 25970113.47. The loader's reconciliation only covers its 11 totals; Workbench key checks are separate.

## 6. One business question
Run sql/02_analytics.sql. It compares bookings, eligible nights, estimated revenue and weighted ADR by hotel. Explain why ADR is revenue divided by nights, not an unweighted mean of booking rates.

## 7. Power BI later
Remove the old nightly query/table and its two measures from your existing PBIX. Import only fact_booking and the five dim_ tables. Each dimension key has a one-to-many, single-direction active relationship to its corresponding booking-fact key; dim_date[date_key] connects to fact_booking[arrival_date_key]. Do not make status_date_key another active date relationship. Keep eligible_nights. Use the supplied DAX one measure at a time. Table names must match DAX (remove database prefixes in Power BI or adjust references).

No prototype workbook is generated. Power BI is outside the current milestone implementation demonstration.

## GitHub
The code is ready to upload, but this kit has not been published to GitHub. Supply your intended repository URL to publish to the correct location. Do not cite an invented GitHub URL. Keep CSV data, database exports, credentials and .venv out of the repository; .gitignore is included. Cite AI assistance for code generation and explain the team's review and validation. The project-specific exploration script is not an existing third-party GitHub source.

## Test status
The revised Python exploration was run on the original 119390-row CSV and reproduced the established reference totals. Python syntax checked. SQL and Power BI require local execution; no MySQL server was available for this revision. Included expected outputs are reference targets, not proof that your local load passed. Presentation changes are a separate deliverable; the old PPT still describes the older architecture until revised.
