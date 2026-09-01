#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)
BUILD_DIR="$REPO_ROOT/build/e2e"
CACHE_DIR="$REPO_ROOT/.ci-cache"
RUNTIME_DIR="$BUILD_DIR/runtime"
DERIVED_DATA_DIR="$BUILD_DIR/DerivedData"
SOURCE_PACKAGES_DIR="$BUILD_DIR/SourcePackages"

ELASTIC_VERSION=${ELASTIC_VERSION:-9.4.2}
ELASTICSEARCH_URL=http://127.0.0.1:9200
OTLP_HOST=127.0.0.1
OTLP_HTTP_PORT=4318
APP_SERVICE_NAME=integration-test-app
APP_BUNDLE_ID=co.elastic.otel.ios.integration
EXPECTED_SDK_NAME=iOS
SIMULATOR_NAME_PREFIX="EDOT iOS SDK E2E"
TEST_RUN_ID="ios-sdk-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}-$(date +%s)"

elasticsearch_pid=""
collector_pid=""
simulator_udid=""

fail() {
  echo "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 ||
    fail "Required command not found: $1"
}

wait_for_url() {
  local url="$1"
  local label="$2"
  local timeout="${3:-120}"
  local elapsed=0

  until curl --fail --silent "$url" >/dev/null 2>&1; do
    if [ "$elapsed" -ge "$timeout" ]; then
      fail "Timed out waiting for $label at $url"
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
}

wait_for_port() {
  local host="$1"
  local port="$2"
  local label="$3"
  local timeout="${4:-120}"
  local elapsed=0

  until nc -z "$host" "$port" >/dev/null 2>&1; do
    if [ "$elapsed" -ge "$timeout" ]; then
      fail "Timed out waiting for $label at $host:$port"
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
}

download_archive() {
  local url="$1"
  local archive="$2"

  if [ ! -f "$archive" ]; then
    echo "Downloading $(basename "$archive")..."
    curl --fail --location --retry 3 --retry-delay 2 \
      --output "$archive" "$url"
  fi

  if [ ! -f "${archive}.sha512" ]; then
    curl --fail --location --retry 3 --retry-delay 2 \
      --output "${archive}.sha512" "${url}.sha512"
  fi

  local expected
  expected=$(awk '{print $1}' "${archive}.sha512")
  local actual
  actual=$(shasum -a 512 "$archive" | awk '{print $1}')
  if [ "$expected" != "$actual" ]; then
    fail "SHA-512 checksum mismatch for $archive"
  fi
}

service_filter() {
  jq -nc \
    --arg service "$APP_SERVICE_NAME" \
    --arg run_id "$TEST_RUN_ID" \
    '[
      {
        bool: {
          should: [
            {term: {"resource.attributes.service.name": $service}},
            {term: {"service.name": $service}}
          ],
          minimum_should_match: 1
        }
      },
      {
        bool: {
          should: [
            {term: {"resource.attributes.test.run_id": $run_id}},
            {term: {"test.run_id": $run_id}}
          ],
          minimum_should_match: 1
        }
      }
    ]'
}

span_query() {
  local filters
  filters=$(service_filter)
  jq -nc --argjson filters "$filters" '{
    size: 1,
    sort: [{"@timestamp": "desc"}],
    query: {
      bool: {
        filter: ($filters + [{term: {name: "e2e span"}}])
      }
    }
  }'
}

log_query() {
  local filters
  filters=$(service_filter)
  jq -nc --argjson filters "$filters" '{
    size: 1,
    sort: [{"@timestamp": "desc"}],
    query: {
      bool: {
        filter: ($filters + [{
          bool: {
            should: [
              {match_phrase: {"body.text": "e2e log"}},
              {match_phrase: {body: "e2e log"}},
              {match_phrase: {message: "e2e log"}}
            ],
            minimum_should_match: 1
          }
        }])
      }
    }
  }'
}

metric_query() {
  local filters
  filters=$(service_filter)
  jq -nc --argjson filters "$filters" '{
    size: 1,
    sort: [{"@timestamp": "desc"}],
    query: {
      bool: {
        filter: ($filters + [{
          bool: {
            should: [
              {exists: {field: "metrics.e2e.launches"}},
              {term: {"metric.name": "e2e.launches"}},
              {term: {name: "e2e.launches"}}
            ],
            minimum_should_match: 1
          }
        }])
      }
    }
  }'
}

