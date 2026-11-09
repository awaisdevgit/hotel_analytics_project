USE hotel_analytics;
-- All nights and estimated revenue are attributed to booking arrival dates.
SELECT h.hotel, COUNT(*) bookings, SUM(f.eligible_nights) modeled_room_nights,
ROUND(SUM(f.estimated_room_revenue),2) estimated_room_revenue,
ROUND(SUM(f.estimated_room_revenue)/NULLIF(SUM(f.eligible_nights),0),2) weighted_adr
FROM fact_booking f JOIN dim_hotel h USING(hotel_key)
GROUP BY h.hotel ORDER BY h.hotel;
