USE VoltParkDB;

-- =============================================================================
-- MENTOR VIVA & LAB EVALUATION QUERY SUITE
-- VoltSlot: Smart Parking Lot & EV Charging Management System (VoltParkDB)
-- Run queries individually or in sections using MySQL Workbench (Ctrl + Enter)
-- =============================================================================

-- =============================================================================
-- SECTION 1: SCHEMA & INTEGRITY VERIFICATION
-- Questions mentor asks: "Show me your tables, keys, and foreign key relations"
-- =============================================================================

SELECT '--- 1.1: ALL SYSTEM TABLES ---' AS 'Demonstration Step';
SHOW TABLES;

SELECT '--- 1.2: SPOT TABLE STRUCTURE & CONSTRAINTS ---' AS 'Demonstration Step';
DESCRIBE Parking_Spots;

SELECT '--- 1.3: FOREIGN KEY & REFERENTIAL INTEGRITY CONSTRAINTS ---' AS 'Demonstration Step';
SELECT 
    TABLE_NAME, 
    COLUMN_NAME, 
    CONSTRAINT_NAME, 
    REFERENCED_TABLE_NAME, 
    REFERENCED_COLUMN_NAME
FROM information_schema.KEY_COLUMN_USAGE
WHERE TABLE_SCHEMA = 'VoltParkDB' AND REFERENCED_TABLE_NAME IS NOT NULL;


-- =============================================================================
-- SECTION 2: PROVING PARKING SLOTS ARE NOT FIXED (DYNAMIC CAPACITY)
-- Questions mentor asks: "Are your spots fixed or can we expand capacity dynamically?"
-- =============================================================================

SELECT '--- 2.1: CURRENT LIVE CAPACITY BEFORE ADDING NEW SPOTS ---' AS 'Demonstration Step';
SELECT * FROM vw_LiveAvailableSpots;

SELECT '--- 2.2: DYNAMICALLY ADDING A NEW 3RD FLOOR AND EXTRA SLOTS ---' AS 'Demonstration Step';
INSERT INTO Parking_Spots (floor_no, spot_number, spot_type, status) VALUES
(1, 'F1-C02', 'Compact', 'Available'),
(3, 'F3-C01', 'Compact', 'Available'),
(3, 'F3-S01', 'SUV',     'Available'),
(3, 'F3-E01', 'EV',      'Available')
ON DUPLICATE KEY UPDATE status = VALUES(status);

SELECT '--- 2.3: VERIFY CAPACITY VIEW AUTO-UPDATED FOR NEW SPOTS & FLOOR 3 ---' AS 'Demonstration Step';
SELECT * FROM vw_LiveAvailableSpots;


-- =============================================================================
-- SECTION 3: TRIGGER 1 DEMO (AUTOMATIC SPOT OCCUPANCY ON ENTRY)
-- Questions mentor asks: "Show me how spot status changes without manual UPDATE queries"
-- =============================================================================

SELECT '--- 3.1: CHECK SPOT STATUS BEFORE VEHICLE ENTRY (Should be Available) ---' AS 'Demonstration Step';
SELECT spot_id, spot_number, floor_no, spot_type, status 
FROM Parking_Spots 
WHERE spot_id = 2;

SELECT '--- 3.2: VEHICLE ENTERS -> ISSUE ACTIVE TICKET ---' AS 'Demonstration Step';
INSERT INTO Parking_Tickets (spot_id, vehicle_id, entry_time, ticket_status)
VALUES (2, 2, NOW() - INTERVAL 120 MINUTE, 'Active');

SET @viva_ticket_id = LAST_INSERT_ID();
SELECT @viva_ticket_id AS 'Generated Active Ticket ID';

SELECT '--- 3.3: VERIFY TRIGGER trg_auto_occupy_spot AUTO-CHANGED SPOT TO Occupied ---' AS 'Demonstration Step';
SELECT spot_id, spot_number, floor_no, spot_type, status 
FROM Parking_Spots 
WHERE spot_id = 2;


-- =============================================================================
-- SECTION 4: EV CHARGING LOG (ELECTRICITY CONSUMPTION)
-- Questions mentor asks: "How do you calculate EV power and link it with tickets?"
-- =============================================================================

SELECT '--- 4.1: LOG 18.5 kWh CHARGING FOR TICKET ---' AS 'Demonstration Step';
INSERT INTO EV_Charging_Logs (ticket_id, kwh_consumed, charging_status, start_time, end_time)
VALUES (@viva_ticket_id, 18.50, 'Charging', NOW() - INTERVAL 110 MINUTE, NOW() - INTERVAL 10 MINUTE)
ON DUPLICATE KEY UPDATE kwh_consumed = 18.50;

SELECT * FROM EV_Charging_Logs WHERE ticket_id = @viva_ticket_id;


-- =============================================================================
-- SECTION 5: STORED PROCEDURE DEMO (ATOMIC EXIT & BILLING RECEIPT)
-- Questions mentor asks: "How does billing work? Show me the procedure and Trigger 2"
-- =============================================================================

SELECT '--- 5.1: EXECUTE ATOMIC STORED PROCEDURE ProcessVehicleExit ---' AS 'Demonstration Step';
CALL ProcessVehicleExit(@viva_ticket_id);

SELECT '--- 5.2: VERIFY TRIGGER trg_auto_free_spot AUTO-RELEASED SPOT BACK TO Available ---' AS 'Demonstration Step';
SELECT spot_id, spot_number, floor_no, spot_type, status 
FROM Parking_Spots 
WHERE spot_id = 2;

