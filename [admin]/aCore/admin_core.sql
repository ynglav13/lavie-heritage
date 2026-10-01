CREATE TABLE IF NOT EXISTS `admin_levels` (
    `identifier` varchar(60) NOT NULL,
    `level` int(2) NOT NULL DEFAULT 0,
    `name` VARCHAR(50) NOT NULL,
    `added_by` VARCHAR(50) DEFAULT 'console',
    `rank_name` VARCHAR(64) DEFAULT NULL,
    `rank_color` VARCHAR(10) DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `admin_bans` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `identifier` varchar(60) NOT NULL,
    `name` varchar(50) DEFAULT NULL,
    `reason` text NOT NULL,
    `banned_by` varchar(60) NOT NULL,
    `banned_by_name` varchar(50) DEFAULT NULL,
    `ban_duration` int(11) DEFAULT NULL COMMENT 'Phút, NULL = vĩnh viễn',
    `expire_at` datetime DEFAULT NULL,
    `unbanned_by` varchar(60) DEFAULT NULL,
    `active` tinyint(1) NOT NULL DEFAULT 1,
    `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_identifier` (`identifier`),
    KEY `idx_active` (`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `admin_warns` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `identifier` varchar(60) NOT NULL,
    `name` varchar(50) DEFAULT NULL,
    `reason` text NOT NULL,
    `warned_by` varchar(60) NOT NULL,
    `warned_by_name` varchar(50) DEFAULT NULL,
    `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DROP TABLE IF EXISTS `admin_logs`;

CREATE TABLE IF NOT EXISTS `admin_jails` (
    `identifier` varchar(60) NOT NULL,
    `reason` text DEFAULT NULL,
    `jailer` varchar(60) DEFAULT NULL,
    `expire_at` int(11) NOT NULL,
    `release_coords` varchar(255) DEFAULT NULL,
    `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

