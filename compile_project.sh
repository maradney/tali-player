#!/bin/bash

# Check if a directory is provided as an argument
if [ -z "$1" ]; then
  echo "Usage: $0 <directory>"
  exit 1
fi

# Directory containing the files to concatenate
DIRECTORY="$1"

# Output file where the contents will be saved
OUTPUT_FILE="project_progress.txt"

# Check if the directory exists
if [ ! -d "$DIRECTORY" ]; then
  echo "Directory not found: $DIRECTORY"
  exit 1
fi

# Clear or create the output file
> "$OUTPUT_FILE"

# Function to recursively concatenate files in a directory
concatenate_files() {
  local dir="$1"
  for entry in "$dir"/*; do
    if [ -f "$entry" ]; then
      # Add the file path as a separator
      echo "File: $entry" >> "$OUTPUT_FILE"
      # Append the file content to the output file
      cat "$entry" >> "$OUTPUT_FILE"
      # Add a blank line for separation between files
      echo "" >> "$OUTPUT_FILE"
    elif [ -d "$entry" ]; then
      # Recursively process subdirectories
      concatenate_files "$entry"
    fi
  done
}

# Start concatenating files from the specified directory
concatenate_files "$DIRECTORY"

echo "Project progress has been compiled into $OUTPUT_FILE"
