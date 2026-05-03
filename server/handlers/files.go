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
)

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

	c.JSON(http.StatusOK, gin.H{
		"file_id":       storedName,
		"original_name": originalName,
		"size":          written,
	})
}

func DownloadFile(c *gin.Context) {
	filename := filepath.Base(c.Param("filename"))
	if filename == "." || filename == "/" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid filename"})
		return
	}

	filePath := filepath.Join(config.C.UploadDir, filename)
	if _, err := os.Stat(filePath); os.IsNotExist(err) {
		c.JSON(http.StatusNotFound, gin.H{"error": "file not found"})
		return
	}

	c.File(filePath)
}
