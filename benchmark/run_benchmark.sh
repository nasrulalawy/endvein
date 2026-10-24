#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUESTS=50000
CONCURRENCY=100

echo "=========================================================="
echo "          ENDVEIN vs SINGLE-ISOLATE DART vs GO            "
echo "  Hardware: 10 CPU Cores (macOS Apple Silicon)            "
echo "  Benchmark: $REQUESTS requests with $CONCURRENCY concurrency   "
echo "=========================================================="

run_bench() {
  local name="$1"
  local bin="$2"
  local port="$3"
  local url="http://127.0.0.1:$port/json"

  echo ""
  echo ">>> [Testing $name] Starting binary: $bin on port $port..."
  "$bin" > /dev/null 2>&1 &
  local pid=$!
  sleep 1.5

  # Warmup
  ab -n 1000 -c 10 -k "$url" > /dev/null 2>&1 || true

  echo ">>> [Testing $name] Running benchmark ($REQUESTS requests)..."
  local output
  output=$(ab -n "$REQUESTS" -c "$CONCURRENCY" -k "$url" 2>&1)
  
  # Kill process cleanly
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  sleep 0.5

  local rps
  rps=$(echo "$output" | grep "Requests per second:" | awk '{print $4}')
  local latency
  latency=$(echo "$output" | grep "Time per request:" | head -n 1 | awk '{print $4}')
  
  echo ">>> [$name Results]"
  echo "    Requests/sec : $rps req/s"
  echo "    Mean Latency : $latency ms"
}

run_bench "Traditional Dart (Single Isolate)" "$DIR/single_bin" 8081
run_bench "Endvein (10-Isolate Native Cluster)" "$DIR/endvein_bin" 8080
run_bench "Go (Standard Library net/http)" "$DIR/go_bin" 8082

echo ""
echo "=========================================================="
echo "                     BENCHMARK COMPLETE                   "
echo "=========================================================="
