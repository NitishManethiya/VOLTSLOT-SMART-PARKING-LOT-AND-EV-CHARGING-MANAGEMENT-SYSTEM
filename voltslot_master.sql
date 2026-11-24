CREATE DATABASE IF NOT EXISTS VoltParkDB;
USE VoltParkDB;

DROP VIEW IF EXISTS vw_OverstayingAlerts;
DROP VIEW IF EXISTS vw_DailyRevenueReport;
DROP VIEW IF EXISTS vw_LiveAvailableSpots;
DROP PROCEDURE IF EXISTS ProcessVehicleExit;
DROP TRIGGER IF EXISTS trg_auto_occupy_spot;
DROP TRIGGER IF EXISTS trg_auto_free_spot;
DROP TABLE IF EXISTS Billing;
DROP TABLE IF EXISTS EV_Charging_Logs;
DROP TABLE IF EXISTS Parking_Tickets;
DROP TABLE IF EXISTS Vehicles;
DROP TABLE IF EXISTS Rates_Config;
DROP TABLE IF EXISTS Parking_Spots;

CREATE TABLE Parking_Spots (
    spot_id INT AUTO_INCREMENT PRIMARY KEY,
    floor_no INT NOT NULL,
    spot_number VARCHAR(10) NOT NULL UNIQUE,
    spot_type ENUM('Compact', 'SUV', 'EV') NOT NULL,
    status ENUM('Available', 'Occupied', 'Maintenance') NOT NULL DEFAULT 'Available'
) ENGINE=InnoDB;

CREATE TABLE Vehicles (
    vehicle_id INT AUTO_INCREMENT PRIMARY KEY,
    vehicle_no VARCHAR(20) NOT NULL UNIQUE,
    owner_name VARCHAR(100) NOT NULL,
    contact_number VARCHAR(15) NOT NULL,
    vehicle_type ENUM('Compact', 'SUV', 'EV') NOT NULL,
    registration_category ENUM('Private', 'Commercial') NOT NULL DEFAULT 'Private'
) ENGINE=InnoDB;

CREATE TABLE Rates_Config (
    rate_id INT AUTO_INCREMENT PRIMARY KEY,
    vehicle_type ENUM('Compact', 'SUV', 'EV') NOT NULL UNIQUE,
    hourly_rate DECIMAL(8, 2) NOT NULL,
    ev_rate_per_kwh DECIMAL(8, 2) NOT NULL DEFAULT 0.00
) ENGINE=InnoDB;

