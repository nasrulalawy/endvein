package main

import (
	"fmt"
	"net/http"
)

var jsonBytes = []byte(`{"message":"Hello from Go","status":"ok"}`)

func main() {
	mux := http.NewServeMux()

	mux.HandleFunc("/json", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Content-Length", fmt.Sprintf("%d", len(jsonBytes)))
		w.WriteHeader(http.StatusOK)
		w.Write(jsonBytes)
	})

	mux.HandleFunc("/plaintext", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("Hello World"))
	})

	fmt.Println("Go server listening on http://127.0.0.1:8082")
	if err := http.ListenAndServe("127.0.0.1:8082", mux); err != nil {
		panic(err)
	}
}
