DROP DATABASE IF EXISTS clinic_db;
CREATE DATABASE clinic_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE clinic_db;

-- Users / Staff (doctors, receptionists, admins)
CREATE TABLE users (
    user_id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    role ENUM('admin','doctor','nurse','receptionist') NOT NULL DEFAULT 'receptionist',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Doctors table (one-to-one with users when role='doctor' optionally)
CREATE TABLE doctors (
    doctor_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL UNIQUE,
    license_number VARCHAR(50) NOT NULL UNIQUE,
    bio TEXT,
    years_experience INT DEFAULT 0 CHECK (years_experience >= 0),
    active TINYINT(1) DEFAULT 1,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- Specialties (many doctors -> one specialty; and doctor_specialties for many-to-many)
CREATE TABLE specialties (
    specialty_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT
) ENGINE=InnoDB;

-- Many-to-many join: doctors <-> specialties
CREATE TABLE doctor_specialties (
    doctor_id INT NOT NULL,
    specialty_id INT NOT NULL,
    PRIMARY KEY (doctor_id, specialty_id),
    FOREIGN KEY (doctor_id) REFERENCES doctors(doctor_id) ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (specialty_id) REFERENCES specialties(specialty_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- Patients
CREATE TABLE patients (
    patient_id INT AUTO_INCREMENT PRIMARY KEY,
    national_id VARCHAR(50) UNIQUE,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    date_of_birth DATE,
    gender ENUM('male','female','other') DEFAULT 'other',
    phone VARCHAR(30),
    email VARCHAR(255),
    address VARCHAR(500),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Rooms (exam rooms)
CREATE TABLE rooms (
    room_id INT AUTO_INCREMENT PRIMARY KEY,
    room_number VARCHAR(20) NOT NULL UNIQUE,
    floor INT DEFAULT 1,
    notes VARCHAR(255)
) ENGINE=InnoDB;

-- Appointments (one-to-many: patient -> appointments; doctor -> appointments; room optional)
CREATE TABLE appointments (
    appointment_id INT AUTO_INCREMENT PRIMARY KEY,
    patient_id INT NOT NULL,
    doctor_id INT NOT NULL,
    room_id INT,
    appointment_start DATETIME NOT NULL,
    appointment_end DATETIME NOT NULL,
    status ENUM('scheduled','checked_in','completed','cancelled','no_show') DEFAULT 'scheduled',
    reason VARCHAR(500),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_time_order CHECK (appointment_end > appointment_start),
    FOREIGN KEY (patient_id) REFERENCES patients(patient_id) ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (doctor_id) REFERENCES doctors(doctor_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (room_id) REFERENCES rooms(room_id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- Medicines / Drugs
CREATE TABLE medicines (
    medicine_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    brand VARCHAR(150),
    unit VARCHAR(50) DEFAULT 'tablet',
    unique_code VARCHAR(100) UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Prescriptions (one prescription per appointment; doctor prescribes medicines)
CREATE TABLE prescriptions (
    prescription_id INT AUTO_INCREMENT PRIMARY KEY,
    appointment_id INT NOT NULL UNIQUE,
    prescribed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    notes TEXT,
    FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- Many-to-many: prescriptions <-> medicines (with dosage instructions)
CREATE TABLE prescription_items (
    prescription_id INT NOT NULL,
    medicine_id INT NOT NULL,
    dosage VARCHAR(200) NOT NULL, -- e.g., '1 tablet twice daily'
    duration_days INT CHECK (duration_days >= 0) DEFAULT 0,
    PRIMARY KEY (prescription_id, medicine_id),
    FOREIGN KEY (prescription_id) REFERENCES prescriptions(prescription_id) ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (medicine_id) REFERENCES medicines(medicine_id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- Billing: invoices per appointment (one-to-one)
CREATE TABLE invoices (
    invoice_id INT AUTO_INCREMENT PRIMARY KEY,
    appointment_id INT NOT NULL UNIQUE,
    issued_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    subtotal DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    tax DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    total DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    status ENUM('unpaid','paid','partially_paid','cancelled') DEFAULT 'unpaid',
    FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- Payments (one-to-many: invoice -> payments)
CREATE TABLE payments (
    payment_id INT AUTO_INCREMENT PRIMARY KEY,
    invoice_id INT NOT NULL,
    paid_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    amount DECIMAL(10,2) NOT NULL CHECK (amount >= 0),
    method ENUM('cash','card','insurance','mobile_money') DEFAULT 'cash',
    reference VARCHAR(255),
    FOREIGN KEY (invoice_id) REFERENCES invoices(invoice_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- Insurance providers (optional many-to-many with patients via policies)
CREATE TABLE insurance_providers (
    provider_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    contact_phone VARCHAR(50)
) ENGINE=InnoDB;

CREATE TABLE patient_policies (
    policy_id INT AUTO_INCREMENT PRIMARY KEY,
    patient_id INT NOT NULL,
    provider_id INT NOT NULL,
    policy_number VARCHAR(150) NOT NULL,
    valid_from DATE,
    valid_to DATE,
    UNIQUE(patient_id, provider_id, policy_number),
    FOREIGN KEY (patient_id) REFERENCES patients(patient_id) ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (provider_id) REFERENCES insurance_providers(provider_id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- Audit trail (lightweight): logs actions by users
CREATE TABLE audit_logs (
    log_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    action VARCHAR(255) NOT NULL,
    object_type VARCHAR(100),
    object_id VARCHAR(100),
    details TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- Indexes to improve common queries
CREATE INDEX idx_appointments_doctor_time ON appointments(doctor_id, appointment_start);
CREATE INDEX idx_appointments_patient_time ON appointments(patient_id, appointment_start);

-- Sample triggers (optional): enforce business rule - prevent overlapping appointments for same doctor
DELIMITER $$
CREATE TRIGGER trg_appointments_no_overlap BEFORE INSERT ON appointments
FOR EACH ROW
BEGIN
    IF EXISTS (
        SELECT 1 FROM appointments a
        WHERE a.doctor_id = NEW.doctor_id
          AND a.status <> 'cancelled'
          AND NOT (NEW.appointment_end <= a.appointment_start OR NEW.appointment_start >= a.appointment_end)
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Doctor has a conflicting appointment in that time range.';
    END IF;
END$$

CREATE TRIGGER trg_appointments_no_overlap_update BEFORE UPDATE ON appointments
FOR EACH ROW
BEGIN
    IF EXISTS (
        SELECT 1 FROM appointments a
        WHERE a.doctor_id = NEW.doctor_id
          AND a.appointment_id <> NEW.appointment_id
          AND a.status <> 'cancelled'
          AND NOT (NEW.appointment_end <= a.appointment_start OR NEW.appointment_start >= a.appointment_end)
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Doctor has a conflicting appointment in that time range.';
    END IF;
END$$
DELIMITER ;