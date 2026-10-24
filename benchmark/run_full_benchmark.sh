#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUESTS=50000
CONCURRENCY=100

echo "=========================================================================="
echo "          ENDVEIN vs DART FROG vs SERVERPOD vs GO BENCHMARK               "
echo "  Hardware : Apple Silicon (10 CPU Cores, macOS arm64)                    "
echo "  Workload : $REQUESTS requests with concurrency $CONCURRENCY (Keep-Alive)"
echo "  Mode     : Production AOT Native Binaries                               "
echo "=========================================================================="

run_bench() {
  local name="$1"
  local bin="$2"
  local port="$3"
  local url="http://127.0.0.1:$port/json"

  echo ""
  echo ">>> [Testing $name] Starting binary on port $port..."
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
  echo "    Throughput   : $rps req/s"
  echo "    Mean Latency : $latency ms"
}

run_bench "1. Dart Frog (Shelf Architecture)" "$DIR/dart_frog_bin" 8085
run_bench "2. Serverpod (RPC & Session Arch)" "$DIR/serverpod_bin" 8086
run_bench "3. Traditional Dart (HttpServer)" "$DIR/single_bin" 8081
run_bench "4. Go Standard Library (net/http)" "$DIR/go_bin" 8082
run_bench "5. ⚡ Endvein (10-Core Native Cluster)" "$DIR/endvein_bin" 8084

echo ""
echo "=========================================================================="
echo "                     BENCHMARK COMPLETE                                   "
echo "=========================================================================="
