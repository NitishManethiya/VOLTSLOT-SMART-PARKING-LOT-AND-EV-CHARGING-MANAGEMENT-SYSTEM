USE VoltParkDB;

DROP PROCEDURE IF EXISTS AlterVoltParkDBSchema;
DELIMITER //
CREATE PROCEDURE AlterVoltParkDBSchema()
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS 
        WHERE table_schema = 'VoltParkDB' AND table_name = 'Vehicles' AND column_name = 'registration_category'
    ) THEN
        ALTER TABLE Vehicles ADD COLUMN registration_category ENUM('Private', 'Commercial') NOT NULL DEFAULT 'Private';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS 
        WHERE table_schema = 'VoltParkDB' AND table_name = 'Billing' AND column_name = 'penalty_fee'
    ) THEN
        ALTER TABLE Billing ADD COLUMN penalty_fee DECIMAL(8, 2) NOT NULL DEFAULT 0.00 AFTER ev_fee;
    END IF;
END//
DELIMITER ;
CALL AlterVoltParkDBSchema();
DROP PROCEDURE IF EXISTS AlterVoltParkDBSchema;

CREATE OR REPLACE VIEW vw_OverstayingAlerts AS
SELECT 
    pt.ticket_id,
    v.vehicle_no,
    v.registration_category AS plate_type,
    v.owner_name,
    v.contact_number,
    ps.spot_number,
    CONCAT('Floor ', ps.floor_no) AS floor_location,
    DATE_FORMAT(pt.entry_time, '%Y-%m-%d %H:%i') AS entry_time,
    TIMESTAMPDIFF(HOUR, pt.entry_time, NOW()) AS hours_parked_so_far,
    CASE 
        WHEN v.registration_category = 'Commercial' AND TIMESTAMPDIFF(HOUR, pt.entry_time, NOW()) >= 24 THEN 'CRITICAL: COMMERCIAL ABANDONED'
        WHEN v.registration_category = 'Commercial' AND TIMESTAMPDIFF(HOUR, pt.entry_time, NOW()) >= 8 THEN 'WARNING: CAB OVERSTAY'
        WHEN TIMESTAMPDIFF(HOUR, pt.entry_time, NOW()) >= 24 THEN 'WARNING: PRIVATE OVERSTAY'
        ELSE 'NORMAL'
    END AS alert_status,
    ROUND(
        (CEIL(TIMESTAMPDIFF(MINUTE, pt.entry_time, NOW()) / 60.0) * rc.hourly_rate) +
        (CASE 
            WHEN v.registration_category = 'Commercial' AND TIMESTAMPDIFF(HOUR, pt.entry_time, NOW()) > 8 
            THEN 200.00 + ((TIMESTAMPDIFF(HOUR, pt.entry_time, NOW()) - 8) * 50.00)
            WHEN v.registration_category = 'Private' AND TIMESTAMPDIFF(HOUR, pt.entry_time, NOW()) > 24 
            THEN 100.00 + ((TIMESTAMPDIFF(HOUR, pt.entry_time, NOW()) - 24) * 30.00)
            ELSE 0.00 
        END), 2
    ) AS estimated_accrued_bill
FROM Parking_Tickets pt
JOIN Vehicles v ON pt.vehicle_id = v.vehicle_id
JOIN Parking_Spots ps ON pt.spot_id = ps.spot_id
JOIN Rates_Config rc ON v.vehicle_type = rc.vehicle_type
WHERE pt.ticket_status = 'Active' 
  AND (
      (v.registration_category = 'Commercial' AND TIMESTAMPDIFF(HOUR, pt.entry_time, NOW()) >= 8)
      OR TIMESTAMPDIFF(HOUR, pt.entry_time, NOW()) >= 24
  );

DROP PROCEDURE IF EXISTS ProcessVehicleExit;

DELIMITER //

