CREATE TABLE IF NOT EXISTS `prime_accounts` (
    `steam_hex` VARCHAR(60) NOT NULL,
    `prime_expiry` DATETIME DEFAULT NULL,
    `prime_type` VARCHAR(20) NOT NULL DEFAULT 'prime',
    `created_at` TIMESTAMP DEFAULT current_timestamp(),
    `updated_at` TIMESTAMP DEFAULT current_timestamp() ON UPDATE current_timestamp(),
    PRIMARY KEY (`steam_hex`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE `prime_accounts`
ADD COLUMN IF NOT EXISTS `prime_type` VARCHAR(20) NOT NULL DEFAULT 'prime'
AFTER `prime_expiry`;
