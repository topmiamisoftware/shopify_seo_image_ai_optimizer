#!/bin/bash

# Configuration
IMAGE_DIR="downloaded_images"
LOG_DIR="logs"
RENAMED_IMAGES_DIR="renamed-images"
LOG_FILE="$LOG_DIR/api_responses.log"
NO_PRODUCT_STRING="NO_PRODUCT_FOUND_IN_IMAGE"

# Variables you will need to adjust for your program to run correctly.
API_KEY=""
GEMINI_PROMPT="Analyze the image and tell me the **name of the product** in the image by reading its label. If the product is a hair product, append hair product to the name you return, if the product is a soap bar, then append soap bar to the name you return. If there is no product in the image, respond with ${NO_PRODUCT_STRING}."
PRODUCT_IMAGE_APPEND="products-online-and-in-miami"

API_URL="https://generativelanguage.googleapis.com/v1/models/gemini-1.5-flash:generateContent?key=${API_KEY}"

# Ensure necessary directories exist
if [ ! -d "$IMAGE_DIR" ]; then
    echo "Error: Directory '$IMAGE_DIR' not found!"
    exit 1
fi

# Log Directory
if [ ! -d "$LOG_DIR" ]; then
  mkdir -p "$LOG_DIR"
fi

# Counter to track requests
counter=0

# Start logging
echo "Starting image processing - $(date)" >> $LOG_FILE

cd $IMAGE_DIR;

# Process each image
for dir in */; do
    # First CD into the product handle directory
    echo "The product handle direcotry name: ${dir}";

    cd $dir;

    # Then, CD into each sub-directory, in this case, each sub dir would be the image order
    for subDir in */; do
      echo "The product image order directory: ${subDir}";
      # CD into dir
      cd $subDir;

      for file in *; do
        echo "The Filename: ${file}";

        # Ensure the file exists and is a valid image
        [ -f "$file" ] || continue

        echo "Processing: $dir/$subDir/$file" >> "../../../${LOG_FILE}" 

        # Convert image to base64
        BASE64_IMAGE=$(base64 -i "$file")
        echo "Log this image: $file" >> "../../../${LOG_FILE}" 

        # Send request using multipart form-data
        RESPONSE=$(curl -s -X POST "$API_URL" \
          -H "Content-Type: application/json" \
          -d '{
              "contents": [
                {
                  "parts": [
                    {
                      "text": "'"$GEMINI_PROMPT"'"
                    },
                    {
                      "inlineData": {
                        "mimeType": "image/jpeg",
                        "data": "'"$BASE64_IMAGE"'"
                      }
                    }
                  ]
                }
              ],
              "generationConfig": {
                "temperature": 0.0,
                "topP": 0.1,
                "maxOutputTokens": 300
              }
            }')
        
        # Log the raw API response
        echo "Response for $file: $RESPONSE" >> "../../../${LOG_FILE}" 

        # Extract the response text and handle potential errors
        PRODUCT_NAME=$(echo "$RESPONSE" | jq -r '.candidates[0].content.parts[0].text' 2>/dev/null)

        echo "Renamed $dir/$subDir/$file" >> "../../../${LOG_FILE}" 

        # Check if the response is valid
        if [[ -z "$PRODUCT_NAME" || "$PRODUCT_NAME" == "null" ]]; then
            echo "Error: No valid response from API for $file" | tee -a "../../../${LOG_FILE}" 
            continue
        fi

        EXT="${file##*.}"  # Get file extension

        # Rename the file if a product name is detected
        if [[ "$PRODUCT_NAME" != "$NO_PRODUCT_STRING" ]]; then
            SAFE_NAME=$(echo "$PRODUCT_NAME" | tr ' /' '-' | tr ' ' '-' |  tr -d '"' | tr -cd '[:alnum:]_-') # Sanitize filename
            NEW_NAME="Shop-for-${SAFE_NAME}-${PRODUCT_IMAGE_APPEND}.$EXT"

            # Rename the file if it's different
            if [ "$file" != "$NEW_NAME" ]; then
                mv "$file" "$NEW_NAME"
                echo "Renamed: $file -> $NEW_NAME" | tee -a "../../../${LOG_FILE}" 
            fi
        else
            # Let's rename the file to the product handle in case that we did not find the correct product name.
            SAFE_NAME=$(echo "$dir" | tr ' /' '-' | tr ' ' '-' | tr -d '"' | tr -cd '[:alnum:]_-') # Sanitize filename
            NEW_NAME="Shop-for-${SAFE_NAME}-${PRODUCT_IMAGE_APPEND}.$EXT"
            echo "No product detected in: $file" | tee -a "../../../${LOG_FILE}" 

            mv "$file" "$NEW_NAME"
            echo "Renamed to product handle: $file -> $NEW_NAME" | tee -a "../../../${LOG_FILE}"
        fi
      done;

      # CD back into product handle dir
      cd ".."
    done

    # CD back into $IMAGE_DIR
    cd ".."

    # Increment the counter
    ((counter++))

    # Throttle every 15 requests (to avoid hitting the rate limit)
    if ((counter % 15 == 0)); then
      echo "Sleeping for 60 seconds to avoid API rate limit..."
      sleep 60
    fi
done

echo "Processing complete! Log file: $LOG_FILE"