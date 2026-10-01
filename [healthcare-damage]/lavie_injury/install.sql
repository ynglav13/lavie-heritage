ALTER TABLE `users`
ADD COLUMN IF NOT EXISTS `injury_status` varchar(255) DEFAULT NULL,
ADD COLUMN IF NOT EXISTS `bodydamages` longtext DEFAULT NULL;
