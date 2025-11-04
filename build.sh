#!/bin/bash

# Variables
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
EXPORT_DIR="export"
ERROR_LOG="error.log"

# Get the current commit short hash
COMMIT_HASH=$(git rev-parse --short HEAD)

# Define the filename
FILENAME="mac_${COMMIT_HASH}.apk"

# Function to copy build to export folder
copy_to_export() {
  echo "Preparing export folder..."
  
  # Clear export folder if it exists and is not empty
  if [ -d "$EXPORT_DIR" ] && [ "$(ls -A $EXPORT_DIR)" ]; then
    echo "Clearing existing export folder..."
    rm -rf "$EXPORT_DIR"/*
  fi
  
  # Create export folder if it doesn't exist
  mkdir -p "$EXPORT_DIR"
  
  # Copy APK to export folder with new filename
  echo "Copying APK to export folder as $FILENAME..."
  cp "$APK_PATH" "$EXPORT_DIR/$FILENAME"
  
  if [ $? -eq 0 ]; then
    echo "Copy successful! APK saved to $EXPORT_DIR/$FILENAME"
  else
    echo "Copy failed."
    exit 1
  fi
}

# Run flutter build apk and capture errors
echo "Building Flutter APK..."
flutter build apk 2> >(tee "$ERROR_LOG")

# Check if the build was successful
if [ $? -eq 0 ]; then
  echo "Build successful! APK generated at $APK_PATH"
  # cs clip write "$FILENAME"
  # Copy to export folder
  copy_to_export
else
  echo "Build failed. Check $ERROR_LOG for details."
  exit 1
fi