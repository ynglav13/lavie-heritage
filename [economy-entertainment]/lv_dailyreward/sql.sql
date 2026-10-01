CREATE TABLE IF NOT EXISTS `lv_daily_rewards` (
    `identifier` VARCHAR(80) NOT NULL,
    `streak` INT UNSIGNED NOT NULL DEFAULT 0,
    `last_claim_date` DATE DEFAULT NULL,
    `claimed_days` BIGINT UNSIGNED NOT NULL DEFAULT 0,
    `free_claimed_days` BIGINT UNSIGNED NOT NULL DEFAULT 0,
    `premium_claimed_days` BIGINT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`identifier`)
);

ALTER TABLE `lv_daily_rewards`
    ADD COLUMN IF NOT EXISTS `claimed_days` BIGINT UNSIGNED NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS `free_claimed_days` BIGINT UNSIGNED NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS `premium_claimed_days` BIGINT UNSIGNED NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS `lv_daily_reward_activity` (
    `identifier` VARCHAR(80) NOT NULL,
    `activity_date` DATE NOT NULL,
    `valid_minutes` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`identifier`, `activity_date`)
);
