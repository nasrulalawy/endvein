package main

import (
	"github.com/gofiber/fiber/v2"
)

func main() {
	app := fiber.New(fiber.Config{
		DisableStartupMessage: true,
	})

	jsonBytes := []byte(`{"message":"Hello from Fiber","status":"ok"}`)

	app.Get("/json", func(c *fiber.Ctx) error {
		c.Set("Content-Type", "application/json; charset=utf-8")
		return c.Send(jsonBytes)
	})

	app.Get("/plaintext", func(c *fiber.Ctx) error {
		return c.SendString("Hello World")
	})

	_ = app.Listen(":8091")
}
