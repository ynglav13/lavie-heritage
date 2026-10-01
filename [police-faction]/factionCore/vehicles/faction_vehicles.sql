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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
