-- Run once during a maintenance window before restarting av_alpr.

SET @av_alpr_has_fakeplate_index = (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'owned_vehicles'
      AND index_name = 'idx_owned_vehicles_fakeplate'
);
SET @av_alpr_fakeplate_sql = IF(
    @av_alpr_has_fakeplate_index = 0,
    'ALTER TABLE `owned_vehicles` ADD INDEX `idx_owned_vehicles_fakeplate` (`fakeplate`)',
    'SELECT 1'
);
PREPARE av_alpr_fakeplate_stmt FROM @av_alpr_fakeplate_sql;
EXECUTE av_alpr_fakeplate_stmt;
DEALLOCATE PREPARE av_alpr_fakeplate_stmt;

SET @av_alpr_has_ticket_index = (
    SELECT COUNT(*)
    FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'police_tickets'
      AND index_name = 'idx_police_tickets_target_status_due'
);
SET @av_alpr_ticket_sql = IF(
    @av_alpr_has_ticket_index = 0,
    'ALTER TABLE `police_tickets` ADD INDEX `idx_police_tickets_target_status_due` (`target_identifier`, `status`, `due_at`)',
    'SELECT 1'
);
PREPARE av_alpr_ticket_stmt FROM @av_alpr_ticket_sql;
EXECUTE av_alpr_ticket_stmt;
DEALLOCATE PREPARE av_alpr_ticket_stmt;
