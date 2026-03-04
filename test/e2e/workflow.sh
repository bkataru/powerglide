#!/bin/bash
set -e

BINARY="./zig-out/bin/powerglide"

echo "--- 1. Doctor check ---"
$BINARY doctor

echo "--- 2. Config management ---"
$BINARY config set velocity 4.0
$BINARY config list | grep "velocity: 4.0x"

echo "--- 3. Tools listing ---"
$BINARY tools list

echo "--- 4. Session management ---"
$BINARY session list

echo "--- 5. Swarm status ---"
$BINARY swarm list

echo "--- E2E Workflow Success ---"
