CREATE TABLE tokens (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  identifier VARCHAR(255) NOT NULL,
  created_at DATETIME NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY tokens_identifier_unique (identifier)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
