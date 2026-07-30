CREATE TABLE IF NOT EXISTS `renewed_bank_schema_migrations` (
  `version` VARCHAR(64) NOT NULL,
  `applied_at` TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`version`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `renewed_bank_accounts` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `account_key` VARCHAR(64) NOT NULL,
  `display_name` VARCHAR(96) NOT NULL,
  `account_type` VARCHAR(16) NOT NULL,
  `owner_identifier` VARCHAR(80) DEFAULT NULL,
  `currency` CHAR(3) NOT NULL DEFAULT 'USD',
  `balance` BIGINT NOT NULL DEFAULT 0,
  `status` VARCHAR(24) NOT NULL DEFAULT 'active',
  `version` BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `metadata` LONGTEXT DEFAULT NULL,
  `created_at` TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  `closed_at` TIMESTAMP(3) NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_renewed_bank_account_key` (`account_key`),
  KEY `idx_renewed_bank_account_owner` (`owner_identifier`),
  KEY `idx_renewed_bank_account_type_status` (`account_type`, `status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `renewed_bank_account_members` (
  `account_id` BIGINT UNSIGNED NOT NULL,
  `member_identifier` VARCHAR(80) NOT NULL,
  `role` VARCHAR(16) NOT NULL,
  `added_by` VARCHAR(80) DEFAULT NULL,
  `created_at` TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`account_id`, `member_identifier`),
  KEY `idx_renewed_bank_member_identifier` (`member_identifier`, `account_id`),
  CONSTRAINT `fk_renewed_bank_member_account` FOREIGN KEY (`account_id`) REFERENCES `renewed_bank_accounts` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `renewed_bank_personal_status` (
  `identifier` VARCHAR(80) NOT NULL,
  `is_frozen` TINYINT(1) NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`identifier`),
  KEY `idx_renewed_bank_personal_frozen` (`is_frozen`, `updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `renewed_bank_transactions` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `group_id` VARCHAR(80) NOT NULL,
  `request_id` VARCHAR(80) NOT NULL,
  `account_id` BIGINT UNSIGNED DEFAULT NULL,
  `personal_identifier` VARCHAR(80) DEFAULT NULL,
  `direction` VARCHAR(8) NOT NULL,
  `transaction_type` VARCHAR(32) NOT NULL,
  `amount` BIGINT NOT NULL,
  `balance_before` BIGINT DEFAULT NULL,
  `balance_after` BIGINT DEFAULT NULL,
  `actor_identifier` VARCHAR(80) DEFAULT NULL,
  `counterparty_ref` VARCHAR(96) DEFAULT NULL,
  `description` VARCHAR(255) DEFAULT NULL,
  `metadata` LONGTEXT DEFAULT NULL,
  `created_at` TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_renewed_bank_tx_account_cursor` (`account_id`, `id`),
  KEY `idx_renewed_bank_tx_personal_cursor` (`personal_identifier`, `id`),
  KEY `idx_renewed_bank_tx_group` (`group_id`),
  KEY `idx_renewed_bank_tx_created` (`created_at`),
  KEY `idx_renewed_bank_tx_request` (`request_id`),
  CONSTRAINT `fk_renewed_bank_tx_account` FOREIGN KEY (`account_id`) REFERENCES `renewed_bank_accounts` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `renewed_bank_idempotency` (
  `scope_key` VARCHAR(128) NOT NULL,
  `request_id` VARCHAR(80) NOT NULL,
  `operation` VARCHAR(32) NOT NULL,
  `payload_hash` VARCHAR(32) NOT NULL,
  `status` VARCHAR(16) NOT NULL,
  `response` LONGTEXT DEFAULT NULL,
  `created_at` TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  `expires_at` TIMESTAMP(3) NULL DEFAULT NULL,
  PRIMARY KEY (`scope_key`, `request_id`),
  KEY `idx_renewed_bank_idempotency_expiry` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `renewed_bank_settlements` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `group_id` VARCHAR(80) NOT NULL,
  `framework` VARCHAR(16) NOT NULL,
  `identifier` VARCHAR(80) NOT NULL,
  `money_type` VARCHAR(16) NOT NULL,
  `direction` VARCHAR(8) NOT NULL,
  `amount` BIGINT NOT NULL,
  `status` VARCHAR(24) NOT NULL,
  `attempts` INT UNSIGNED NOT NULL DEFAULT 0,
  `last_error` VARCHAR(255) DEFAULT NULL,
  `metadata` LONGTEXT DEFAULT NULL,
  `created_at` TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_renewed_bank_settlement_group_direction` (`group_id`, `identifier`, `direction`),
  KEY `idx_renewed_bank_settlement_status` (`status`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `renewed_bank_audit_events` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `event_type` VARCHAR(48) NOT NULL,
  `actor_identifier` VARCHAR(80) DEFAULT NULL,
  `account_id` BIGINT UNSIGNED DEFAULT NULL,
  `reason` VARCHAR(255) DEFAULT NULL,
  `metadata` LONGTEXT DEFAULT NULL,
  `created_at` TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_renewed_bank_audit_account` (`account_id`, `id`),
  KEY `idx_renewed_bank_audit_type` (`event_type`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
