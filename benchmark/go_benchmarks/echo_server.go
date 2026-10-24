package main

import (
	"net/http"
	"github.com/labstack/echo/v4"
)

var jsonBytes = []byte(`{"message":"Hello from Echo","status":"ok"}`)

func main() {
	e := echo.New()
	e.HideBanner = true
	e.HidePort = true

	e.GET("/json", func(c echo.Context) error {
		return c.Blob(http.StatusOK, "application/json; charset=utf-8", jsonBytes)
	})

	e.GET("/plaintext", func(c echo.Context) error {
		return c.String(http.StatusOK, "Hello World")
	})

	_ = e.Start(":8094")
}