crash_query() {
  local filters
  filters=$(service_filter)
  jq -nc --argjson filters "$filters" '{
    size: 1,
    sort: [{"@timestamp": "desc"}],
    query: {
      bool: {
        filter: ($filters + [{
          bool: {
            should: [
              {term: {"event.name": "app.crash"}},
              {term: {event_name: "app.crash"}},
              {term: {"attributes.otel.event.name": "app.crash"}}
            ],
            minimum_should_match: 1
          }
        }])
      }
    }
  }'
}

es_search() {
  local index="$1"
  local query="$2"
  local response_file="${3:-}"
  local response

  response=$(curl --fail --silent --show-error \
    -H "Content-Type: application/json" \
    --data "$query" \
    "$ELASTICSEARCH_URL/$index/_search") || return 1

  if [ -n "$response_file" ]; then
    echo "$response" | jq . > "$response_file"
  fi
  if [ "$(echo "$response" | jq -r '.hits.total.value // 0')" -lt 1 ]; then
    return 1
  fi
  echo "$response" | jq -c '.hits.hits[0]'
}

es_wait_for_item() {
  local index="$1"
  local query="$2"
  local label="$3"
  local artifact_name="$4"
  local timeout="${5:-180}"
  local elapsed=0

  echo "$query" | jq . > "$BUILD_DIR/${artifact_name}-query.json"
  while [ "$elapsed" -lt "$timeout" ]; do
    local result
    if result=$(
      es_search "$index" "$query" "$BUILD_DIR/${artifact_name}-response.json"
    ); then
      echo "$result" | jq . > "$BUILD_DIR/${artifact_name}.json"
      echo "$result"
      return 0
    fi
    echo "  ${elapsed}s/${timeout}s - waiting for $label..." >&2
    sleep 5
    elapsed=$((elapsed + 5))
  done

  fail "Timed out after ${timeout}s waiting for $label"
}

document_attribute() {
  local document="$1"
  local attribute="$2"
  echo "$document" | jq -r \
    --arg attribute "$attribute" \
    '._source.resource.attributes[$attribute] //
     ._source[$attribute] //
     empty'
}

assert_identity() {
  local document="$1"
  local label="$2"
  local service_name
  local service_version
  local sdk_name

  service_name=$(document_attribute "$document" "service.name")
  service_version=$(document_attribute "$document" "service.version")
  sdk_name=$(document_attribute "$document" "telemetry.sdk.name")

  [ "$service_name" = "$APP_SERVICE_NAME" ] ||
    fail "$label service.name: expected '$APP_SERVICE_NAME', got '$service_name'"
  [ "$service_version" = "$APP_VERSION" ] ||
    fail "$label service.version: expected '$APP_VERSION', got '$service_version'"
  [ "$sdk_name" = "$EXPECTED_SDK_NAME" ] ||
    fail "$label telemetry.sdk.name: expected '$EXPECTED_SDK_NAME', got '$sdk_name'"
}

assert_not_empty() {
  local value="$1"
  local message="$2"
  if [ -z "$value" ] || [ "$value" = "null" ]; then
    fail "$message"
  fi
}

launch_app() {
  local scenario="$1"
  local log_prefix="$2"
  local launch_output
  local pid

  : > "$BUILD_DIR/${log_prefix}.stdout.log"
  : > "$BUILD_DIR/${log_prefix}.stderr.log"

  if [ -n "$scenario" ]; then
    launch_output=$(
      SIMCTL_CHILD_OTEL_RESOURCE_ATTRIBUTES="test.run_id=$TEST_RUN_ID" \
      SIMCTL_CHILD_E2E_SCENARIO="$scenario" \
        xcrun simctl launch \
          --terminate-running-process \
          --stdout="$BUILD_DIR/${log_prefix}.stdout.log" \
          --stderr="$BUILD_DIR/${log_prefix}.stderr.log" \
          "$simulator_udid" \
          "$APP_BUNDLE_ID"
    )
  else
    launch_output=$(
      SIMCTL_CHILD_OTEL_RESOURCE_ATTRIBUTES="test.run_id=$TEST_RUN_ID" \
        xcrun simctl launch \
          --terminate-running-process \
          --stdout="$BUILD_DIR/${log_prefix}.stdout.log" \
          --stderr="$BUILD_DIR/${log_prefix}.stderr.log" \
          "$simulator_udid" \
          "$APP_BUNDLE_ID"
    )
  fi

  pid="${launch_output##*: }"
  case "$pid" in
    '' | *[!0-9]*) fail "Could not parse app PID from simctl output: $launch_output" ;;
  esac
  echo "$pid"
}

