#!/bin/bash
set -e

# PostgreSQL Logical Replication Test Script for Docker Compose
# This script tests the replication setup using shell commands and psql

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test configuration
SOURCE_HOST="localhost"
SOURCE_PORT="5432"
TARGET_HOST="localhost"
TARGET_PORT="5433"
DB_USER="postgres"
DB_PASSWORD="postgres"
SOURCE_DB="sourcedb"
TARGET_DB="targetdb"
TIMEOUT=60
REPLICATION_WAIT=10

# Counters
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

test_pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((TESTS_PASSED++))
}

test_fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((TESTS_FAILED++))
}

# Wait for database to be ready
wait_for_database() {
    local host=$1
    local port=$2
    local database=$3
    local timeout=$4
    
    log_info "Waiting for database at $host:$port to be ready..."
    
    local count=0
    while [ $count -lt $timeout ]; do
        if pg_isready -h "$host" -p "$port" -U "$DB_USER" -d "$database" >/dev/null 2>&1; then
            log_info "Database at $host:$port is ready"
            return 0
        fi
        
        # Fallback to psql connection test
        if PGPASSWORD="$DB_PASSWORD" psql -h "$host" -p "$port" -U "$DB_USER" -d "$database" -c '\q' >/dev/null 2>&1; then
            log_info "Database at $host:$port is ready"
            return 0
        fi
        
        sleep 2
        ((count += 2))
    done
    
    log_error "Database at $host:$port not ready after ${timeout}s"
    return 1
}

# Test database connectivity
test_database_connectivity() {
    log_info "Testing database connectivity..."
    
    if wait_for_database "$SOURCE_HOST" "$SOURCE_PORT" "$SOURCE_DB" "$TIMEOUT"; then
        test_pass "Source database connectivity"
    else
        test_fail "Source database connectivity"
        return 1
    fi
    
    if wait_for_database "$TARGET_HOST" "$TARGET_PORT" "$TARGET_DB" "$TIMEOUT"; then
        test_pass "Target database connectivity"
    else
        test_fail "Target database connectivity"
        return 1
    fi
    
    return 0
}

# Test replication setup
test_replication_setup() {
    log_info "Testing replication setup..."
    
    # Test publication exists on source
    local pub_count
    pub_count=$(PGPASSWORD="$DB_PASSWORD" psql -h "$SOURCE_HOST" -p "$SOURCE_PORT" -U "$DB_USER" -d "$SOURCE_DB" -t -c "SELECT COUNT(*) FROM pg_publication WHERE pubname = 'my_publication';" 2>/dev/null | tr -d ' ')
    
    if [ "$pub_count" -gt 0 ]; then
        test_pass "Publication exists on source"
    else
        test_fail "Publication exists on source"
    fi
    
    # Test subscription exists on target
    local sub_count
    sub_count=$(PGPASSWORD="$DB_PASSWORD" psql -h "$TARGET_HOST" -p "$TARGET_PORT" -U "$DB_USER" -d "$TARGET_DB" -t -c "SELECT COUNT(*) FROM pg_subscription WHERE subname = 'my_subscription';" 2>/dev/null | tr -d ' ')
    
    if [ "$sub_count" -gt 0 ]; then
        test_pass "Subscription exists on target"
    else
        test_fail "Subscription exists on target"
    fi
    
    # Test replication slot exists on source
    local slot_count
    slot_count=$(PGPASSWORD="$DB_PASSWORD" psql -h "$SOURCE_HOST" -p "$SOURCE_PORT" -U "$DB_USER" -d "$SOURCE_DB" -t -c "SELECT COUNT(*) FROM pg_replication_slots WHERE slot_name = 'my_subscription';" 2>/dev/null | tr -d ' ')
    
    if [ "$slot_count" -gt 0 ]; then
        test_pass "Replication slot exists on source"
    else
        test_fail "Replication slot exists on source"
    fi
    
    # Test subscription is enabled
    local sub_enabled
    sub_enabled=$(PGPASSWORD="$DB_PASSWORD" psql -h "$TARGET_HOST" -p "$TARGET_PORT" -U "$DB_USER" -d "$TARGET_DB" -t -c "SELECT subenabled FROM pg_subscription WHERE subname = 'my_subscription';" 2>/dev/null | tr -d ' ')
    
    if [ "$sub_enabled" = "t" ]; then
        test_pass "Subscription is enabled"
    else
        test_fail "Subscription is enabled"
    fi
}

