#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUESTS=50000
CONCURRENCY=100

echo "=========================================================================="
echo "      🦀 RUST (ACTIX, AXUM) vs ⚡ ENDVEIN (DART) vs 🐹 GO (FASTHTTP)       "
echo "  Hardware : Apple Silicon (10 CPU Cores, macOS arm64)                    "
echo "  Workload : $REQUESTS requests with concurrency $CONCURRENCY (Keep-Alive)"
echo "  Mode     : Production Optimized Native Binaries                         "
echo "=========================================================================="

run_bench() {
  local name="$1"
  local bin="$2"
  local port="$3"
  local url="http://127.0.0.1:$port/json"

  echo ""
  echo ">>> [Testing $name] Starting binary on port $port..."
  $bin > /dev/null 2>&1 &
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
  sleep 0.8

  local rps
  rps=$(echo "$output" | grep "Requests per second:" | awk '{print $4}')
  local latency
  latency=$(echo "$output" | grep "Time per request:" | head -n 1 | awk '{print $4}')
  
  echo ">>> [$name Results]"
  echo "    Throughput   : $rps req/s"
  echo "    Mean Latency : $latency ms"
}

run_bench "1. Axum (Rust 1.99 / Tokio / Hyper)" "$DIR/rust_benchmarks/target/release/axum_bin" 8096
run_bench "2. Actix-web (Rust 1.99 / Actix)" "$DIR/rust_benchmarks/target/release/actix_bin" 8095
run_bench "3. FastHTTP (Go / Valyala)" "$DIR/go_benchmarks/fasthttp_bin" 8092
run_bench "4. Endvein Raw Socket (Pure Dart AOT)" "$DIR/endvein_bin" 8084
run_bench "5. ⚡ Endvein Turbo FFI (C kqueue + Dart FFI)" "$DIR/endvein_turbo_bin --workers=1 --port=8097" 8097

echo ""
echo "=========================================================================="
echo "                     BENCHMARK COMPLETE                                   "
echo "=========================================================================="