CREATE TABLE Parking_Tickets (
    ticket_id INT AUTO_INCREMENT PRIMARY KEY,
    spot_id INT NOT NULL,
    vehicle_id INT NOT NULL,
    entry_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    exit_time DATETIME NULL,
    ticket_status ENUM('Active', 'Completed', 'Cancelled') NOT NULL DEFAULT 'Active',
    CONSTRAINT fk_ticket_spot FOREIGN KEY (spot_id) 
        REFERENCES Parking_Spots(spot_id) ON DELETE CASCADE,
    CONSTRAINT fk_ticket_vehicle FOREIGN KEY (vehicle_id) 
        REFERENCES Vehicles(vehicle_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE EV_Charging_Logs (
    log_id INT AUTO_INCREMENT PRIMARY KEY,
    ticket_id INT NOT NULL UNIQUE,
    kwh_consumed DECIMAL(6, 2) NOT NULL DEFAULT 0.00,
    charging_status ENUM('Pending', 'Charging', 'Completed') NOT NULL DEFAULT 'Pending',
    start_time DATETIME NULL,
    end_time DATETIME NULL,
    CONSTRAINT fk_charging_ticket FOREIGN KEY (ticket_id) 
        REFERENCES Parking_Tickets(ticket_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE Billing (
    bill_id INT AUTO_INCREMENT PRIMARY KEY,
    ticket_id INT NOT NULL UNIQUE,
    duration_hours DECIMAL(6, 2) NOT NULL,
    parking_fee DECIMAL(8, 2) NOT NULL,
    ev_fee DECIMAL(8, 2) NOT NULL DEFAULT 0.00,
    penalty_fee DECIMAL(8, 2) NOT NULL DEFAULT 0.00,
    total_amount DECIMAL(8, 2) NOT NULL,
    payment_status ENUM('Paid', 'Pending') NOT NULL DEFAULT 'Pending',
    bill_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_billing_ticket FOREIGN KEY (ticket_id) 
        REFERENCES Parking_Tickets(ticket_id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE INDEX idx_vehicle_no ON Vehicles(vehicle_no);
CREATE INDEX idx_ticket_status ON Parking_Tickets(ticket_status);

DELIMITER //

CREATE TRIGGER trg_auto_occupy_spot
AFTER INSERT ON Parking_Tickets
FOR EACH ROW
BEGIN
    IF NEW.ticket_status = 'Active' THEN
        UPDATE Parking_Spots
        SET status = 'Occupied'
        WHERE spot_id = NEW.spot_id;
    END IF;
END//

CREATE TRIGGER trg_auto_free_spot
AFTER UPDATE ON Parking_Tickets
FOR EACH ROW
BEGIN
    IF (NEW.ticket_status = 'Completed' AND OLD.ticket_status <> 'Completed') 
       OR (NEW.ticket_status = 'Cancelled' AND OLD.ticket_status <> 'Cancelled') THEN
        UPDATE Parking_Spots
        SET status = 'Available'
        WHERE spot_id = NEW.spot_id;
    END IF;
END//

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
    ROUND(SUM(b.penalty_fee), 2) AS total_overstay_penalties,
    ROUND(SUM(b.total_amount), 2) AS grand_total_revenue,
    ROUND(AVG(b.total_amount), 2) AS avg_revenue_per_vehicle
FROM Billing b
GROUP BY DATE(b.bill_time)
ORDER BY revenue_date DESC;

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

INSERT INTO Rates_Config (vehicle_type, hourly_rate, ev_rate_per_kwh) VALUES
('Compact', 30.00, 0.00),
('SUV',     50.00, 0.00),
('EV',      40.00, 12.00);

INSERT INTO Parking_Spots (floor_no, spot_number, spot_type, status) VALUES
(1, 'F1-C01', 'Compact', 'Available'),
(1, 'F1-S01', 'SUV',     'Available'),
(1, 'F1-E01', 'EV',      'Available'),
(1, 'F1-E02', 'EV',      'Available'),
(2, 'F2-C01', 'Compact', 'Available'),
(2, 'F2-C02', 'Compact', 'Available'),
(2, 'F2-S01', 'SUV',     'Available'),
(2, 'F2-E01', 'EV',      'Available');

INSERT INTO Vehicles (vehicle_no, owner_name, contact_number, vehicle_type, registration_category) VALUES
('DL-01-AB-1234', 'Rajesh Sharma',  '9811001122', 'Compact', 'Private'),
('UP-16-CD-5678', 'Priya Singh',    '9822334455', 'SUV',     'Private'),
('DL-03-EV-9999', 'Amit Verma',     '9877889900', 'EV',      'Private'),
('HR-26-EV-7777', 'Sneha Patel',    '9899112233', 'EV',      'Private'),
('DL-01-CAB-9999', 'Ramesh Yadav (Ola Driver)', '9876543210', 'Compact', 'Commercial'),
('DL-01-CAB-8888', 'Sunil Kumar (Uber Driver)', '9812345678', 'Compact', 'Commercial');

INSERT INTO Parking_Tickets (ticket_id, spot_id, vehicle_id, entry_time, exit_time, ticket_status)
VALUES (101, 1, 1, NOW() - INTERVAL 1 DAY - INTERVAL 2 HOUR, NOW() - INTERVAL 1 DAY, 'Completed');

INSERT INTO Billing (ticket_id, duration_hours, parking_fee, ev_fee, penalty_fee, total_amount, payment_status, bill_time)
VALUES (101, 2.00, 60.00, 0.00, 0.00, 60.00, 'Paid', NOW() - INTERVAL 1 DAY);

INSERT INTO Parking_Tickets (ticket_id, spot_id, vehicle_id, entry_time, exit_time, ticket_status)
VALUES (102, 3, 3, NOW() - INTERVAL 5 HOUR, NOW() - INTERVAL 2 HOUR, 'Completed');

INSERT INTO EV_Charging_Logs (ticket_id, kwh_consumed, charging_status, start_time, end_time)
VALUES (102, 15.50, 'Completed', NOW() - INTERVAL 5 HOUR, NOW() - INTERVAL 2 HOUR);

INSERT INTO Billing (ticket_id, duration_hours, parking_fee, ev_fee, penalty_fee, total_amount, payment_status, bill_time)
VALUES (102, 3.00, 120.00, 186.00, 0.00, 306.00, 'Paid', NOW() - INTERVAL 2 HOUR);

INSERT INTO Parking_Tickets (ticket_id, spot_id, vehicle_id, entry_time, ticket_status)
VALUES (100, 5, 5, NOW() - INTERVAL 14 HOUR, 'Active');
