#!/usr/bin/env bash
# shellcheck disable=SC1091

set -e

# Echo all environment variables used by this script
echo "----------- OSS Upload -----------"
echo "Environment variables:"
echo "OSS_ACCESS_KEY_ID=${OSS_ACCESS_KEY_ID:0:8}..."
echo "OSS_ACCESS_KEY_SECRET=${OSS_ACCESS_KEY_SECRET:0:8}..."
echo "OSS_BUCKET_NAME=${OSS_BUCKET_NAME}"
echo "OSS_ENDPOINT=${OSS_ENDPOINT}"
echo "OSS_REGION=${OSS_REGION}"
echo "APP_NAME=${APP_NAME}"
echo "RELEASE_VERSION=${RELEASE_VERSION}"
echo "VSCODE_PLATFORM=${VSCODE_PLATFORM}"
echo "-------------------------"

# Check if OSS credentials are provided
if [[ -z "${OSS_ACCESS_KEY_ID}" ]] || [[ -z "${OSS_ACCESS_KEY_SECRET}" ]] || [[ -z "${OSS_BUCKET_NAME}" ]]; then
  echo "OSS credentials not provided, skipping OSS upload"
  exit 0
fi

# Install Alibaba Cloud CLI if not present
if ! command -v aliyun &> /dev/null; then
  echo "Installing Alibaba Cloud CLI..."
  
  # Download and install aliyun CLI
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    curl -sL https://aliyuncli.alicdn.com/aliyun-cli-linux-latest-amd64.tgz | tar -xz
    sudo mv aliyun /usr/local/bin/
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    curl -sL https://aliyuncli.alicdn.com/aliyun-cli-macosx-latest-amd64.tgz | tar -xz
    sudo mv aliyun /usr/local/bin/
  elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
    curl -sL https://aliyuncli.alicdn.com/aliyun-cli-windows-latest-amd64.zip -o aliyun-cli.zip
    unzip aliyun-cli.zip
    mv aliyun.exe /usr/local/bin/
  fi
fi

# Configure Alibaba Cloud CLI
echo "Configuring Alibaba Cloud CLI..."
aliyun configure set \
  --profile default \
  --mode AK \
  --region "${OSS_REGION}" \
  --access-key-id "${OSS_ACCESS_KEY_ID}" \
  --access-key-secret "${OSS_ACCESS_KEY_SECRET}"

# Function to upload file to OSS
upload_to_oss() {
  local file_path="$1"
  local file_name="$2"
  local platform="$3"
  
  # Determine platform-specific path
  local oss_path="${APP_NAME}/${RELEASE_VERSION}/${platform}/${file_name}"
  
  echo "Uploading ${file_name} to OSS..."
  
  # Upload file with retry logic
  for i in {1..3}; do
    if aliyun oss cp "${file_path}" "oss://${OSS_BUCKET_NAME}/${oss_path}" \
      --endpoint "https://${OSS_ENDPOINT}" \
      --include "*.zip,*.dmg,*.exe,*.msi,*.deb,*.rpm,*.tar.gz,*.AppImage,*.snap,*.sha1,*.sha256"; then
      echo "Successfully uploaded ${file_name} to OSS (attempt ${i})"
      
      # Set public read permissions
      aliyun oss set-acl "oss://${OSS_BUCKET_NAME}/${oss_path}" \
        --endpoint "https://${OSS_ENDPOINT}" \
        --acl public-read
      
      return 0
    else
      echo "Failed to upload ${file_name} to OSS (attempt ${i})"
      if [[ $i -eq 3 ]]; then
        echo "Failed to upload ${file_name} after 3 attempts"
        return 1
      fi
      sleep 10
    fi
  done
}

# Function to get platform from file name
get_platform_from_filename() {
  local filename="$1"
  
  if [[ "$filename" =~ darwin|osx ]]; then
    echo "darwin"
  elif [[ "$filename" =~ win32|windows ]]; then
    echo "win32"
  elif [[ "$filename" =~ linux ]]; then
    echo "linux"
  else
    # Default to current platform
    echo "${VSCODE_PLATFORM:-linux}"
  fi
}

# Upload assets to OSS
cd assets

echo "Starting OSS upload for all assets..."

# Upload all files
for file in *; do
  if [[ -f "$file" ]]; then
    platform=$(get_platform_from_filename "$file")
    
    echo "::group::Uploading '${file}' to OSS at $(date "+%T")"
    
    if upload_to_oss "$file" "$file" "$platform"; then
      echo "✓ Successfully uploaded ${file} to OSS"
    else
      echo "✗ Failed to upload ${file} to OSS"
      # Continue with other files even if one fails
    fi
    
    echo "::endgroup::"
  fi
done

echo "OSS upload completed!"

# Generate OSS URLs for later use
echo "Generating OSS URLs..."
mkdir -p ../oss_urls

for file in *; do
  if [[ -f "$file" ]] && [[ "$file" != *.sha1 ]] && [[ "$file" != *.sha256 ]]; then
    platform=$(get_platform_from_filename "$file")
    oss_url="https://${OSS_BUCKET_NAME}.${OSS_ENDPOINT}/${APP_NAME}/${RELEASE_VERSION}/${platform}/${file}"
    echo "$oss_url" >> "../oss_urls/${file}.url"
    echo "OSS URL for ${file}: ${oss_url}"
  fi
done

cd ..