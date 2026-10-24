package main

import (
	"net/http"
	"github.com/gin-gonic/gin"
)

var jsonBytes = []byte(`{"message":"Hello from Gin","status":"ok"}`)

func main() {
	gin.SetMode(gin.ReleaseMode)
	r := gin.New()

	r.GET("/json", func(c *gin.Context) {
		c.Data(http.StatusOK, "application/json; charset=utf-8", jsonBytes)
	})

	r.GET("/plaintext", func(c *gin.Context) {
		c.String(http.StatusOK, "Hello World")
	})

	_ = r.Run(":8093")
}
