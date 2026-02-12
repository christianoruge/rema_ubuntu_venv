#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
BASE_URL="${1:-http://localhost:8000}"
TEST_FILE="${2:-.}"

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if curl is installed
check_curl() {
    if ! command -v curl &> /dev/null; then
        log_error "curl is not installed. Please install it first."
        exit 1
    fi
}

# Test health endpoint
test_health() {
    log_info "Testing health endpoint: $BASE_URL/health"
    
    response=$(curl -s -w "\n%{http_code}" "$BASE_URL/health")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" = "200" ]; then
        log_success "Health check passed (HTTP $http_code)"
        echo "Response: $body"
        return 0
    else
        log_error "Health check failed (HTTP $http_code)"
        echo "Response: $body"
        return 1
    fi
}

# Test PDF conversion
test_convert() {
    local pdf_file="$1"
    
    if [ ! -f "$pdf_file" ]; then
        log_error "PDF file not found: $pdf_file"
        return 1
    fi
    
    log_info "Testing PDF conversion: $pdf_file"
    log_info "Uploading to: $BASE_URL/convert"
    
    output_file="${pdf_file%.*}_output.xlsx"
    
    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -F "file=@$pdf_file" \
        -o "$output_file" \
        "$BASE_URL/convert")
    
    http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" = "200" ]; then
        log_success "PDF conversion successful (HTTP $http_code)"
        
        if [ -f "$output_file" ]; then
            file_size=$(du -h "$output_file" | cut -f1)
            log_success "Output file created: $output_file ($file_size)"
        fi
        return 0
    else
        log_error "PDF conversion failed (HTTP $http_code)"
        
        if [ -f "$output_file" ]; then
            error_msg=$(cat "$output_file")
            echo "Error: $error_msg"
            rm "$output_file"
        fi
        return 1
    fi
}

# Test invalid file
test_invalid_file() {
    log_info "Testing with invalid file (should fail)"
    
    # Create a temporary text file
    temp_file=$(mktemp --suffix=.txt)
    echo "This is not a PDF" > "$temp_file"
    
    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -F "file=@$temp_file" \
        "$BASE_URL/convert")
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    rm "$temp_file"
    
    if [ "$http_code" = "400" ]; then
        log_success "Invalid file correctly rejected (HTTP $http_code)"
        echo "Response: $body"
        return 0
    else
        log_warning "Expected 400, got $http_code"
        echo "Response: $body"
        return 1
    fi
}

# Test missing file
test_missing_file() {
    log_info "Testing without file (should fail)"
    
    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        "$BASE_URL/convert")
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" = "400" ]; then
        log_success "Missing file correctly rejected (HTTP $http_code)"
        echo "Response: $body"
        return 0
    else
        log_warning "Expected 400, got $http_code"
        echo "Response: $body"
        return 1
    fi
}

# Performance test
test_performance() {
    local pdf_file="$1"
    local iterations="${2:-3}"
    
    if [ ! -f "$pdf_file" ]; then
        log_error "PDF file not found: $pdf_file"
        return 1
    fi
    
    log_info "Running performance test: $iterations iterations"
    
    total_time=0
    failed=0
    
    for i in $(seq 1 $iterations); do
        echo -n "Iteration $i/$iterations: "
        
        start=$(date +%s%N)
        
        response=$(curl -s -w "\n%{http_code}" \
            -X POST \
            -F "file=@$pdf_file" \
            -o /tmp/test_output_$i.xlsx \
            "$BASE_URL/convert")
        
        end=$(date +%s%N)
        http_code=$(echo "$response" | tail -n1)
        
        if [ "$http_code" = "200" ]; then
            # Calculate time in milliseconds
            elapsed_ms=$(( (end - start) / 1000000 ))
            echo "${elapsed_ms}ms"
            total_time=$((total_time + elapsed_ms))
            rm -f "/tmp/test_output_$i.xlsx"
        else
            log_error "Failed (HTTP $http_code)"
            failed=$((failed + 1))
        fi
    done
    
    if [ $failed -eq 0 ]; then
        avg_time=$((total_time / iterations))
        log_success "Performance test completed"
        echo "Total time: ${total_time}ms"
        echo "Average time: ${avg_time}ms"
        echo "Success rate: 100%"
        return 0
    else
        log_error "Performance test failed: $failed/$iterations failed"
        return 1
    fi
}

# Find PDF files in directory
find_pdf_files() {
    local dir="$1"
    find "$dir" -type f -name "*.pdf" | head -5
}

# Main test suite
run_all_tests() {
    log_info "Starting API test suite"
    echo "Base URL: $BASE_URL"
    echo ""
    
    # Test health endpoint
    test_health
    health_status=$?
    echo ""
    
    if [ $health_status -ne 0 ]; then
        log_error "Health check failed. Cannot continue with other tests."
        return 1
    fi
    
    # Test invalid file
    test_invalid_file
    echo ""
    
    # Test missing file
    test_missing_file
    echo ""
    
    # Find and test PDF files
    log_info "Looking for PDF files in: $TEST_FILE"
    
    if [ -f "$TEST_FILE" ] && [ "${TEST_FILE##*.}" = "pdf" ]; then
        # Single PDF file provided
        test_convert "$TEST_FILE"
        echo ""
        
        # Performance test
        test_performance "$TEST_FILE" 3
        
    elif [ -d "$TEST_FILE" ]; then
        # Directory provided
        pdf_files=$(find_pdf_files "$TEST_FILE")
        
        if [ -z "$pdf_files" ]; then
            log_warning "No PDF files found in $TEST_FILE"
        else
            count=$(echo "$pdf_files" | wc -l)
            log_info "Found $count PDF file(s)"
            
            first_pdf=$(echo "$pdf_files" | head -n1)
            test_convert "$first_pdf"
            echo ""
            
            test_performance "$first_pdf" 3
        fi
    else
        log_warning "No test file specified or found"
    fi
    
    echo ""
    log_success "Test suite completed"
}

# Display usage
show_usage() {
    echo "Usage: $0 [BASE_URL] [TEST_FILE]"
    echo ""
    echo "Arguments:"
    echo "  BASE_URL   - API base URL (default: http://localhost:8000)"
    echo "  TEST_FILE  - PDF file or directory to test with (default: current directory)"
    echo ""
    echo "Examples:"
    echo "  $0                              # Test local app with current directory"
    echo "  $0 http://localhost:8000        # Test local app"
    echo "  $0 https://my-app.azurecontainerinstances.io  # Test deployed app"
    echo "  $0 https://my-app.azurecontainerinstances.io ./test.pdf  # Test with specific file"
    echo "  $0 https://my-app.azurecontainerinstances.io ./test_files  # Test with directory"
    echo ""
    echo "The script will:"
    echo "  1. Test health endpoint"
    echo "  2. Test invalid file handling"
    echo "  3. Test missing file handling"
    echo "  4. Convert PDF to Excel (if file provided)"
    echo "  5. Run performance tests"
}

# Parse arguments
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_usage
    exit 0
fi

# Run tests
check_curl
run_all_tests
