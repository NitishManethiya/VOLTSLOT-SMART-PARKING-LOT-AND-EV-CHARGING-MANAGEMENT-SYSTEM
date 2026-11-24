USE VoltParkDB;

CREATE INDEX idx_vehicle_no ON Vehicles(vehicle_no);

CREATE INDEX idx_ticket_status ON Parking_Tickets(ticket_status);
