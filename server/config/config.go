package config

import (
	"os"
	"strconv"
)

type Config struct {
	Port          string
	JWTSecret     string
	DBPath        string
	UploadDir     string
	MaxFileSizeMB int64
	HistoryLimit  int
}

var C Config

func Load() {
	C = Config{
		Port:          getEnv("PORT", "8080"),
		JWTSecret:     getEnv("JWT_SECRET", "change_me_please"),
		DBPath:        getEnv("DB_PATH", "./data/chat.db"),
		UploadDir:     getEnv("UPLOAD_DIR", "./data/uploads"),
		MaxFileSizeMB: getEnvInt64("MAX_FILE_SIZE_MB", 10),
		HistoryLimit:  getEnvInt("HISTORY_LIMIT", 50),
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func getEnvInt(key string, fallback int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return fallback
}

func getEnvInt64(key string, fallback int64) int64 {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.ParseInt(v, 10, 64); err == nil {
			return n
		}
	}
	return fallback
}
