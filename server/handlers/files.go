package handlers

import (
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/yourname/chat-platform/config"
	"github.com/yourname/chat-platform/db"
)

const maxFileCount = 50

func UploadFile(c *gin.Context) {
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, config.C.MaxFileSizeMB<<20)

	file, header, err := c.Request.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "file required (max 10MB)"})
		return
	}
	defer file.Close()

	if header.Size > config.C.MaxFileSizeMB<<20 {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("file too large, max %dMB", config.C.MaxFileSizeMB)})
		return
	}

	// Sanitize filename
	originalName := filepath.Base(header.Filename)
	ext := strings.ToLower(filepath.Ext(originalName))

	// Generate unique stored name
	storedName := fmt.Sprintf("%d_%s%s", time.Now().UnixNano(), generateCode(), ext)
	destPath := filepath.Join(config.C.UploadDir, storedName)

	if err := os.MkdirAll(config.C.UploadDir, 0755); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "storage error"})
		return
	}

	dst, err := os.Create(destPath)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "storage error"})
		return
	}
	defer dst.Close()

	buf := make([]byte, 32*1024)
	written := int64(0)
	for {
		n, readErr := file.Read(buf)
		if n > 0 {
			written += int64(n)
			if written > config.C.MaxFileSizeMB<<20 {
				dst.Close()
				os.Remove(destPath)
				c.JSON(http.StatusBadRequest, gin.H{"error": "file too large"})
				return
			}
			dst.Write(buf[:n])
		}
		if readErr != nil {
			break
		}
	}

	// Insert into files table
	_, err = db.DB.Exec(
		`INSERT INTO files (stored_name, original_name, size) VALUES (?, ?, ?)`,
		storedName, originalName, written,
	)
	if err != nil {
		os.Remove(destPath)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	// Enforce max file count: expire oldest files beyond limit
	go expireOldFiles()

	c.JSON(http.StatusOK, gin.H{
		"file_id":       storedName,
		"original_name": originalName,
		"size":          written,
	})
}

// expireOldFiles marks the oldest files as expired and deletes them from disk
// when the total count exceeds maxFileCount.
func expireOldFiles() {
	// Count non-expired files
	var count int
	db.DB.QueryRow(`SELECT COUNT(*) FROM files WHERE expired = 0`).Scan(&count)
	if count <= maxFileCount {
		return
	}

	// Find files to expire (oldest first, keep newest maxFileCount)
	excess := count - maxFileCount
	rows, err := db.DB.Query(
		`SELECT id, stored_name FROM files WHERE expired = 0 ORDER BY created_at ASC LIMIT ?`,
		excess,
	)
	if err != nil {
		return
	}
	defer rows.Close()

	type toExpire struct {
		id         int64
		storedName string
	}
	var targets []toExpire
	for rows.Next() {
		var t toExpire
		rows.Scan(&t.id, &t.storedName)
		targets = append(targets, t)
	}
	rows.Close()

	for _, t := range targets {
		// Mark expired in DB
		db.DB.Exec(`UPDATE files SET expired = 1 WHERE id = ?`, t.id)
		// Delete from disk
		os.Remove(filepath.Join(config.C.UploadDir, t.storedName))
	}
}

func DownloadFile(c *gin.Context) {
	filename := filepath.Base(c.Param("filename"))
	if filename == "." || filename == "/" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid filename"})
		return
	}

	// Check files table for expiry status
	var expired int
	err := db.DB.QueryRow(
		`SELECT expired FROM files WHERE stored_name = ?`, filename,
	).Scan(&expired)
	if err != nil {
		// Not in files table (legacy file) — fall through to disk check
		filePath := filepath.Join(config.C.UploadDir, filename)
		if _, err2 := os.Stat(filePath); os.IsNotExist(err2) {
			c.JSON(http.StatusNotFound, gin.H{"error": "file not found"})
			return
		}
		c.File(filePath)
		return
	}

	if expired == 1 {
		c.JSON(http.StatusGone, gin.H{"error": "file_expired"})
		return
	}

	filePath := filepath.Join(config.C.UploadDir, filename)
	if _, err := os.Stat(filePath); os.IsNotExist(err) {
		c.JSON(http.StatusNotFound, gin.H{"error": "file not found"})
		return
	}
	c.File(filePath)
}
