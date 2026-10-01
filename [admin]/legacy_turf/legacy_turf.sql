CREATE TABLE IF NOT EXISTS `legacy_turf_zones` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `name` VARCHAR(64) NOT NULL,
    `shape` VARCHAR(16) NOT NULL,
    `center_x` DOUBLE NULL,
    `center_y` DOUBLE NULL,
    `center_z` DOUBLE NULL,
    `radius` DOUBLE NULL,
    `points` LONGTEXT NULL,
    `color` SMALLINT UNSIGNED NOT NULL DEFAULT 3,
    `allow_vehicles` TINYINT(1) NOT NULL DEFAULT 1,
    `created_by` VARCHAR(191) NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_legacy_turf_zones_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
