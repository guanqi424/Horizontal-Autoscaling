package main

import (
	"fmt"
	"net/http"
	"strconv"
	"time"
)

func main() {
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(200)
		w.Write([]byte("work now is healthy!\n"))
	})

	// /work?ms=30  -> burn ~30ms CPU per request
	http.HandleFunc("/work", func(w http.ResponseWriter, r *http.Request) {
		ms := 30
		if v := r.URL.Query().Get("ms"); v != "" {
			if i, err := strconv.Atoi(v); err == nil && i >= 1 && i <= 5000 {
				ms = i
			}
		}
		burn(time.Duration(ms) * time.Millisecond)
		fmt.Fprintf(w, "worked %dms\n", ms)
	})

	http.ListenAndServe(":8081", nil)
}

func burn(d time.Duration) {
	end := time.Now().Add(d)
	x := 0.0001
	for time.Now().Before(end) {
		// meaningless math to keep CPU busy
		x = x*1.000001 + 0.0000001
		if x > 10 {
			x = 0.0001
		}
	}
}
