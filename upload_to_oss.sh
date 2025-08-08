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

# Install ossutil 2.0 if not present
if ! command -v ossutil &> /dev/null; then
  echo "Installing ossutil 2.0..."
  
  # Download and install ossutil 2.1.1
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if [[ "$(uname -m)" == "x86_64" ]]; then
      curl -sL https://gosspublic.alicdn.com/ossutil/v2/2.1.1/ossutil-2.1.1-linux-amd64.zip -o ossutil.zip
      unzip ossutil.zip
      chmod 755 ossutil-v2.1.1-linux-amd64/ossutil
      sudo mv ossutil-v2.1.1-linux-amd64/ossutil /usr/local/bin/
      rm -rf ossutil.zip ossutil-v2.1.1-linux-amd64
    else
      curl -sL https://gosspublic.alicdn.com/ossutil/v2/2.1.1/ossutil-2.1.1-linux-arm64.zip -o ossutil.zip
      unzip ossutil.zip
      chmod 755 ossutil-2.1.1-linux-arm64/ossutil
      sudo mv ossutil-2.1.1-linux-arm64/ossutil /usr/local/bin/
      rm -rf ossutil.zip ossutil-2.1.1-linux-arm64
    fi
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    if [[ "$(uname -m)" == "x86_64" ]]; then
      # macOS Intel
      curl -sL https://gosspublic.alicdn.com/ossutil/v2/2.1.2/ossutil-2.1.2-mac-amd64.zip -o ossutil.zip
      unzip ossutil.zip
      chmod 755 ossutil-2.1.2-mac-amd64/ossutil
      sudo mv ossutil-2.1.2-mac-amd64/ossutil /usr/local/bin/
      rm -rf ossutil.zip ossutil-2.1.2-mac-amd64
    else
      # macOS Apple Silicon
      curl -sL https://gosspublic.alicdn.com/ossutil/v2/2.1.2/ossutil-2.1.2-mac-arm64.zip -o ossutil.zip
      unzip ossutil.zip
      chmod 755 ossutil-2.1.2-mac-arm64/ossutil
      sudo mv ossutil-2.1.2-mac-arm64/ossutil /usr/local/bin/
      rm -rf ossutil.zip ossutil-2.1.2-mac-arm64
    fi
  elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
    curl -sL https://gosspublic.alicdn.com/ossutil/v2/2.1.1/ossutil-2.1.1-windows-amd64-go1.20.zip -o ossutil.zip
    unzip ossutil.zip
    # Create local bin directory if it doesn't exist and move ossutil there
    mkdir -p "./bin"
    mv ossutil-2.1.1-windows-amd64-go1.20/ossutil.exe ./bin/
    # Add local bin to PATH for current session
    export PATH="$(pwd)/bin:$PATH"
    rm -rf ossutil.zip ossutil-2.1.1-windows-amd64-go1.20
  fi
fi

# Function to upload file to OSS
upload_to_oss() {
  local file_path="$1"
  local file_name="$2"
  local platform="$3"
  
  # Determine platform-specific path
  local oss_path="${APP_NAME}/${RELEASE_VERSION}/${platform}/${file_name}"
  
  echo "Uploading ${file_name} to OSS..."
  
  # Upload file with retry logic using ossutil 2.0 with command line options
  for i in {1..3}; do
    if ossutil cp "${file_path}" "oss://${OSS_BUCKET_NAME}/${oss_path}" \
      --access-key-id "${OSS_ACCESS_KEY_ID}" \
      --access-key-secret "${OSS_ACCESS_KEY_SECRET}" \
      --endpoint "https://${OSS_ENDPOINT}"; then
      echo "Successfully uploaded ${file_name} to OSS (attempt ${i})"
      
      # Set public read permissions
      ossutil set-acl "oss://${OSS_BUCKET_NAME}/${oss_path}" public-read \
        --access-key-id "${OSS_ACCESS_KEY_ID}" \
        --access-key-secret "${OSS_ACCESS_KEY_SECRET}" \
        --endpoint "https://${OSS_ENDPOINT}"
      
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

# Function to get platform from environment variable
get_platform() {
  # Use VSCODE_PLATFORM environment variable if set, otherwise default to linux
  echo "${VSCODE_PLATFORM:-linux}"
}

# Upload assets to OSS
cd assets

echo "Starting OSS upload for all assets..."
echo "Using platform: $(get_platform)"

# Upload all files
for file in *; do
  if [[ -f "$file" ]]; then
    platform=$(get_platform)
    
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
    platform=$(get_platform)
    # Prefer custom public download domain when provided, fallback to default bucket endpoint
    if [[ -n "${PUBLIC_DOWNLOAD_DOMAIN}" ]]; then
      base_url="https://${PUBLIC_DOWNLOAD_DOMAIN}"
    else
      base_url="https://${OSS_BUCKET_NAME}.${OSS_ENDPOINT}"
    fi
    oss_url="${base_url}/${APP_NAME}/${RELEASE_VERSION}/${platform}/${file}"
    echo "$oss_url" >> "../oss_urls/${file}.url"
    echo "OSS URL for ${file}: ${oss_url}"
  fi
done

cd ..