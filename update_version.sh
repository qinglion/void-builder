#!/usr/bin/env bash
# shellcheck disable=SC1091

set -e

# Echo all environment variables used by this script
echo "----------- release -----------"
echo "Environment variables:"
echo "SHOULD_BUILD=${SHOULD_BUILD}"
echo "FORCE_UPDATE=${FORCE_UPDATE}"

echo "GH_TOKEN=${GH_TOKEN}"
echo "GITHUB_TOKEN=${GITHUB_TOKEN}"
echo "GH_ENTERPRISE_TOKEN=${GH_ENTERPRISE_TOKEN}"
echo "GITHUB_ENTERPRISE_TOKEN=${GITHUB_ENTERPRISE_TOKEN}"
echo "-------------------------"

if [[ "${SHOULD_BUILD}" != "yes" && "${FORCE_UPDATE}" != "true" ]]; then
  echo "Will not update version JSON because we did not build"
  exit 0
fi

if [[ -z "${GH_TOKEN}" ]] && [[ -z "${GITHUB_TOKEN}" ]] && [[ -z "${GH_ENTERPRISE_TOKEN}" ]] && [[ -z "${GITHUB_ENTERPRISE_TOKEN}" ]]; then
  echo "Will not update version JSON because no GITHUB_TOKEN defined"
  exit 0
else
  GITHUB_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-${GH_ENTERPRISE_TOKEN:-${GITHUB_ENTERPRISE_TOKEN}}}}"
fi

# Support for GitHub Enterprise
GH_HOST="${GH_HOST:-github.com}"

if [[ "${FORCE_UPDATE}" == "true" ]]; then
  . version.sh
fi

if [[ -z "${BUILD_SOURCEVERSION}" ]]; then
  echo "Will not update version JSON because no BUILD_SOURCEVERSION defined"
  exit 0
fi

# if [[ "${VSCODE_ARCH}" == "ppc64le" ]] || [[ "${VSCODE_ARCH}" == "riscv64" ]] ; then
#   echo "Skip PPC64LE since only reh is published"
#   exit 0
# fi

#  {
#    "url": "https://az764295.vo.msecnd.net/stable/51b0b28134d51361cf996d2f0a1c698247aeabd8/VSCode-darwin-stable.zip",
#    "name": "1.33.1",
#    "version": "51b0b28134d51361cf996d2f0a1c698247aeabd8",
#    "productVersion": "1.33.1",
#    "hash": "cb4109f196d23b9d1e8646ce43145c5bb62f55a8",
#    "timestamp": 1554971059007,
#    "sha256hash": "ac2a1c8772501732cd5ff539a04bb4dc566b58b8528609d2b34bbf970d08cf01"
#  }

# `url` is URL_BASE + filename of asset e.g.
#    darwin: https://github.com/${ASSETS_REPOSITORY}/releases/download/${RELEASE_VERSION}/${APP_NAME}-darwin-${RELEASE_VERSION}.zip
# `name` is $RELEASE_VERSION
# `version` is $BUILD_SOURCEVERSION
# `productVersion` is $RELEASE_VERSION
# `hash` in <filename>.sha1
# `timestamp` is $(node -e 'console.log(Date.now())')
# `sha256hash` in <filename>.sha256

REPOSITORY_NAME="${VERSIONS_REPOSITORY/*\//}"
URL_BASE="https://${GH_HOST}/${ASSETS_REPOSITORY}/releases/download/${RELEASE_VERSION}"

