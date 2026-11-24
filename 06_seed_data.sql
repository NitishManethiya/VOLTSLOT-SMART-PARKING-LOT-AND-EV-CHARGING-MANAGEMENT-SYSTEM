USE VoltParkDB;

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

INSERT INTO Vehicles (vehicle_no, owner_name, contact_number, vehicle_type) VALUES
('DL-01-AB-1234', 'Rajesh Sharma',  '9811001122', 'Compact'),
('UP-16-CD-5678', 'Priya Singh',    '9822334455', 'SUV'),
('DL-03-EV-9999', 'Amit Verma',     '9877889900', 'EV'),
('HR-26-EV-7777', 'Sneha Patel',    '9899112233', 'EV'),
('UP-14-XY-4321', 'Vikram Mehta',   '9844556677', 'Compact');

INSERT INTO Parking_Tickets (ticket_id, spot_id, vehicle_id, entry_time, exit_time, ticket_status)
VALUES (101, 1, 1, NOW() - INTERVAL 1 DAY - INTERVAL 2 HOUR, NOW() - INTERVAL 1 DAY, 'Completed');

INSERT INTO Billing (ticket_id, duration_hours, parking_fee, ev_fee, total_amount, payment_status, bill_time)
VALUES (101, 2.00, 60.00, 0.00, 60.00, 'Paid', NOW() - INTERVAL 1 DAY);

INSERT INTO Parking_Tickets (ticket_id, spot_id, vehicle_id, entry_time, exit_time, ticket_status)
VALUES (102, 3, 3, NOW() - INTERVAL 5 HOUR, NOW() - INTERVAL 2 HOUR, 'Completed');

INSERT INTO EV_Charging_Logs (ticket_id, kwh_consumed, charging_status, start_time, end_time)
VALUES (102, 15.50, 'Completed', NOW() - INTERVAL 5 HOUR, NOW() - INTERVAL 2 HOUR);

INSERT INTO Billing (ticket_id, duration_hours, parking_fee, ev_fee, total_amount, payment_status, bill_time)
VALUES (102, 3.00, 120.00, 186.00, 306.00, 'Paid', NOW() - INTERVAL 2 HOUR);
