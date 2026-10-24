package main

import (
	"github.com/valyala/fasthttp"
)

var jsonBytes = []byte(`{"message":"Hello from FastHTTP","status":"ok"}`)

func requestHandler(ctx *fasthttp.RequestCtx) {
	switch string(ctx.Path()) {
	case "/json":
		ctx.SetContentType("application/json; charset=utf-8")
		ctx.SetBody(jsonBytes)
	case "/plaintext":
		ctx.SetContentType("text/plain; charset=utf-8")
		ctx.SetBodyString("Hello World")
	default:
		ctx.Error("Not Found", fasthttp.StatusNotFound)
	}
}

func main() {
	_ = fasthttp.ListenAndServe(":8092", requestHandler)
}
