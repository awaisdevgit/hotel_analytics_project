USE hotel_analytics;
-- Dedicated student schema only. Full rebuild removes generated tables, not source CSV.
DROP VIEW IF EXISTS vw_booking_analysis;
DROP TABLE IF EXISTS fact_booking;
DROP TABLE IF EXISTS dim_date;
DROP TABLE IF EXISTS dim_room;
DROP TABLE IF EXISTS dim_guest_profile;
DROP TABLE IF EXISTS dim_channel;
DROP TABLE IF EXISTS dim_hotel;
DROP TABLE IF EXISTS clean_booking;
CREATE TABLE clean_booking AS
WITH typed AS (
 SELECT booking_id, TRIM(hotel) hotel,
 STR_TO_DATE(CONCAT(arrival_date_year,'-',arrival_date_month,'-',arrival_date_day_of_month),'%Y-%M-%d') arrival_date,
 STR_TO_DATE(reservation_status_date,'%Y-%m-%d') status_date,
 CAST(stays_in_weekend_nights AS SIGNED)+CAST(stays_in_week_nights AS SIGNED) total_nights,
 CAST(lead_time AS SIGNED) lead_time, CAST(adr AS DECIMAL(12,2)) adr,
 CAST(adults AS SIGNED) adults, CAST(children AS DECIMAL(8,0)) children, CAST(babies AS SIGNED) babies,
 COALESCE(NULLIF(TRIM(country),''),'Unknown') country,TRIM(customer_type) customer_type,
 TRIM(distribution_channel) distribution_channel,TRIM(market_segment) market_segment,
 TRIM(reserved_room_type) reserved_room_type,TRIM(assigned_room_type) assigned_room_type,
 TRIM(deposit_type) deposit_type,TRIM(meal) meal,
 CAST(is_repeated_guest AS SIGNED) is_repeated_guest,TRIM(reservation_status) reservation_status,
 CAST(is_canceled AS SIGNED) source_is_canceled,
 CAST(booking_changes AS SIGNED) booking_changes,
 CAST(total_of_special_requests AS SIGNED) special_requests
 FROM psa_booking
), flags AS (
 SELECT *, DATE_ADD(arrival_date,INTERVAL total_nights DAY) departure_date,
 DATE_SUB(arrival_date,INTERVAL lead_time DAY) booking_date_estimate,
 CASE WHEN children IS NULL THEN 'Unknown' WHEN children+babies>0 THEN 'With children' ELSE 'Adults only' END party_type,
 CASE WHEN lead_time<=7 THEN '00-07' WHEN lead_time<=30 THEN '08-30' WHEN lead_time<=90 THEN '031-090' WHEN lead_time<=180 THEN '091-180' ELSE '181+' END lead_band,
 (reservation_status='Check-Out') is_completed,(reservation_status='Canceled') is_cancel_only,
 (reservation_status='No-Show') is_no_show,(reservation_status IN ('Canceled','No-Show')) is_failed,
 (reserved_room_type<>assigned_room_type) room_mismatch,(distribution_channel='Direct') is_direct,
 (adults+COALESCE(children,0)+babies=0) no_known_guests,
 (reservation_status='Check-Out' AND status_date<>DATE_ADD(arrival_date,INTERVAL total_nights DAY)) date_mismatch,
 (adr<0 OR adr>1000) adr_review
 FROM typed
), eligibility AS (
 SELECT *, (is_completed=1 AND total_nights>0 AND adr>=0 AND no_known_guests=0 AND date_mismatch=0 AND arrival_date IS NOT NULL) eligible_stay
 FROM flags
)
SELECT *, total_nights*eligible_stay eligible_nights,
 CAST(adr*total_nights*eligible_stay AS DECIMAL(14,2)) estimated_room_revenue,
 CAST(CASE WHEN is_cancel_only=1 AND adr>=0 AND total_nights>0 THEN adr*total_nights ELSE 0 END AS DECIMAL(14,2)) cancelled_booked_value,
 CASE WHEN is_cancel_only=1 THEN DATEDIFF(arrival_date,status_date) END cancel_days_before_arrival,
 is_repeated_guest*is_completed repeat_completed
