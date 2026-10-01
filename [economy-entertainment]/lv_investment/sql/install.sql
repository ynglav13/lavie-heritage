CREATE TABLE IF NOT EXISTS investment_contracts (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    identifier VARCHAR(80) NOT NULL,
    package_id VARCHAR(40) NOT NULL,
    principal INT UNSIGNED NOT NULL,
    payout INT UNSIGNED NOT NULL,
    required_minutes INT UNSIGNED NOT NULL,
    active_minutes INT UNSIGNED NOT NULL DEFAULT 0,
    status ENUM('active','completed','claimed','cancelled','frozen') NOT NULL DEFAULT 'active',
    started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP NULL DEFAULT NULL,
    claimed_at TIMESTAMP NULL DEFAULT NULL,
    cancelled_at TIMESTAMP NULL DEFAULT NULL,
    PRIMARY KEY (id),
    INDEX idx_investment_owner (identifier, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS investment_logs (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    contract_id BIGINT UNSIGNED NULL,
    identifier VARCHAR(80) NOT NULL,
    player_name VARCHAR(100) NULL,
    action VARCHAR(40) NOT NULL,
    amount INT NOT NULL DEFAULT 0,
    metadata JSON NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    INDEX idx_investment_log_owner (identifier, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS investment_activity_daily (
    contract_id BIGINT UNSIGNED NOT NULL,
    activity_date DATE NOT NULL,
    valid_minutes INT UNSIGNED NOT NULL DEFAULT 0,
    afk_minutes INT UNSIGNED NOT NULL DEFAULT 0,
    suspicious_minutes INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (contract_id, activity_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