SELECT '--- 5.3: VERIFY INVOICE RECORD PERMANENTLY STORED IN BILLING TABLE ---' AS 'Demonstration Step';
SELECT * FROM Billing WHERE ticket_id = @viva_ticket_id;


-- =============================================================================
-- SECTION 6: UNIQUE FEATURE: OLA/UBER CAB OVERSTAY & PENALTY ENGINE
-- Questions mentor asks: "What unique problem did you solve? Show cab overstay charges"
-- =============================================================================

SELECT '--- 6.1: REGISTER COMMERCIAL CAB (OLA/UBER YELLOW PLATE) ---' AS 'Demonstration Step';
INSERT INTO Vehicles (vehicle_no, owner_name, contact_number, vehicle_type, registration_category)
VALUES ('DL-01-CAB-9900', 'Mohan Lal (Ola Cab Driver)', '9811223344', 'Compact', 'Commercial')
ON DUPLICATE KEY UPDATE owner_name = VALUES(owner_name);

SELECT '--- 6.2: CAB PARKED 14 HOURS AGO AND FORGOT TO LEAVE ---' AS 'Demonstration Step';
INSERT INTO Parking_Tickets (spot_id, vehicle_id, entry_time, ticket_status)
VALUES (
    1, 
    (SELECT vehicle_id FROM Vehicles WHERE vehicle_no = 'DL-01-CAB-9900'), 
    NOW() - INTERVAL 14 HOUR, 
    'Active'
);

SET @cab_viva_ticket = LAST_INSERT_ID();

SELECT '--- 6.3: LIVE OVERSTAY ALERT DASHBOARD (Driver phone number + live fine) ---' AS 'Demonstration Step';
SELECT * FROM vw_OverstayingAlerts;

SELECT '--- 6.4: PROCESS CAB EXIT (Shows ₹200 flat fine + ₹50/hr overstay surcharge) ---' AS 'Demonstration Step';
CALL ProcessVehicleExit(@cab_viva_ticket);


-- =============================================================================
-- SECTION 7: ADVANCED ANALYTICAL QUERIES MENTORS LOVE TO ASK IN VIVA
-- =============================================================================

SELECT '--- 7.1: LIST ALL CURRENTLY PARKED CARS WITH TIME ELAPSED & SPOT (JOIN) ---' AS 'Demonstration Step';
SELECT 
    pt.ticket_id,
    v.vehicle_no,
    v.owner_name,
    v.contact_number,
    v.vehicle_type,
    v.registration_category AS plate_type,
    ps.spot_number,
    ps.floor_no,
    pt.entry_time,
    TIMESTAMPDIFF(MINUTE, pt.entry_time, NOW()) AS parked_minutes_so_far
FROM Parking_Tickets pt
JOIN Vehicles v ON pt.vehicle_id = v.vehicle_id
JOIN Parking_Spots ps ON pt.spot_id = ps.spot_id
WHERE pt.ticket_status = 'Active'
ORDER BY pt.entry_time ASC;


SELECT '--- 7.2: REVENUE BREAKDOWN BY VEHICLE TYPE (Compact vs SUV vs EV) ---' AS 'Demonstration Step';
SELECT 
    v.vehicle_type,
    COUNT(b.bill_id) AS total_bills,
    ROUND(SUM(b.parking_fee), 2) AS total_parking_charges,
    ROUND(SUM(b.ev_fee), 2) AS total_ev_charges,
    ROUND(SUM(b.penalty_fee), 2) AS total_overstay_penalties,
    ROUND(SUM(b.total_amount), 2) AS grand_total_revenue
FROM Billing b
JOIN Parking_Tickets pt ON b.ticket_id = pt.ticket_id
JOIN Vehicles v ON pt.vehicle_id = v.vehicle_id
WHERE b.payment_status = 'Paid'
GROUP BY v.vehicle_type;


SELECT '--- 7.3: MOST POPULAR / FREQUENTLY UTILIZED PARKING SPOTS (AGGREGATION) ---' AS 'Demonstration Step';
SELECT 
    ps.spot_number,
    ps.floor_no,
    ps.spot_type,
    COUNT(pt.ticket_id) AS times_used,
    IFNULL(ROUND(SUM(b.total_amount), 2), 0.00) AS total_revenue_generated
FROM Parking_Spots ps
LEFT JOIN Parking_Tickets pt ON ps.spot_id = pt.spot_id
LEFT JOIN Billing b ON pt.ticket_id = b.ticket_id
GROUP BY ps.spot_id, ps.spot_number, ps.floor_no, ps.spot_type
ORDER BY times_used DESC, total_revenue_generated DESC;


SELECT '--- 7.4: TOTAL EV ELECTRICITY (kWh) CONSUMED & EV REVENUE STATS ---' AS 'Demonstration Step';
SELECT 
    COUNT(log_id) AS total_charging_sessions,
    ROUND(SUM(kwh_consumed), 2) AS total_units_consumed_kwh,
    ROUND(AVG(kwh_consumed), 2) AS avg_kwh_per_session,
    ROUND(SUM(kwh_consumed * 12.00), 2) AS total_electricity_sales_inr
FROM EV_Charging_Logs
WHERE charging_status = 'Completed';


SELECT '--- 7.5: DAILY REVENUE & PERFORMANCE REPORT VIEW ---' AS 'Demonstration Step';
SELECT * FROM vw_DailyRevenueReport;
