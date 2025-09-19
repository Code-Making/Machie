#!/bin/bash

# Run dart analyze and capture output
ANALYZE_OUTPUT=$(dart analyze 2>&1)

# Count error lines (lines containing "error" or "Error", case-insensitive)
ERROR_COUNT=$(echo "$ANALYZE_OUTPUT" | grep -i "error" | wc -l | tr -d ' ')

# Count warning lines
WARNING_COUNT=$(echo "$ANALYZE_OUTPUT" | grep -i "warning" | wc -l | tr -d ' ')

# Create summary
SUMMARY="Dart Analysis Results:
Errors: $ERROR_COUNT
Warnings: $WARNING_COUNT

Full Output:
$ANALYZE_OUTPUT"

# Copy to clipboard
echo "$SUMMARY" | cs clip write

echo "Analysis complete!"
echo "Errors: $ERROR_COUNT, Warnings: $WARNING_COUNT"
echo "Full output copied to clipboard"
