-- ONE-TIME migration only for an existing dedicated project database.
-- Back up first. Deletes the obsolete generated table, never the source CSV.
USE hotel_analytics;
DROP TABLE IF EXISTS fact_stay_night;
