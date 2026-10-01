CREATE TABLE IF NOT EXISTS `lv_rental_stations` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `code` VARCHAR(64) NOT NULL,
    `label` VARCHAR(100) NOT NULL,
    `coords` LONGTEXT NOT NULL,
    `heading` FLOAT NOT NULL DEFAULT 0,
    `enabled` TINYINT(1) NOT NULL DEFAULT 1,
    `blip` TINYINT(1) NOT NULL DEFAULT 1,
    `max_hours` INT NOT NULL DEFAULT 6,
    `deposit` INT NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uniq_code` (`code`)
);

CREATE TABLE IF NOT EXISTS `lv_rental_spawns` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `station_id` INT UNSIGNED NOT NULL,
    `coords` LONGTEXT NOT NULL,
    `heading` FLOAT NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    KEY `idx_station_id` (`station_id`)
);

CREATE TABLE IF NOT EXISTS `lv_rental_vehicles` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `station_id` INT UNSIGNED NOT NULL,
    `model` VARCHAR(60) NOT NULL,
    `label` VARCHAR(100) NOT NULL,
    `price_per_hour` INT NOT NULL DEFAULT 0,
    `deposit` INT NOT NULL DEFAULT 0,
    `image` VARCHAR(255) DEFAULT '',
    `enabled` TINYINT(1) NOT NULL DEFAULT 1,
    PRIMARY KEY (`id`),
    KEY `idx_station_id` (`station_id`)
);

CREATE TABLE IF NOT EXISTS `lv_rental_active` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(80) NOT NULL,
    `player_name` VARCHAR(100) NOT NULL,
    `station_id` INT UNSIGNED NOT NULL,
    `vehicle_id` INT UNSIGNED NOT NULL,
    `model` VARCHAR(60) NOT NULL,
    `plate` VARCHAR(12) NOT NULL,
    `net_id` INT DEFAULT NULL,
    `entity` INT DEFAULT NULL,
    `spawn_coords` LONGTEXT DEFAULT NULL,
    `hours` INT NOT NULL,
    `price_paid` INT NOT NULL,
    `deposit_paid` INT NOT NULL,
    `rented_at` INT NOT NULL,
    `expires_at` INT NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uniq_plate` (`plate`),
    KEY `idx_identifier` (`identifier`),
    KEY `idx_expires_at` (`expires_at`)
);

DROP TABLE IF EXISTS `lv_rental_logs`;