print_failure_diagnostics() {
  echo "=== E2E failure diagnostics ===" >&2
  curl --silent "$ELASTICSEARCH_URL/_cluster/health?pretty" >&2 2>/dev/null || true

  if [ -n "$simulator_udid" ]; then
    xcrun simctl spawn "$simulator_udid" log show \
      --style compact \
      --last 10m \
      --predicate 'process == "integration-test-app"' \
      > "$BUILD_DIR/simulator-system.log" 2>&1 || true
  fi

  local file
  for file in \
    "$BUILD_DIR/elasticsearch.log" \
    "$BUILD_DIR/otel-endpoint.log" \
    "$BUILD_DIR/app.stdout.log" \
    "$BUILD_DIR/app.stderr.log" \
    "$BUILD_DIR/app-crash.stdout.log" \
    "$BUILD_DIR/app-crash.stderr.log" \
    "$BUILD_DIR/app-relaunch.stdout.log" \
    "$BUILD_DIR/app-relaunch.stderr.log"; do
    if [ -f "$file" ]; then
      echo "--- Last 100 lines of $(basename "$file") ---" >&2
      tail -n 100 "$file" >&2 || true
    fi
  done
  echo "=== End E2E failure diagnostics ===" >&2
}

cleanup() {
  local exit_code=$?
  trap - EXIT

  if [ "$exit_code" -ne 0 ]; then
    print_failure_diagnostics
  fi

  if [ -n "$simulator_udid" ]; then
    xcrun simctl shutdown "$simulator_udid" >/dev/null 2>&1 || true
    xcrun simctl delete "$simulator_udid" >/dev/null 2>&1 || true
  fi

  local pid
  for pid in "$collector_pid" "$elasticsearch_pid"; do
    if [ -n "$pid" ]; then
      kill "$pid" >/dev/null 2>&1 || true
      wait "$pid" >/dev/null 2>&1 || true
    fi
  done

  rm -rf "$RUNTIME_DIR" "$DERIVED_DATA_DIR" "$SOURCE_PACKAGES_DIR"
  exit "$exit_code"
}

trap cleanup EXIT

for command in awk curl git jq nc shasum tar xattr xcodebuild xcrun; do
  require_command "$command"
done
[ -x /usr/libexec/PlistBuddy ] ||
  fail "Required command not found: /usr/libexec/PlistBuddy"

mkdir -p "$BUILD_DIR" "$CACHE_DIR"
rm -rf "$RUNTIME_DIR" "$DERIVED_DATA_DIR" "$SOURCE_PACKAGES_DIR"
mkdir -p "$RUNTIME_DIR"

case "$(uname -m)" in
  arm64) elastic_arch=aarch64 ;;
  x86_64) elastic_arch=x86_64 ;;
  *) fail "Unsupported macOS architecture: $(uname -m)" ;;
esac

elasticsearch_archive="$CACHE_DIR/elasticsearch-$ELASTIC_VERSION-darwin-$elastic_arch.tar.gz"
collector_archive="$CACHE_DIR/elastic-agent-$ELASTIC_VERSION-darwin-$elastic_arch.tar.gz"

download_archive \
  "https://artifacts.elastic.co/downloads/elasticsearch/$(basename "$elasticsearch_archive")" \
  "$elasticsearch_archive"
download_archive \
  "https://artifacts.elastic.co/downloads/beats/elastic-agent/$(basename "$collector_archive")" \
  "$collector_archive"

echo "Extracting Elastic distributions..."
tar -xzf "$elasticsearch_archive" -C "$RUNTIME_DIR"
tar -xzf "$collector_archive" -C "$RUNTIME_DIR"

elasticsearch_home="$RUNTIME_DIR/elasticsearch-$ELASTIC_VERSION"
collector_home="$RUNTIME_DIR/elastic-agent-$ELASTIC_VERSION-darwin-$elastic_arch"
xattr -dr com.apple.quarantine "$elasticsearch_home" "$collector_home" 2>/dev/null || true

echo "Starting Elasticsearch..."
ES_JAVA_OPTS="-Xms512m -Xmx512m" \
  "$elasticsearch_home/bin/elasticsearch" \
  -Ediscovery.type=single-node \
  -Expack.security.enabled=false \
  -Expack.security.autoconfiguration.enabled=false \
  -Expack.ml.enabled=false \
  -Ecluster.routing.allocation.disk.threshold_enabled=false \
  > "$BUILD_DIR/elasticsearch.log" 2>&1 &
