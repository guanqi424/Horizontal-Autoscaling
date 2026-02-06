package main

import (
	"fmt"
	"log"
	"net/http"
	"runtime"
	"strconv"
	"sync/atomic"
	"time"
)

// global state
var burning int32 // 0/1

func main() {
	mux := http.NewServeMux()

	mux.HandleFunc("/Healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(200)
		_, _ = w.Write([]byte("burn now is healthy!\n"))
	})

	// Start CPU burn:
	//   /burn?load=50&seconds=120
	// load is 0-100 (% busy time)
	mux.HandleFunc("/burn", func(w http.ResponseWriter, r *http.Request) {
		load := clamp(parseInt(r, "load", 50), 0, 100)
		secs := clamp(parseInt(r, "seconds", 120), 1, 3600)

		atomic.StoreInt32(&burning, 1)
		go burnFor(time.Duration(secs)*time.Second, load)

		fmt.Fprintf(w, "burning started: load=%d%% for %ds\n", load, secs)
	})

	// Stop burn:
	//   /stop
	mux.HandleFunc("/stop", func(w http.ResponseWriter, r *http.Request) {
		atomic.StoreInt32(&burning, 0)
		_, _ = w.Write([]byte("burning stopped\n"))
	})

	addr := ":8082"
	log.Printf("cpu-burner listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, mux))
}

func burnFor(d time.Duration, load int) {
	defer atomic.StoreInt32(&burning, 0)

	// One worker per GOMAXPROCS (often OK for container)
	n := runtime.GOMAXPROCS(0)
	period := 100 * time.Millisecond
	busy := time.Duration(load) * period / 100
	idle := period - busy

	end := time.Now().Add(d)

	// workers
	done := make(chan struct{})
	for i := 0; i < n; i++ {
		go func() {
			for {
				select {
				case <-done:
					return
				default:
				}

				if atomic.LoadInt32(&burning) == 0 {
					time.Sleep(50 * time.Millisecond)
					continue
				}

				start := time.Now()
				// busy loop
				for time.Since(start) < busy {
					// do some work
					_ = 3.1415926 * 2.7182818
				}
				if idle > 0 {
					time.Sleep(idle)
				}
			}
		}()
	}

	for time.Now().Before(end) && atomic.LoadInt32(&burning) == 1 {
		time.Sleep(200 * time.Millisecond)
	}
	close(done)
}

func parseInt(r *http.Request, key string, def int) int {
	v := r.URL.Query().Get(key)
	if v == "" {
		return def
	}
	i, err := strconv.Atoi(v)
	if err != nil {
		return def
	}
	return i
}

func clamp(x, lo, hi int) int {
	if x < lo {
		return lo
	}
	if x > hi {
		return hi
	}
	return x
}