# Test data replication
test_data_replication() {
    log_info "Testing data replication..."
    
    local test_timestamp=$(date +%s)
    local test_email="test_${test_timestamp}@example.com"
    local test_name="Test User ${test_timestamp}"
    local test_product="Test Product ${test_timestamp}"
    
    # Insert test data on source
    log_info "Inserting test data on source..."
    local insert_result
    insert_result=$(PGPASSWORD="$DB_PASSWORD" psql -h "$SOURCE_HOST" -p "$SOURCE_PORT" -U "$DB_USER" -d "$SOURCE_DB" -t -c "
        INSERT INTO users (name, email) VALUES ('$test_name', '$test_email') RETURNING id;
    " 2>/dev/null | grep -o '[0-9]*' | head -n 1 | tr -d '[:space:]')
    
    if [ -n "$insert_result" ] && [ "$insert_result" -gt 0 ]; then
        test_pass "Test user inserted on source"
        local test_user_id="$insert_result"
        
        # Insert test order
        local order_result
        order_result=$(PGPASSWORD="$DB_PASSWORD" psql -h "$SOURCE_HOST" -p "$SOURCE_PORT" -U "$DB_USER" -d "$SOURCE_DB" -t -c "
            INSERT INTO orders (user_id, product_name, amount) VALUES ($test_user_id, '$test_product', 99.99) RETURNING id;
        " 2>/dev/null | grep -o '[0-9]*' | head -n 1 | tr -d '[:space:]')
        
        if [ -n "$order_result" ] && [ "$order_result" -gt 0 ]; then
            test_pass "Test order inserted on source"
        else
            test_fail "Test order inserted on source"
            return 1
        fi
    else
        test_fail "Test user inserted on source"
        return 1
    fi
    
    # Wait for replication
    log_info "Waiting ${REPLICATION_WAIT}s for replication..."
    sleep "$REPLICATION_WAIT"
    
    # Verify data on target
    log_info "Verifying replicated data on target..."
    
    # Check user replication
    local user_count
    user_count=$(PGPASSWORD="$DB_PASSWORD" psql -h "$TARGET_HOST" -p "$TARGET_PORT" -U "$DB_USER" -d "$TARGET_DB" -t -c "SELECT COUNT(*) FROM users WHERE email = '$test_email';" 2>/dev/null | tr -d ' ')
    
    if [ "$user_count" -gt 0 ]; then
        test_pass "User data replicated to target"
    else
        test_fail "User data replicated to target"
    fi
    
    # Check order replication
    local order_count
    order_count=$(PGPASSWORD="$DB_PASSWORD" psql -h "$TARGET_HOST" -p "$TARGET_PORT" -U "$DB_USER" -d "$TARGET_DB" -t -c "SELECT COUNT(*) FROM orders WHERE user_id = $test_user_id;" 2>/dev/null | tr -d ' ')
    
    if [ "$order_count" -gt 0 ]; then
        test_pass "Order data replicated to target"
    else
        test_fail "Order data replicated to target"
    fi
}

# Test replication performance
test_replication_performance() {
    log_info "Testing replication performance..."
    
    # Check replication status
    local repl_state
    repl_state=$(PGPASSWORD="$DB_PASSWORD" psql -h "$SOURCE_HOST" -p "$SOURCE_PORT" -U "$DB_USER" -d "$SOURCE_DB" -t -c "
        SELECT state FROM pg_stat_replication WHERE application_name = 'my_subscription';
    " 2>/dev/null | tr -d ' ')
    
    if [ "$repl_state" = "streaming" ]; then
        test_pass "Replication is in streaming state"
    else
        test_fail "Replication is in streaming state (current: $repl_state)"
    fi
    
    # Check replication lag
    local lag_bytes
    lag_bytes=$(PGPASSWORD="$DB_PASSWORD" psql -h "$SOURCE_HOST" -p "$SOURCE_PORT" -U "$DB_USER" -d "$SOURCE_DB" -t -c "
        SELECT COALESCE(pg_wal_lsn_diff(sent_lsn, replay_lsn), 0) as lag_bytes
        FROM pg_stat_replication 
        WHERE application_name = 'my_subscription';
    " 2>/dev/null | tr -d ' ')
    
    if [ -n "$lag_bytes" ] && [ "$lag_bytes" -lt 1024 ]; then
        test_pass "Replication lag is acceptable ($lag_bytes bytes)"
    else
        test_fail "Replication lag is acceptable (current: $lag_bytes bytes)"
    fi
}

# Display replication status
show_replication_status() {
    log_info "Current replication status:"
    
    echo "Source Database (Publications):"
    PGPASSWORD="$DB_PASSWORD" psql -h "$SOURCE_HOST" -p "$SOURCE_PORT" -U "$DB_USER" -d "$SOURCE_DB" -c "
        SELECT pubname, puballtables, pubinsert, pubupdate, pubdelete 
        FROM pg_publication;
    " 2>/dev/null || echo "  Failed to query publications"
    
    echo "Source Database (Replication Slots):"
    PGPASSWORD="$DB_PASSWORD" psql -h "$SOURCE_HOST" -p "$SOURCE_PORT" -U "$DB_USER" -d "$SOURCE_DB" -c "
        SELECT slot_name, plugin, slot_type, active, restart_lsn 
        FROM pg_replication_slots;
    " 2>/dev/null || echo "  Failed to query replication slots"
    
    echo "Source Database (Replication Stats):"
    PGPASSWORD="$DB_PASSWORD" psql -h "$SOURCE_HOST" -p "$SOURCE_PORT" -U "$DB_USER" -d "$SOURCE_DB" -c "
        SELECT application_name, state, sent_lsn, write_lsn, flush_lsn, replay_lsn 
        FROM pg_stat_replication;
    " 2>/dev/null || echo "  Failed to query replication stats"
    
    echo "Target Database (Subscriptions):"
    PGPASSWORD="$DB_PASSWORD" psql -h "$TARGET_HOST" -p "$TARGET_PORT" -U "$DB_USER" -d "$TARGET_DB" -c "
        SELECT subname, subenabled, subconninfo 
        FROM pg_subscription;
    " 2>/dev/null || echo "  Failed to query subscriptions"
}

# Main test function
run_tests() {
    log_info "Starting PostgreSQL Logical Replication Tests (Docker Compose)"
    echo "=================================================="
    
    # Test 1: Database connectivity
    if ! test_database_connectivity; then
        log_error "Database connectivity test failed. Stopping tests."
        return 1
    fi
    
    # Test 2: Replication setup
    test_replication_setup
    
    # Test 3: Data replication
    test_data_replication
    
    # Test 4: Replication performance
    test_replication_performance
    
    # Show status
    echo ""
    show_replication_status
    
    # Summary
    echo ""
    echo "=================================================="
    log_info "Test Summary:"
    echo "  Tests Passed: $TESTS_PASSED"
    echo "  Tests Failed: $TESTS_FAILED"
    echo "  Total Tests:  $((TESTS_PASSED + TESTS_FAILED))"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        log_info "All tests passed! ✓"
        return 0
    else
        log_error "$TESTS_FAILED test(s) failed! ✗"
        return 1
    fi
}

# Parse command line arguments
VERBOSE=false
SHOW_STATUS_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -s|--status)
            SHOW_STATUS_ONLY=true
            shift
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -w|--wait)
            REPLICATION_WAIT="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  -v, --verbose       Enable verbose output"
            echo "  -s, --status        Show replication status only"
            echo "  -t, --timeout SEC   Database connection timeout (default: 60)"
            echo "  -w, --wait SEC      Replication wait time (default: 10)"
            echo "  -h, --help          Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if required tools are available
if ! command -v psql &> /dev/null; then
    log_error "psql command not found. Please install PostgreSQL client tools."
    exit 1
fi

if ! command -v pg_isready &> /dev/null; then
    log_warn "pg_isready command not found. Will use psql for connectivity tests."
fi

# Change to project directory
cd "$PROJECT_DIR"

# Show status only if requested
if [ "$SHOW_STATUS_ONLY" = true ]; then
    show_replication_status
    exit 0
fi

# Run tests
if run_tests; then
    exit 0
else
    exit 1
fi
