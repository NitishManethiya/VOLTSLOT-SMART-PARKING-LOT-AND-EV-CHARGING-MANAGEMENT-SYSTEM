CREATE DATABASE IF NOT EXISTS VoltParkDB;
USE VoltParkDB;

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
    vehicle_type ENUM('Compact', 'SUV', 'EV') NOT NULL
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
    total_amount DECIMAL(8, 2) NOT NULL,
    payment_status ENUM('Paid', 'Pending') NOT NULL DEFAULT 'Pending',
    bill_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_billing_ticket FOREIGN KEY (ticket_id) 
        REFERENCES Parking_Tickets(ticket_id) ON DELETE CASCADE
) ENGINE=InnoDB;
