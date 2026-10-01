CREATE TABLE IF NOT EXISTS `lv_gacha_state` (
  `identifier` varchar(80) NOT NULL,
  `banner` varchar(50) NOT NULL,
  `pity` int unsigned NOT NULL DEFAULT 0,
  `total_spins` int unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`identifier`, `banner`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `lv_gacha_history` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `identifier` varchar(80) NOT NULL,
  `banner` varchar(50) NOT NULL,
  `reward_id` varchar(80) NOT NULL,
  `reward_name` varchar(120) NOT NULL,
  `reward_type` varchar(20) NOT NULL,
  `rarity` varchar(20) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_gacha_history_player` (`identifier`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


['gacha_crate'] = {
        label = 'Crate',
        weight = 800,
        stack = true,
        close = true,
        consume = 0,
        client = {
            export = 'lv_gacha.openCase'
        }
    },

['gacha_key'] = {
        label = 'Key',
        weight = 50,
        stack = true,
        close = true,
        consume = 0
    },