elasticsearch_pid=$!
wait_for_url "$ELASTICSEARCH_URL" Elasticsearch 180

echo "Starting Elastic Agent OTLP endpoint..."
ELASTIC_ENDPOINT="$ELASTICSEARCH_URL" \
  "$collector_home/otelcol" \
  --config "$SCRIPT_DIR/otel.yml" \
  > "$BUILD_DIR/otel-endpoint.log" 2>&1 &
collector_pid=$!
wait_for_port "$OTLP_HOST" "$OTLP_HTTP_PORT" "OTLP endpoint" 120

echo "Creating iOS Simulator..."
runtime_id=$(
  xcrun simctl list runtimes -j |
    jq -r '[.runtimes[] | select(.isAvailable == true and (.identifier | contains(".iOS-")))]
      | sort_by(.version | split(".") | map(tonumber))
      | last
      | .identifier'
)
device_type_id=$(
  xcrun simctl list devicetypes -j |
    jq -r '[.devicetypes[] | select(.name | startswith("iPhone"))] | first | .identifier'
)
[ -n "$runtime_id" ] && [ "$runtime_id" != "null" ] ||
  fail "No available iOS Simulator runtime found"
[ -n "$device_type_id" ] && [ "$device_type_id" != "null" ] ||
  fail "No iPhone Simulator device type found"

simulator_udid=$(
  xcrun simctl create \
    "$SIMULATOR_NAME_PREFIX $TEST_RUN_ID" \
    "$device_type_id" \
    "$runtime_id"
)
xcrun simctl boot "$simulator_udid"
xcrun simctl bootstatus "$simulator_udid" -b

echo "Building and installing integration app..."
xcodebuild -quiet \
  -project "$REPO_ROOT/integration-test/IntegrationTestApp.xcodeproj" \
  -scheme IntegrationTestApp \
  -configuration Release \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$simulator_udid" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  build

app_path="$DERIVED_DATA_DIR/Build/Products/Release-iphonesimulator/integration-test-app.app"
dsym_path="${app_path}.dSYM"
[ -d "$app_path" ] || fail "Release build did not produce $app_path"
[ -d "$dsym_path" ] || fail "Release build did not produce $dsym_path"
APP_VERSION=$(
  /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app_path/Info.plist"
)
[ -n "$APP_VERSION" ] || fail "Built app has no CFBundleShortVersionString"

xcrun simctl install "$simulator_udid" "$app_path"

echo "Launching integration app..."
launch_app "" app >/dev/null

span_document=$(es_wait_for_item \
  "traces-*" \
  "$(span_query)" \
  "span named 'e2e span'" \
  "span-document")
assert_identity "$span_document" "Span document"

log_document=$(es_wait_for_item \
  "logs-*" \
  "$(log_query)" \
  "log record with body 'e2e log'" \
  "log-document")
assert_identity "$log_document" "Log document"

metric_document=$(es_wait_for_item \
  "metrics-*" \
  "$(metric_query)" \
  "metric named 'e2e.launches'" \
  "metric-document")
assert_identity "$metric_document" "Metric document"

echo "Triggering intentional app crash..."
xcrun simctl terminate "$simulator_udid" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true
crash_pid=$(launch_app crash app-crash)

crash_detected=false
crash_wait_seconds=0
while [ "$crash_wait_seconds" -lt 20 ]; do
  if ! kill -0 "$crash_pid" >/dev/null 2>&1; then
    crash_detected=true
    break
  fi
  sleep 1
  crash_wait_seconds=$((crash_wait_seconds + 1))
done
[ "$crash_detected" = true ] ||
  fail "The app did not exit after the intentional crash"

echo "Relaunching app to export the persisted crash report..."
launch_app "" app-relaunch >/dev/null

crash_document=$(es_wait_for_item \
  "logs-*" \
  "$(crash_query)" \
  "app.crash event" \
  "crash-document" \
  120)

exception_type=$(
  echo "$crash_document" |
    jq -r '._source.attributes."exception.type" // ._source.exception.type // empty'
)
exception_stacktrace=$(
  echo "$crash_document" |
    jq -r '._source.attributes."exception.stacktrace" //
      ._source.exception.stacktrace //
      empty'
)
assert_not_empty "$exception_type" "The app.crash event has no exception.type"
assert_not_empty "$exception_stacktrace" "The app.crash event has no exception.stacktrace"

echo "E2E test succeeded for run ID $TEST_RUN_ID"
