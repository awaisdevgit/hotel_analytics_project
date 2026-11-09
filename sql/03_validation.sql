USE hotel_analytics;
-- Expected: all three row counts 119390 for the supplied source.
SELECT (SELECT COUNT(*) FROM psa_booking) source_rows,
(SELECT COUNT(*) FROM clean_booking) cleaned_rows, COUNT(*) fact_rows,
COUNT(*)-COUNT(DISTINCT booking_id) duplicate_keys FROM fact_booking;
-- Every missing-key count must be zero.
SELECT SUM(h.hotel_key IS NULL) missing_hotel,
SUM(c.channel_key IS NULL) missing_channel,
SUM(g.guest_profile_key IS NULL) missing_guest_profile,
SUM(r.room_key IS NULL) missing_room,
SUM(d.date_key IS NULL) missing_arrival_date
FROM fact_booking f
LEFT JOIN dim_hotel h USING(hotel_key)
LEFT JOIN dim_channel c USING(channel_key)
LEFT JOIN dim_guest_profile g USING(guest_profile_key)
LEFT JOIN dim_room r USING(room_key)
LEFT JOIN dim_date d ON d.date_key=f.arrival_date_key;
-- Both problem counts must be zero.
SELECT SUM(is_completed+is_cancel_only+is_no_show<>1 OR source_is_canceled<>is_failed) invalid_status,
SUM(eligible_stay=1 AND (total_nights<=0 OR adr<0 OR no_known_guests=1 OR date_mismatch=1)) invalid_eligible
FROM fact_booking;
-- Compare to validation_reference/expected_totals.json.
SELECT SUM(eligible_stay) eligible_stays, SUM(eligible_nights) eligible_nights,
SUM(estimated_room_revenue) estimated_room_revenue FROM fact_booking;
