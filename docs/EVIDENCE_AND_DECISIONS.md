# Essential evidence and cleaning decisions

## Generated files
| File | Job | Show in presentation? |
|---|---|---|
| evidence/field_profile.csv | All 32 source fields: pandas type, missing count, distinct count, numeric minimum/maximum/mean | A readable extract; full version in appendix |
| evidence/quality_summary.csv | Issue counts, coverage and source fingerprint | Show issue counts with decisions |
| evidence/quality_summary.json | Same summary, machine-readable; loader checks source fingerprint | No separate slide |
| evidence/status_crosscheck.csv | Cross-tab of reservation status and cancellation flag | Show the small table or its conclusion |
| evidence/duplicate_sensitivity.csv | Retain-all versus hypothetical identical-row removal | Show to justify the choice |
| evidence/review_queue.csv | Records flagged for zero nights, unusual ADR, no known guests, date mismatch or missing children | A few examples in appendix |
| validation_reference/expected_totals.json | Independent Python reference for KPI totals | Not cleaning evidence; used by loader |
| evidence/mysql_reconciliation.json | Actual SQL totals after the loader's comparisons pass | Validation slide; created only after local load |

Five cleaning evidence topics, six files because the quality summary has CSV and JSON versions. No large reference-bookings CSV, charts, channel/monthly reference exports or Excel prototype. Do not delete reference totals: the loader depends on them.

## Decisions
- Repeated source rows: retain. A generated booking_id identifies a source row, not a proven unique real reservation. Removing repeats is shown only as sensitivity analysis.
- Missing country: label Unknown. Missing children: retain missing; party type Unknown. Filling missing children with zero solely for the no-known-guests check does not assert actual child count.
- Agent/company missing values remain in raw storage. These fields are not needed for the chosen dimensional analysis.
- Zero-night bookings: retain in booking counts; exclude from commercial eligible stays.
- Negative ADR: retain source, flag, exclude from commercial measures. ADR above 1000: review flag, not automatic exclusion. Zero ADR remains eligible if other checks pass.
- No known guests: exclude from commercial eligible stays, retain in booking outcomes.
- Check-Out date inconsistent with arrival plus nights: exclude from commercial eligible stays, retain in outcome counts.
- Canceled and No-Show: separate outcomes; both contribute to failed arrivals. is_canceled=1 includes both in this dataset.
- Eligible: Check-Out, positive nights, nonnegative ADR, at least one known guest, matching checkout date and valid arrival date. One room per row is a modeling assumption.
- Arrival/status parse errors, unexpected columns/statuses, negative nights/lead time or contradictory failure flags stop exploration. They require investigation rather than silent repair.
- Count overlap: a row can have several issues. Do not add issue counts to calculate excluded stays. Missing children alone does not necessarily exclude a stay.

## Data description slide
Keep a compact source overview before field meanings. field_profile.csv replaces a separate statistics script. The source dictionary supplies meanings; these are different tasks. Numeric min/max/mean are automated descriptions, not semantic classifications. Month names are ordered cyclic categories; week/day numbers need calendar context. is_canceled is not simply cancellation-only. Source column is lowercase hotel. No additional script is needed just to duplicate these counts.

## Script sequence
01_explore.py: copies data in memory, builds dates and flags, calculates independent references, and writes essential evidence. It never modifies the original CSV.
02_load_mysql.py: verifies same source, prompts for credentials, loads raw records, runs transformations, reconciles totals, exports six tables.
00_schema.sql: creates database and text-preserving raw table.
01_transform.sql: converts types, derives flags and eligibility, builds five dimensions and one fact, adds keys, creates a convenience joined view.
03_validation.sql: checks row preservation, key uniqueness, all five dimension links, valid statuses, eligibility and totals.
02_analytics.sql: demonstrates one hotel comparison.

## Slide appendix navigation plan
Use a main 'EDA evidence' slide with filename hyperlinks to appendix slides showing readable Excel extracts. Use one appendix destination per origin when return destinations differ. Add a transparent full-slide rectangle on each appendix screenshot slide and link it back to the origin slide; clicking the screenshot then returns. Do the same for exploration, schema, transformation, load and validation steps. Test links in Slide Show mode. Include concise comments/callouts around code excerpts; do not squeeze full scripts into one unreadable image. Label supplied reference outputs versus actual local validation screenshots.

KPI tables should carry definitions, formula, source fields, processing, presentation and agreed target status. A snapshot/reference value is evidence for this dataset, not a business target. Omit the extra snapshot-reference row from presentation KPI tables, but retain relevant results on the validation slide.
