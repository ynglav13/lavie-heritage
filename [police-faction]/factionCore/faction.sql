CREATE TABLE IF NOT EXISTS `faction` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `type` longtext DEFAULT NULL,
  `tag` longtext DEFAULT NULL,
  `category` longtext DEFAULT NULL,
  `colour` longtext DEFAULT '255, 255, 255',
  `image` longtext DEFAULT '',
  `name` longtext DEFAULT NULL,
  `rank` longtext DEFAULT '[]',
  `division` longtext DEFAULT '[]',
  `permission` longtext DEFAULT '[]',
  `locker` longtext DEFAULT '[]',
  `garage` longtext DEFAULT '[]',
  `data` longtext DEFAULT '[{"owner":"Cartier Kentral", "orderPoint":0, "buyPoint":0}]',
  `items` longtext DEFAULT '[]',
  `budget` int(11) NOT NULL DEFAULT 0,
  `sirenbox` varchar(50) DEFAULT 'SmartControllerB',
  `reserved_budget` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`) USING BTREE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `faction_vehicles` (
  `identifier` varchar(50) DEFAULT NULL,
  `name` varchar(50) DEFAULT NULL,
  `type` varchar(50) DEFAULT NULL,
  `plate` varchar(50) NOT NULL,
  `status` int(11) DEFAULT 0,
  `colour` longtext DEFAULT NULL,
  `lastDriver` varchar(50) DEFAULT NULL,
  `glovebox` longtext DEFAULT NULL,
  `trunk` longtext DEFAULT NULL,
  PRIMARY KEY (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE `users` ADD COLUMN IF NOT EXISTS `faction` longtext DEFAULT '{"name":"Không có","rank":0,"division":0}';
