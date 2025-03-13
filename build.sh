#!/bin/bash

# Variables
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
ERROR_LOG="error.log"
DOWNLOAD_FILE="download.log" # File to store the bashupload URL

# Get the current commit short hash
COMMIT_HASH=$(git rev-parse --short HEAD)

# Define the filename
FILENAME="mac_${COMMIT_HASH}.apk"

# Function to upload to bashupload.com
upload_to_bashupload() {
  echo "Uploading file to bashupload.com as $FILENAME..."
  UPLOAD_URL=$(curl -o /tmp/_bu.tmp -# "https://bashupload.com/$FILENAME" --data-binary @"$APK_PATH" && cat /tmp/_bu.tmp && rm /tmp/_bu.tmp)
  if [ $? -eq 0 ]; then
    echo "Upload successful! Download URL: $UPLOAD_URL"
    # Write the URL to download.txt
    echo "$UPLOAD_URL" > "$DOWNLOAD_FILE"
    echo "Download URL saved to $DOWNLOAD_FILE"
  else
    echo "Upload failed."
    exit 1
  fi
}

# Run flutter build apk and capture errors
echo "Building Flutter APK..."
flutter build apk 2> >(tee "$ERROR_LOG")

# Check if the build was successful
if [ $? -eq 0 ]; then
  echo "Build successful! APK generated at $APK_PATH"
  # Ask user if they want to upload
  read -p "Do you want to upload the file to bashupload.com? (y/n): " UPLOAD_CHOICE
  if [[ "$UPLOAD_CHOICE" == "y" || "$UPLOAD_CHOICE" == "Y" ]]; then
    upload_to_bashupload
  else
    echo "Upload canceled."
    exit 0
  fi
else
  echo "Build failed. Check $ERROR_LOG for details."
  exit 1
fi