generateJson() {
  local url name version productVersion sha1hash sha256hash timestamp oss_url
  JSON_DATA="{}"

  # Determine platform for OSS path
  local platform=""
  if [[ "${OS_NAME}" == "osx" ]]; then
    platform="darwin"
  elif [[ "${OS_NAME}" == "windows" ]]; then
    platform="win32"
  else
    platform="linux"
  fi

  # Generate OSS CDN URL as primary URL
  if [[ -n "${OSS_BUCKET_NAME}" ]] && [[ -n "${OSS_ENDPOINT}" ]]; then
    # Use OSS CDN URL as primary URL for better global access
    url="https://d.qinglion.com/${APP_NAME}/${RELEASE_VERSION}/${platform}/${ASSET_NAME}"
  else
    # Fallback to GitHub Release URL if OSS is not configured
    url="${URL_BASE}/${ASSET_NAME}"
  fi

  name="${RELEASE_VERSION}"
  version="${BUILD_SOURCEVERSION}"
  productVersion="$( transformVersion "${RELEASE_VERSION}" )"
  timestamp=$( node -e 'console.log(Date.now())' )

  if [[ ! -f "assets/${ASSET_NAME}" ]]; then
    echo "Downloading asset '${ASSET_NAME}'"
    gh release download --repo "${ASSETS_REPOSITORY}" "${RELEASE_VERSION}" --dir "assets" --pattern "${ASSET_NAME}*"
  fi

  sha1hash=$( awk '{ print $1 }' "assets/${ASSET_NAME}.sha1" )
  sha256hash=$( awk '{ print $1 }' "assets/${ASSET_NAME}.sha256" )

  # Generate OSS URL for backup (keeping the original OSS URL format)
  oss_url=""
  if [[ -n "${OSS_BUCKET_NAME}" ]] && [[ -n "${OSS_ENDPOINT}" ]]; then
    oss_url="https://${OSS_BUCKET_NAME}.${OSS_ENDPOINT}/${APP_NAME}/${RELEASE_VERSION}/${platform}/${ASSET_NAME}"
  fi

  # check that nothing is blank (blank indicates something awry with build)
  for key in url name version productVersion sha1hash timestamp sha256hash; do
    if [[ -z "${key}" ]]; then
      echo "Variable '${key}' is empty; exiting..."
      exit 1
    fi
  done

  # generate json with OSS URL if available
  if [[ -n "${oss_url}" ]]; then
    JSON_DATA=$( jq \
      --arg url             "${url}" \
      --arg name            "${name}" \
      --arg version         "${version}" \
      --arg productVersion  "${productVersion}" \
      --arg hash            "${sha1hash}" \
      --arg timestamp       "${timestamp}" \
      --arg sha256hash      "${sha256hash}" \
      --arg oss_url         "${oss_url}" \
      '. | .url=$url | .name=$name | .version=$version | .productVersion=$productVersion | .hash=$hash | .timestamp=$timestamp | .sha256hash=$sha256hash | .oss_url=$oss_url' \
      <<<'{}' )
  else
    JSON_DATA=$( jq \
      --arg url             "${url}" \
      --arg name            "${name}" \
      --arg version         "${version}" \
      --arg productVersion  "${productVersion}" \
      --arg hash            "${sha1hash}" \
      --arg timestamp       "${timestamp}" \
      --arg sha256hash      "${sha256hash}" \
      '. | .url=$url | .name=$name | .version=$version | .productVersion=$productVersion | .hash=$hash | .timestamp=$timestamp | .sha256hash=$sha256hash' \
      <<<'{}' )
  fi
}

transformVersion() {
  local version parts

  version="${1%-insider}"

  IFS='.' read -r -a parts <<< "${version}"

  # Remove leading zeros from third part
  parts[2]="$((10#${parts[2]}))"

  version="${parts[0]}.${parts[1]}.${parts[2]}.0"

  if [[ "${1}" == *-insider ]]; then
    version="${version}-insider"
  fi

  echo "${version}"
}

updateLatestVersion() {
  echo "Updating ${VERSION_PATH}/latest.json"

  # do not update the same version
  if [[ -f "${REPOSITORY_NAME}/${VERSION_PATH}/latest.json" ]]; then
    CURRENT_VERSION=$( jq -r '.name' "${REPOSITORY_NAME}/${VERSION_PATH}/latest.json" )
    echo "CURRENT_VERSION: ${CURRENT_VERSION}"

    if [[ "${CURRENT_VERSION}" == "${RELEASE_VERSION}" && "${FORCE_UPDATE}" != "true" ]]; then
      return 0
    fi
  fi

  echo "Generating ${VERSION_PATH}/latest.json"

  mkdir -p "${REPOSITORY_NAME}/${VERSION_PATH}"

  generateJson

  echo "${JSON_DATA}" > "${REPOSITORY_NAME}/${VERSION_PATH}/latest.json"

  echo "${JSON_DATA}"
}

