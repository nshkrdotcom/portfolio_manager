#!/usr/bin/env bash
#
# Run Portfolio Manager examples
#
# Usage:
#   ./examples/run_all.sh              # Run all examples
#   ./examples/run_all.sh --list       # List available examples
#   ./examples/run_all.sh rag          # Run by short name
#   ./examples/run_all.sh rag_query.exs # Run by filename
#

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR" || exit 1

EXAMPLES=(
  "index_repo.exs"
  "rag_query.exs"
  "graph_analysis.exs"
  "full_workflow.exs"
)

resolve_example() {
  case "$1" in
    rag|rag_query) echo "rag_query.exs" ;;
    index|index_repo) echo "index_repo.exs" ;;
    graph|graph_analysis) echo "graph_analysis.exs" ;;
    full|full_workflow) echo "full_workflow.exs" ;;
    *.exs) echo "$1" ;;
    *) echo "" ;;
  esac
}

if [ "$#" -eq 0 ]; then
  SELECTED=("${EXAMPLES[@]}")
else
  if [ "$1" = "--list" ]; then
    printf '%s\n' "${EXAMPLES[@]}"
    exit 0
  fi

  SELECTED=()
  for arg in "$@"; do
    resolved=$(resolve_example "$arg")
    if [ -n "$resolved" ] && [ -f "$SCRIPT_DIR/$resolved" ]; then
      SELECTED+=("$resolved")
    else
      echo "Unknown example: $arg"
      exit 1
    fi
  done
fi

failures=0

for example in "${SELECTED[@]}"; do
  printf '\n==> Running examples/%s\n' "$example"
  mix run "examples/$example"
  if [ "$?" -ne 0 ]; then
    echo "Failed: $example"
    failures=$((failures + 1))
  fi
done

if [ "$failures" -gt 0 ]; then
  printf '\nCompleted with %s failure(s).\n' "$failures"
  exit 1
fi

printf '\nAll examples completed.\n'
