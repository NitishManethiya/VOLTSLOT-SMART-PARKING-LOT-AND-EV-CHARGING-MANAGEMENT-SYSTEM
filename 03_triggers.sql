USE VoltParkDB;

DROP TRIGGER IF EXISTS trg_auto_occupy_spot;
DROP TRIGGER IF EXISTS trg_auto_free_spot;

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

DELIMITER ;
