CREATE TABLE IF NOT EXISTS `player_weapon_anims` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `identifier` VARCHAR(60) NOT NULL,
  `weapongroup` VARCHAR(50) NOT NULL,
  `animkey` VARCHAR(50) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_player_weapon` (`identifier`, `weapongroup`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
