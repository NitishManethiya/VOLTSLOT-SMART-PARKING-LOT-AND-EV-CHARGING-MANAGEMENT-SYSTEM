USE VoltParkDB;

SELECT '==================================================' AS ' ';
SELECT ' STEP 1: INITIAL STATE OF PARKING SPOTS' AS ' ';
SELECT '==================================================' AS ' ';
SELECT spot_id, floor_no, spot_number, spot_type, status 
FROM Parking_Spots 
WHERE spot_id = 3;

SELECT '==================================================' AS ' ';
SELECT ' STEP 2: VEHICLE ENTERS (CREATING ACTIVE TICKET)' AS ' ';
SELECT '==================================================' AS ' ';

INSERT INTO Parking_Tickets (spot_id, vehicle_id, entry_time, ticket_status)
VALUES (3, 3, NOW() - INTERVAL 150 MINUTE, 'Active');

SET @demo_ev_ticket_id = LAST_INSERT_ID();

SELECT @demo_ev_ticket_id AS 'Generated Active Ticket ID';

SELECT '==================================================' AS ' ';
SELECT ' STEP 3: VERIFY TRIGGER 1 (trg_auto_occupy_spot)' AS ' ';
SELECT '==================================================' AS ' ';
SELECT spot_id, floor_no, spot_number, spot_type, status AS 'Spot Status (Auto-Updated by Trigger)'
FROM Parking_Spots 
WHERE spot_id = 3;

SELECT '==================================================' AS ' ';
SELECT ' STEP 4: LOG EV CHARGING USAGE (22.40 kWh)' AS ' ';
SELECT '==================================================' AS ' ';

INSERT INTO EV_Charging_Logs (ticket_id, kwh_consumed, charging_status, start_time, end_time)
VALUES (@demo_ev_ticket_id, 22.40, 'Charging', NOW() - INTERVAL 140 MINUTE, NOW() - INTERVAL 20 MINUTE);

SELECT * FROM EV_Charging_Logs WHERE ticket_id = @demo_ev_ticket_id;

SELECT '==================================================' AS ' ';
SELECT ' STEP 5: CALL STORED PROCEDURE ProcessVehicleExit' AS ' ';
SELECT '==================================================' AS ' ';

CALL ProcessVehicleExit(@demo_ev_ticket_id);

SELECT '==================================================' AS ' ';
SELECT ' STEP 6: VERIFY TRIGGER 2 (trg_auto_free_spot)' AS ' ';
SELECT '==================================================' AS ' ';
SELECT spot_id, floor_no, spot_number, spot_type, status AS 'Spot Status (Auto-Freed by Trigger)'
FROM Parking_Spots 
WHERE spot_id = 3;

SELECT '==================================================' AS ' ';
SELECT ' STEP 7: VERIFY RECORD IN BILLING TABLE' AS ' ';
SELECT '==================================================' AS ' ';
SELECT * FROM Billing WHERE ticket_id = @demo_ev_ticket_id;

SELECT '==================================================' AS ' ';
SELECT ' VIEW 1: LIVE FLOOR-WISE SPOT AVAILABILITY' AS ' ';
SELECT '==================================================' AS ' ';
SELECT * FROM vw_LiveAvailableSpots;

SELECT '==================================================' AS ' ';
SELECT ' VIEW 2: DAILY REVENUE ANALYTICS REPORT' AS ' ';
SELECT '==================================================' AS ' ';
SELECT * FROM vw_DailyRevenueReport;