# init versions repo for later commiting + pushing the json file to it
# thank you https://www.vinaygopinath.me/blog/tech/commit-to-master-branch-on-github-using-travis-ci/
git clone "https://${GH_HOST}/${VERSIONS_REPOSITORY}.git"
cd "${REPOSITORY_NAME}" || { echo "'${REPOSITORY_NAME}' dir not found"; exit 1; }
git config user.email "$( echo "${GITHUB_USERNAME}" | awk '{print tolower($0)}' )-ci@not-real.com"
git config user.name "${GITHUB_USERNAME} CI"
git remote rm origin
git remote add origin "https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@${GH_HOST}/${VERSIONS_REPOSITORY}.git" &> /dev/null
cd ..

if [[ "${OS_NAME}" == "osx" ]]; then
  ASSET_NAME="${APP_NAME}-darwin-${VSCODE_ARCH}-${RELEASE_VERSION}.zip"
  VERSION_PATH="${VSCODE_QUALITY}/darwin/${VSCODE_ARCH}"
  updateLatestVersion
elif [[ "${OS_NAME}" == "windows" ]]; then
  # system installer
  ASSET_NAME="${APP_NAME}Setup-${VSCODE_ARCH}-${RELEASE_VERSION}.exe"
  VERSION_PATH="${VSCODE_QUALITY}/win32/${VSCODE_ARCH}/system"
  updateLatestVersion

  # user installer
  ASSET_NAME="${APP_NAME}UserSetup-${VSCODE_ARCH}-${RELEASE_VERSION}.exe"
  VERSION_PATH="${VSCODE_QUALITY}/win32/${VSCODE_ARCH}/user"
  updateLatestVersion

  # windows archive
  ASSET_NAME="${APP_NAME}-win32-${VSCODE_ARCH}-${RELEASE_VERSION}.zip"
  VERSION_PATH="${VSCODE_QUALITY}/win32/${VSCODE_ARCH}/archive"
  updateLatestVersion

  if [[ "${VSCODE_ARCH}" == "ia32" || "${VSCODE_ARCH}" == "x64" ]]; then
    # msi
    ASSET_NAME="${APP_NAME}-${VSCODE_ARCH}-${RELEASE_VERSION}.msi"
    VERSION_PATH="${VSCODE_QUALITY}/win32/${VSCODE_ARCH}/msi"
    updateLatestVersion

    # updates-disabled msi
    ASSET_NAME="${APP_NAME}-${VSCODE_ARCH}-updates-disabled-${RELEASE_VERSION}.msi"
    VERSION_PATH="${VSCODE_QUALITY}/win32/${VSCODE_ARCH}/msi-updates-disabled"
    updateLatestVersion
  fi
else # linux
  # update service links to tar.gz file
  # see https://update.code.visualstudio.com/api/update/linux-x64/stable/VERSION
  # as examples
  ASSET_NAME="${APP_NAME}-linux-${VSCODE_ARCH}-${RELEASE_VERSION}.tar.gz"
  VERSION_PATH="${VSCODE_QUALITY}/linux/${VSCODE_ARCH}"
  updateLatestVersion
fi

cd "${REPOSITORY_NAME}" || { echo "'${REPOSITORY_NAME}' dir not found"; exit 1; }

# Void made master into main (why would anyone change from main -> master??)
git pull origin main # in case another build just pushed
git add .

CHANGES=$( git status --porcelain )

if [[ -n "${CHANGES}" ]]; then
  echo "Some changes have been found, pushing them"

  dateAndMonth=$( date "+%D %T" )

  git commit -m "CI update: ${dateAndMonth} (Build ${GITHUB_RUN_NUMBER})"

  if ! git push origin main --quiet; then
    git pull origin main
    git push origin main --quiet
  fi
else
  echo "No changes"
fi

cd ..
