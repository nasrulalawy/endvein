#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUESTS=50000
CONCURRENCY=100

echo "=========================================================================="
echo "      ⚡ ENDVEIN vs GO (FIBER, FASTHTTP, GIN, ECHO, NET/HTTP) BENCHMARK   "
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

run_bench "1. Gin (gin-gonic/gin)" "$DIR/go_benchmarks/gin_bin" 8093
run_bench "2. Echo (labstack/echo)" "$DIR/go_benchmarks/echo_bin" 8094
run_bench "3. Go Standard Library (net/http)" "$DIR/go_bin" 8082
run_bench "4. Fiber (gofiber/fiber v2)" "$DIR/go_benchmarks/fiber_bin" 8091
run_bench "5. FastHTTP (valyala/fasthttp)" "$DIR/go_benchmarks/fasthttp_bin" 8092
run_bench "6. ⚡ Endvein (Dart 10-Core Cluster)" "$DIR/endvein_bin" 8084

echo ""
echo "=========================================================================="
echo "                     BENCHMARK COMPLETE                                   "
echo "=========================================================================="