CREATE PROCEDURE ProcessVehicleExit(
    IN p_ticket_id INT
)
proc_label: BEGIN
    DECLARE v_ticket_id INT;
    DECLARE v_spot_id INT;
    DECLARE v_vehicle_id INT;
    DECLARE v_entry_time DATETIME;
    DECLARE v_exit_time DATETIME;
    DECLARE v_ticket_status VARCHAR(20);
    DECLARE v_vehicle_type VARCHAR(20);
    DECLARE v_reg_category VARCHAR(20);
    DECLARE v_hourly_rate DECIMAL(8, 2);
    DECLARE v_ev_rate_per_kwh DECIMAL(8, 2);
    DECLARE v_kwh_consumed DECIMAL(6, 2) DEFAULT 0.00;
    DECLARE v_duration_minutes INT;
    DECLARE v_billed_hours DECIMAL(6, 2);
    DECLARE v_parking_fee DECIMAL(8, 2);
    DECLARE v_ev_fee DECIMAL(8, 2) DEFAULT 0.00;
    DECLARE v_penalty_fee DECIMAL(8, 2) DEFAULT 0.00;
    DECLARE v_penalty_reason VARCHAR(100) DEFAULT 'None';
    DECLARE v_total_amount DECIMAL(8, 2);
    DECLARE v_exists INT DEFAULT 0;

    SELECT COUNT(*) INTO v_exists
    FROM Parking_Tickets
    WHERE ticket_id = p_ticket_id;

    IF v_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'VoltSlot Error: Ticket ID does not exist.';
    END IF;

    SELECT 
        pt.ticket_id,
        pt.spot_id,
        pt.vehicle_id,
        pt.entry_time,
        pt.ticket_status,
        v.vehicle_type,
        v.registration_category,
        rc.hourly_rate,
        rc.ev_rate_per_kwh
    INTO 
        v_ticket_id,
        v_spot_id,
        v_vehicle_id,
        v_entry_time,
        v_ticket_status,
        v_vehicle_type,
        v_reg_category,
        v_hourly_rate,
        v_ev_rate_per_kwh
    FROM Parking_Tickets pt
    JOIN Vehicles v ON pt.vehicle_id = v.vehicle_id
    JOIN Rates_Config rc ON v.vehicle_type = rc.vehicle_type
    WHERE pt.ticket_id = p_ticket_id;

    IF v_ticket_status = 'Completed' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'VoltSlot Error: Ticket is already completed and billed.';
    ELSEIF v_ticket_status = 'Cancelled' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'VoltSlot Error: Cannot process a cancelled ticket.';
    END IF;

    SET v_exit_time = NOW();
    IF v_exit_time < v_entry_time THEN
        SET v_exit_time = v_entry_time;
    END IF;

    SET v_duration_minutes = TIMESTAMPDIFF(MINUTE, v_entry_time, v_exit_time);
    SET v_billed_hours = CEIL(v_duration_minutes / 60.0);
    IF v_billed_hours < 1.00 THEN
        SET v_billed_hours = 1.00;
    END IF;

    SET v_parking_fee = ROUND(v_billed_hours * v_hourly_rate, 2);

    IF v_vehicle_type = 'EV' THEN
        SELECT IFNULL(kwh_consumed, 0.00)
        INTO v_kwh_consumed
        FROM EV_Charging_Logs
        WHERE ticket_id = p_ticket_id;

        IF v_kwh_consumed > 0.00 THEN
            SET v_ev_fee = ROUND(v_kwh_consumed * v_ev_rate_per_kwh, 2);

            UPDATE EV_Charging_Logs
            SET charging_status = 'Completed',
                end_time = IFNULL(end_time, v_exit_time)
            WHERE ticket_id = p_ticket_id;
        END IF;
    END IF;

    IF v_reg_category = 'Commercial' AND v_billed_hours > 8.00 THEN
        SET v_penalty_fee = 200.00 + ((v_billed_hours - 8.00) * 50.00);
        SET v_penalty_reason = 'Commercial Cab Overstay (> 8 hrs)';
    ELSEIF v_reg_category = 'Private' AND v_billed_hours > 24.00 THEN
        SET v_penalty_fee = 100.00 + ((v_billed_hours - 24.00) * 30.00);
        SET v_penalty_reason = 'Private Long-Duration Overstay (> 24 hrs)';
    END IF;

    SET v_total_amount = v_parking_fee + v_ev_fee + v_penalty_fee;

    UPDATE Parking_Tickets
    SET exit_time = v_exit_time,
        ticket_status = 'Completed'
    WHERE ticket_id = p_ticket_id;

    INSERT INTO Billing (
        ticket_id,
        duration_hours,
        parking_fee,
        ev_fee,
        penalty_fee,
        total_amount,
        payment_status,
        bill_time
    ) VALUES (
        p_ticket_id,
        v_billed_hours,
        v_parking_fee,
        v_ev_fee,
        v_penalty_fee,
        v_total_amount,
        'Paid',
        v_exit_time
    );

    SELECT 
        b.bill_id AS invoice_id,
        pt.ticket_id,
        v.vehicle_no,
        v.registration_category AS plate_type,
        v.owner_name,
        v.vehicle_type,
        ps.spot_number,
        ps.floor_no,
        pt.entry_time,
        pt.exit_time,
        b.duration_hours AS billed_hours,
        rc.hourly_rate AS rate_per_hour,
        b.parking_fee,
        v_kwh_consumed AS ev_kwh_consumed,
        rc.ev_rate_per_kwh,
        b.ev_fee,
        b.penalty_fee AS overstay_penalty_fee,
        v_penalty_reason AS penalty_notes,
        b.total_amount AS grand_total_amount,
        b.payment_status,
        ps.status AS spot_status_after_release
    FROM Billing b
    JOIN Parking_Tickets pt ON b.ticket_id = pt.ticket_id
    JOIN Vehicles v ON pt.vehicle_id = v.vehicle_id
    JOIN Parking_Spots ps ON pt.spot_id = ps.spot_id
    JOIN Rates_Config rc ON v.vehicle_type = rc.vehicle_type
    WHERE pt.ticket_id = p_ticket_id;

END//

DELIMITER ;

INSERT INTO Vehicles (vehicle_no, owner_name, contact_number, vehicle_type, registration_category)
VALUES ('DL-01-CAB-8888', 'Sunil Kumar (Uber Driver)', '9812345678', 'Compact', 'Commercial')
ON DUPLICATE KEY UPDATE owner_name = VALUES(owner_name);

INSERT INTO Parking_Tickets (spot_id, vehicle_id, entry_time, ticket_status)
VALUES (5, (SELECT vehicle_id FROM Vehicles WHERE vehicle_no = 'DL-01-CAB-8888'), NOW() - INTERVAL 16 HOUR, 'Active');

SET @cab_ticket = LAST_INSERT_ID();

SELECT * FROM vw_OverstayingAlerts;

CALL ProcessVehicleExit(@cab_ticket);
