USE VoltParkDB;

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
    DECLARE v_hourly_rate DECIMAL(8, 2);
    DECLARE v_ev_rate_per_kwh DECIMAL(8, 2);
    DECLARE v_kwh_consumed DECIMAL(6, 2) DEFAULT 0.00;
    DECLARE v_duration_minutes INT;
    DECLARE v_billed_hours DECIMAL(6, 2);
    DECLARE v_parking_fee DECIMAL(8, 2);
    DECLARE v_ev_fee DECIMAL(8, 2) DEFAULT 0.00;
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
        rc.hourly_rate,
        rc.ev_rate_per_kwh
    INTO 
        v_ticket_id,
        v_spot_id,
        v_vehicle_id,
        v_entry_time,
        v_ticket_status,
        v_vehicle_type,
        v_hourly_rate,
        v_ev_rate_per_kwh
    FROM Parking_Tickets pt
    JOIN Vehicles v ON pt.vehicle_id = v.vehicle_id
    JOIN Rates_Config rc ON v.vehicle_type = rc.vehicle_type
    WHERE pt.ticket_id = p_ticket_id;

    IF v_ticket_status = 'Completed' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'VoltSlot Error: Ticket has already been completed and settled.';
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

    SET v_total_amount = v_parking_fee + v_ev_fee;

    UPDATE Parking_Tickets
    SET exit_time = v_exit_time,
        ticket_status = 'Completed'
    WHERE ticket_id = p_ticket_id;

    INSERT INTO Billing (
        ticket_id,
        duration_hours,
        parking_fee,
        ev_fee,
        total_amount,
        payment_status,
        bill_time
    ) VALUES (
        p_ticket_id,
        v_billed_hours,
        v_parking_fee,
        v_ev_fee,
        v_total_amount,
        'Paid',
        v_exit_time
    );

    SELECT 
        b.bill_id AS invoice_id,
        pt.ticket_id,
        v.vehicle_no,
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
        b.total_amount,
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
