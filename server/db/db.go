package db

import (
	"database/sql"
	"log"
	"os"
	"path/filepath"

	"github.com/yourname/chat-platform/config"
	_ "modernc.org/sqlite"
)

var DB *sql.DB

func Init() {
	dir := filepath.Dir(config.C.DBPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		log.Fatalf("failed to create db dir: %v", err)
	}

	var err error
	DB, err = sql.Open("sqlite", config.C.DBPath+"?_journal_mode=WAL&_foreign_keys=on")
	if err != nil {
		log.Fatalf("failed to open db: %v", err)
	}

	if err = DB.Ping(); err != nil {
		log.Fatalf("failed to ping db: %v", err)
	}

	migrate()
}

func migrate() {
	schema := `
	CREATE TABLE IF NOT EXISTS users (
		id          INTEGER PRIMARY KEY AUTOINCREMENT,
		username    TEXT    NOT NULL UNIQUE,
		password    TEXT    NOT NULL,
		role        TEXT    NOT NULL DEFAULT 'user',
		status      TEXT    NOT NULL DEFAULT 'active',
		created_at  DATETIME DEFAULT CURRENT_TIMESTAMP
	);

	CREATE TABLE IF NOT EXISTS messages (
		id          INTEGER PRIMARY KEY AUTOINCREMENT,
		user_id     INTEGER NOT NULL,
		username    TEXT    NOT NULL,
		type        TEXT    NOT NULL DEFAULT 'text',
		content     TEXT    NOT NULL,
		file_name   TEXT,
		file_size   INTEGER,
		created_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
		FOREIGN KEY (user_id) REFERENCES users(id)
	);

	CREATE TABLE IF NOT EXISTS files (
		id            INTEGER PRIMARY KEY AUTOINCREMENT,
		stored_name   TEXT    NOT NULL UNIQUE,
		original_name TEXT    NOT NULL,
		size          INTEGER NOT NULL,
		expired       INTEGER NOT NULL DEFAULT 0,
		created_at    DATETIME DEFAULT CURRENT_TIMESTAMP
	);

	CREATE TABLE IF NOT EXISTS invite_codes (
		id          INTEGER PRIMARY KEY AUTOINCREMENT,
		code        TEXT    NOT NULL UNIQUE,
		created_by  INTEGER NOT NULL,
		used_by     INTEGER,
		created_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
		FOREIGN KEY (created_by) REFERENCES users(id),
		FOREIGN KEY (used_by)    REFERENCES users(id)
	);

	CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at);
	CREATE INDEX IF NOT EXISTS idx_invite_codes_code   ON invite_codes(code);
	CREATE INDEX IF NOT EXISTS idx_files_created_at    ON files(created_at);
	`
	if _, err := DB.Exec(schema); err != nil {
		log.Fatalf("migration failed: %v", err)
	}
}
