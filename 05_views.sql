USE VoltParkDB;

CREATE OR REPLACE VIEW vw_LiveAvailableSpots AS
SELECT 
    floor_no AS floor_number,
    spot_type,
    COUNT(*) AS total_spots,
    SUM(CASE WHEN status = 'Available' THEN 1 ELSE 0 END) AS available_spots,
    SUM(CASE WHEN status = 'Occupied' THEN 1 ELSE 0 END) AS occupied_spots,
    SUM(CASE WHEN status = 'Maintenance' THEN 1 ELSE 0 END) AS maintenance_spots,
    ROUND((SUM(CASE WHEN status = 'Available' THEN 1 ELSE 0 END) / COUNT(*)) * 100, 1) AS availability_pct
FROM Parking_Spots
GROUP BY floor_no, spot_type
ORDER BY floor_no, spot_type;

CREATE OR REPLACE VIEW vw_DailyRevenueReport AS
SELECT 
    DATE(b.bill_time) AS revenue_date,
    COUNT(b.bill_id) AS total_settled_tickets,
    ROUND(SUM(b.parking_fee), 2) AS total_parking_revenue,
    ROUND(SUM(b.ev_fee), 2) AS total_ev_charging_revenue,
    ROUND(SUM(b.total_amount), 2) AS grand_total_revenue,
    ROUND(AVG(b.total_amount), 2) AS avg_revenue_per_vehicle
FROM Billing b
GROUP BY DATE(b.bill_time)
ORDER BY revenue_date DESC;
