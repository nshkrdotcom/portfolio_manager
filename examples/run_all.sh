#!/bin/bash
#
# Run Portfolio Manager examples
#
# Usage:
#   ./examples/run_all.sh           # Run basic examples only
#   ./examples/run_all.sh --basic   # Run basic examples only (same as default)
#   ./examples/run_all.sh --all     # Run all examples including AI features
#   ./examples/run_all.sh --ai      # Run only AI examples
#   ./examples/run_all.sh 01 03 07  # Run specific examples by number
#

# Don't exit on error - we handle errors ourselves
set +e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Change to project directory
cd "$PROJECT_DIR"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Portfolio Manager Examples Runner                   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check for dependencies
if ! command -v mix &> /dev/null; then
    echo -e "${RED}Error: 'mix' not found. Please install Elixir.${NC}"
    exit 1
fi

# Define example groups
BASIC_EXAMPLES=(
    "01_basic_init.exs"
    "02_list_and_filter.exs"
    "03_repo_details.exs"
    "04_update_context.exs"
    "05_notes_and_decisions.exs"
    "06_relationships.exs"
    "07_text_search.exs"
    "12_edit_and_remove.exs"
    "13_workflow_engine.exs"
    "14_relationship_graph.exs"
    "15_sqlite_cache.exs"
)

AI_EXAMPLES=(
    "08_semantic_search.exs"
    "09_agentic_query.exs"
    "10_chat_session.exs"
    "16_agentic_detection.exs"
)

FULL_EXAMPLE=(
    "11_full_workflow.exs"
)

# Parse arguments
RUN_BASIC=false
RUN_AI=false
RUN_FULL=false
SPECIFIC_EXAMPLES=()

if [ $# -eq 0 ]; then
    RUN_BASIC=true
else
    for arg in "$@"; do
        case $arg in
            --basic)
                RUN_BASIC=true
                ;;
            --ai)
                RUN_AI=true
                ;;
            --all)
                RUN_BASIC=true
                RUN_AI=true
                RUN_FULL=true
                ;;
            --full)
                RUN_FULL=true
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS] [EXAMPLE_NUMBERS...]"
                echo ""
                echo "Options:"
                echo "  --basic    Run basic examples (01-07, 12-15) [default]"
                echo "  --ai       Run AI examples (08-10, 16) - requires GOOGLE_API_KEY"
                echo "  --full     Run full workflow example (11)"
                echo "  --all      Run all examples"
                echo "  --help     Show this help"
                echo ""
                echo "Examples:"
                echo "  $0                 # Run basic examples"
                echo "  $0 --all           # Run everything"
                echo "  $0 01 03 07        # Run specific examples"
                echo "  $0 --ai            # Run only AI examples"
                exit 0
                ;;
            [0-9]*)
                # Specific example number
                padded=$(printf "%02d" "$arg")
                SPECIFIC_EXAMPLES+=("$padded")
                ;;
            *)
                echo -e "${RED}Unknown option: $arg${NC}"
                exit 1
                ;;
        esac
    done
fi

# Build list of examples to run
EXAMPLES_TO_RUN=()

if [ ${#SPECIFIC_EXAMPLES[@]} -gt 0 ]; then
    # Run specific examples
    for num in "${SPECIFIC_EXAMPLES[@]}"; do
        found=false
        for ex in examples/${num}_*.exs; do
            if [ -f "$ex" ]; then
                EXAMPLES_TO_RUN+=("$(basename "$ex")")
                found=true
            fi
        done
        if [ "$found" = false ]; then
            echo -e "${YELLOW}Warning: No example found for number $num${NC}"
        fi
    done
else
    # Run by category
    if [ "$RUN_BASIC" = true ]; then
        EXAMPLES_TO_RUN+=("${BASIC_EXAMPLES[@]}")
    fi
    if [ "$RUN_AI" = true ]; then
        EXAMPLES_TO_RUN+=("${AI_EXAMPLES[@]}")
    fi
    if [ "$RUN_FULL" = true ]; then
        EXAMPLES_TO_RUN+=("${FULL_EXAMPLE[@]}")
    fi
fi

# Check for API key if running AI examples
if [ "$RUN_AI" = true ] || [ "$RUN_FULL" = true ]; then
    if [ -z "$GOOGLE_API_KEY" ]; then
        echo -e "${YELLOW}Warning: GOOGLE_API_KEY not set${NC}"
        echo -e "${YELLOW}AI examples will be skipped or show limited functionality${NC}"
        echo ""
    else
        echo -e "${GREEN}✓ GOOGLE_API_KEY detected${NC}"
        echo ""
    fi
fi

# Summary
echo -e "${BLUE}Examples to run:${NC}"
for ex in "${EXAMPLES_TO_RUN[@]}"; do
    echo "  - $ex"
done
echo ""

# Ensure dependencies
echo -e "${BLUE}Checking dependencies...${NC}"
mix deps.get --quiet 2>/dev/null || mix deps.get
echo -e "${GREEN}✓ Dependencies ready${NC}"
echo ""

# Run examples
PASSED=0
FAILED=0
SKIPPED=0

for example in "${EXAMPLES_TO_RUN[@]}"; do
    example_path="examples/$example"

    if [ ! -f "$example_path" ]; then
        echo -e "${YELLOW}⚠ Skipping: $example (file not found)${NC}"
        ((SKIPPED++))
        continue
    fi

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Running: $example${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if mix run "$example_path" 2>&1; then
        echo -e "${GREEN}✓ $example completed${NC}"
        ((PASSED++))
    else
        exit_code=$?
        if [ $exit_code -eq 0 ]; then
            echo -e "${GREEN}✓ $example completed${NC}"
            ((PASSED++))
        else
            echo -e "${RED}✗ $example failed (exit code: $exit_code)${NC}"
            ((FAILED++))
        fi
    fi

    echo ""
done

# Summary
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                        Summary                              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}Passed:${NC}  $PASSED"
echo -e "  ${RED}Failed:${NC}  $FAILED"
echo -e "  ${YELLOW}Skipped:${NC} $SKIPPED"
echo ""

if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Some examples failed!${NC}"
    exit 1
else
    echo -e "${GREEN}All examples completed successfully!${NC}"
fi