FROM eligibility;
ALTER TABLE clean_booking ADD PRIMARY KEY (booking_id);
CREATE TABLE dim_hotel AS SELECT ROW_NUMBER() OVER(ORDER BY hotel) hotel_key,hotel FROM (SELECT DISTINCT hotel FROM clean_booking) s;
ALTER TABLE dim_hotel MODIFY hotel_key BIGINT NOT NULL, ADD PRIMARY KEY(hotel_key);
CREATE TABLE dim_channel AS SELECT ROW_NUMBER() OVER(ORDER BY distribution_channel,market_segment) channel_key,distribution_channel,market_segment FROM (SELECT DISTINCT distribution_channel,market_segment FROM clean_booking) s;
ALTER TABLE dim_channel MODIFY channel_key BIGINT NOT NULL, ADD PRIMARY KEY(channel_key);
CREATE TABLE dim_guest_profile AS SELECT ROW_NUMBER() OVER(ORDER BY country,customer_type,is_repeated_guest,party_type) guest_profile_key,country,customer_type,is_repeated_guest,party_type FROM (SELECT DISTINCT country,customer_type,is_repeated_guest,party_type FROM clean_booking) s;
ALTER TABLE dim_guest_profile MODIFY guest_profile_key BIGINT NOT NULL, ADD PRIMARY KEY(guest_profile_key);
CREATE TABLE dim_room AS SELECT ROW_NUMBER() OVER(ORDER BY reserved_room_type,assigned_room_type) room_key,reserved_room_type,assigned_room_type FROM (SELECT DISTINCT reserved_room_type,assigned_room_type FROM clean_booking) s;
ALTER TABLE dim_room MODIFY room_key BIGINT NOT NULL, ADD PRIMARY KEY(room_key);
SET SESSION cte_max_recursion_depth=5000;
CREATE TABLE dim_date AS
WITH RECURSIVE dates AS (
 SELECT DATE('2013-01-01') full_date
 UNION ALL SELECT DATE_ADD(full_date,INTERVAL 1 DAY) FROM dates WHERE full_date<'2018-12-31'
)
SELECT CAST(DATE_FORMAT(full_date,'%Y%m%d') AS SIGNED) date_key, full_date,
 YEAR(full_date) year,MONTH(full_date) month_number,MONTHNAME(full_date) month_name,
 DATE_FORMAT(full_date,'%Y-%m') `year_month`,QUARTER(full_date) quarter_number,
 WEEKDAY(full_date)+1 weekday_number,DAYNAME(full_date) weekday_name,
 (WEEKDAY(full_date)>=5) is_weekend,
 (full_date BETWEEN '2015-07-01' AND '2017-08-31') arrival_coverage
FROM dates;
ALTER TABLE dim_date ADD PRIMARY KEY(date_key);
CREATE TABLE fact_booking AS
SELECT b.booking_id,h.hotel_key,c.channel_key,g.guest_profile_key,r.room_key,
 CAST(DATE_FORMAT(b.arrival_date,'%Y%m%d') AS SIGNED) arrival_date_key,
 CAST(DATE_FORMAT(b.status_date,'%Y%m%d') AS SIGNED) status_date_key,
 b.total_nights,b.lead_time,b.lead_band,b.adr,b.adults,b.children,b.babies,b.deposit_type,b.meal,
 b.reservation_status,b.source_is_canceled,b.is_completed,b.is_cancel_only,b.is_no_show,b.is_failed,
 b.is_direct,b.room_mismatch,b.no_known_guests,b.date_mismatch,b.adr_review,
 b.eligible_stay,b.eligible_nights,b.estimated_room_revenue,b.cancelled_booked_value,
 b.cancel_days_before_arrival,b.repeat_completed,b.booking_changes,b.special_requests
FROM clean_booking b
JOIN dim_hotel h ON h.hotel=b.hotel
JOIN dim_channel c ON c.distribution_channel=b.distribution_channel AND c.market_segment=b.market_segment
JOIN dim_guest_profile g ON g.country=b.country AND g.customer_type=b.customer_type AND g.is_repeated_guest=b.is_repeated_guest AND g.party_type=b.party_type
JOIN dim_room r ON r.reserved_room_type=b.reserved_room_type AND r.assigned_room_type=b.assigned_room_type;
ALTER TABLE fact_booking MODIFY hotel_key BIGINT NOT NULL, MODIFY channel_key BIGINT NOT NULL, MODIFY guest_profile_key BIGINT NOT NULL, MODIFY room_key BIGINT NOT NULL,
 ADD PRIMARY KEY(booking_id),
 ADD FOREIGN KEY(hotel_key) REFERENCES dim_hotel(hotel_key),
 ADD FOREIGN KEY(channel_key) REFERENCES dim_channel(channel_key),
 ADD FOREIGN KEY(guest_profile_key) REFERENCES dim_guest_profile(guest_profile_key),
 ADD FOREIGN KEY(room_key) REFERENCES dim_room(room_key),
 ADD FOREIGN KEY(arrival_date_key) REFERENCES dim_date(date_key);
CREATE VIEW vw_booking_analysis AS
SELECT f.*,h.hotel,c.distribution_channel,c.market_segment,g.country,g.customer_type,g.is_repeated_guest,g.party_type,
 r.reserved_room_type,r.assigned_room_type,d.full_date arrival_date,d.`year_month`
FROM fact_booking f JOIN dim_hotel h USING(hotel_key) JOIN dim_channel c USING(channel_key)
JOIN dim_guest_profile g USING(guest_profile_key) JOIN dim_room r USING(room_key)
JOIN dim_date d ON d.date_key=f.arrival_date_key;
