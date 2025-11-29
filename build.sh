#!/bin/bash

# Variables
APK_DIR="build/app/outputs/flutter-apk"
EXPORT_DIR="export"
ABI_SUBDIR="$EXPORT_DIR/abis"
ERROR_LOG="error.log"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
ENDCOLOR="\033[0m"

# Get the current directory name and first 3 letters
CURRENT_DIR=$(basename "$PWD")
DIR_PREFIX=$(echo "$CURRENT_DIR" | cut -c1-3)

# Get the current commit short hash
COMMIT_HASH=$(git rev-parse --short HEAD)

# Define the filename using directory prefix
FILENAME="${DIR_PREFIX}_${COMMIT_HASH}.apk"

# Function to show usage
show_usage() {
    echo "Usage: $0 [--split]"
    echo "  --split    Build with ABI splitting (generates multiple APKs for different architectures)"
    echo "  (no flag)  Build single universal APK"
    exit 1
}

# Function to clear and setup export directories for split build
setup_export_dirs_split() {
    echo "Preparing export directories..."
    
    # Clear export folder completely
    if [ -d "$EXPORT_DIR" ]; then
        echo "Clearing existing export folder..."
        rm -rf "$EXPORT_DIR"
    fi
    
    # Create export and abi subdirectory
    mkdir -p "$EXPORT_DIR"
    mkdir -p "$ABI_SUBDIR"
}

# Function to clear and setup export directories for single build
setup_export_dirs_single() {
    echo "Preparing export folder..."
    
    # Clear export folder if it exists and is not empty
    if [ -d "$EXPORT_DIR" ] && [ "$(ls -A $EXPORT_DIR)" ]; then
        echo "Clearing existing export folder..."
        rm -rf "$EXPORT_DIR"/*
    fi
    
    # Create export folder if it doesn't exist
    mkdir -p "$EXPORT_DIR"
}

# Function to copy APKs for split build
copy_apks_split() {
    # Copy main arm64-v8a APK to export root
    SOURCE_APK="$APK_DIR/app-arm64-v8a-release.apk"
    
    # Verify the arm64 APK exists
    if [ ! -f "$SOURCE_APK" ]; then
        echo -e "${RED}Error: arm64-v8a APK not found at $SOURCE_APK${ENDCOLOR}"
        echo "Available APKs:"
        ls -la "$APK_DIR"/*.apk 2>/dev/null || echo "No APKs found"
        exit 1
    fi
    
    # Copy main APK to export folder with new filename
    echo -e "Copying main APK to export folder as ${GREEN}$FILENAME${ENDCOLOR}..."
    cp "$SOURCE_APK" "$EXPORT_DIR/$FILENAME"
    
    if [ $? -eq 0 ]; then
        echo "Main APK saved to $EXPORT_DIR/$FILENAME"
        echo "This is the arm64-v8a version (for Samsung S10e and modern Android devices)"
    else
        echo -e "${RED}Main APK copy failed.${ENDCOLOR}"
        exit 1
    fi
    
    # Copy all ABI APKs to abi subfolder
    echo "Copying all ABI versions to $ABI_SUBDIR..."
    for apk in "$APK_DIR"/app-*-release.apk; do
        if [ -f "$apk" ]; then
            apk_name=$(basename "$apk")
            cp "$apk" "$ABI_SUBDIR/$apk_name"
            echo "  - $apk_name"
        fi
    done
    
    # Verify copies
    echo -e "\nABI versions available in $ABI_SUBDIR:"
    ls -la "$ABI_SUBDIR"/*.apk 2>/dev/null && echo "All ABI APKs copied successfully!" || echo "No ABI APKs found"
}

# Function to copy APK for single build
copy_apk_single() {
    SOURCE_APK="$APK_DIR/app-release.apk"
    
    # Verify the APK exists
    if [ ! -f "$SOURCE_APK" ]; then
        echo -e "${RED}Error: APK not found at $SOURCE_APK${ENDCOLOR}"
        exit 1
    fi
    
    # Copy APK to export folder with new filename
    echo -e "Copying APK to export folder as ${YELLOW}$FILENAME${ENDCOLOR}..."
    cp "$SOURCE_APK" "$EXPORT_DIR/$FILENAME"
    
    if [ $? -eq 0 ]; then
        echo "Copy successful! APK saved to $EXPORT_DIR/$FILENAME"
    else
        echo -e "${RED}Copy failed.${ENDCOLOR}"
        exit 1
    fi
}

# Main script logic
SPLIT_MODE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --split)
            SPLIT_MODE=true
            shift
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${ENDCOLOR}"
            show_usage
            ;;
    esac
done

if [ "$SPLIT_MODE" = true ]; then
    echo "Building Flutter APK with ABI splitting..."
    flutter build apk --split-per-abi 2> >(tee "$ERROR_LOG")
    
    # Check if the build was successful
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Build successful! APKs generated in $APK_DIR${ENDCOLOR}"
        echo "Available APKs:"
        ls -la "$APK_DIR"/*.apk
        
        # Setup directories and copy APKs
        setup_export_dirs_split
        copy_apks_split
        
        echo -e "\n${GREEN}Export complete!${ENDCOLOR}"
        echo -e "\nMain APK:${YELLOW} $EXPORT_DIR/$FILENAME ${ENDCOLOR}"
        
    else
        echo -e "${RED}Build failed. Check $ERROR_LOG for details.${ENDCOLOR}"
        exit 1
    fi
else
    echo "Building Flutter APK (universal)..."
    flutter build apk 2> >(tee "$ERROR_LOG")
    
    # Check if the build was successful
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Build successful! APK generated at $APK_DIR/app-release.apk${ENDCOLOR}"
        
        # Setup directories and copy APK
        setup_export_dirs_single
        copy_apk_single
        
        echo -e "\n${GREEN}Export complete!${ENDCOLOR}"
        echo -e "\nAPK:${YELLOW} $EXPORT_DIR/$FILENAME ${ENDCOLOR}"
        
    else
        echo -e "${RED}Build failed. Check $ERROR_LOG for details.${ENDCOLOR}"
        exit 1
    fi
fi