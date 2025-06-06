#!/usr/bin/env bash
# shellcheck disable=SC1091

set -ex

# Echo all environment variables used by this script
echo "----------- release -----------"
echo "Environment variables:"
echo "GH_TOKEN=${GH_TOKEN}"
echo "GITHUB_TOKEN=${GITHUB_TOKEN}"
echo "GH_ENTERPRISE_TOKEN=${GH_ENTERPRISE_TOKEN}"
echo "GITHUB_ENTERPRISE_TOKEN=${GITHUB_ENTERPRISE_TOKEN}"
echo "-------------------------"

if [[ -z "${GH_TOKEN}" ]] && [[ -z "${GITHUB_TOKEN}" ]] && [[ -z "${GH_ENTERPRISE_TOKEN}" ]] && [[ -z "${GITHUB_ENTERPRISE_TOKEN}" ]]; then
  echo "Will not release because no GITHUB_TOKEN defined"
  exit
fi

REPOSITORY_OWNER="${ASSETS_REPOSITORY/\/*/}"
REPOSITORY_NAME="${ASSETS_REPOSITORY/*\//}"

npm install -g github-release-cli

if [[ $( gh release view "${RELEASE_VERSION}" --repo "${ASSETS_REPOSITORY}" 2>&1 ) =~ "release not found" ]]; then
  echo "Creating release '${RELEASE_VERSION}'"

  if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
    NOTES="update vscode to [${MS_COMMIT}](https://github.com/microsoft/vscode/tree/${MS_COMMIT})"

    gh release create "${RELEASE_VERSION}" --repo "${ASSETS_REPOSITORY}" --title "${VOID_VERSION}" --notes "${NOTES}"
  else
    gh release create "${RELEASE_VERSION}" --repo "${ASSETS_REPOSITORY}" --title "${VOID_VERSION}" --generate-notes

    . ./utils.sh

    RELEASE_NOTES=$( gh release view "${RELEASE_VERSION}" --repo "${ASSETS_REPOSITORY}" --json "body" --jq ".body" )

    replace "s|MS_TAG_SHORT|$( echo "${MS_TAG//./_}" | cut -d'_' -f 1,2 )|" release_notes.txt
    replace "s|MS_TAG|${MS_TAG}|" release_notes.txt
    replace "s|RELEASE_VERSION|${RELEASE_VERSION}|g" release_notes.txt
    replace "s|VOID_VERSION|${VOID_VERSION}|g" release_notes.txt
    replace "s|RELEASE_NOTES|${RELEASE_NOTES//$'\n'/\\n}|" release_notes.txt

    gh release edit "${RELEASE_VERSION}" --repo "${ASSETS_REPOSITORY}" --notes-file release_notes.txt
  fi
fi

cd assets

set +e

for FILE in *; do
  if [[ -f "${FILE}" ]] && [[ "${FILE}" != *.sha1 ]] && [[ "${FILE}" != *.sha256 ]]; then
    echo "::group::Uploading '${FILE}' at $( date "+%T" )"
    gh release upload --repo "${ASSETS_REPOSITORY}" "${RELEASE_VERSION}" "${FILE}" "${FILE}.sha1" "${FILE}.sha256"

    EXIT_STATUS=$?
    echo "exit: ${EXIT_STATUS}"

    if (( "${EXIT_STATUS}" )); then
      for (( i=0; i<10; i++ )); do
        github-release delete --owner "${REPOSITORY_OWNER}" --repo "${REPOSITORY_NAME}" --tag "${RELEASE_VERSION}" "${FILE}" "${FILE}.sha1" "${FILE}.sha256"

        sleep $(( 15 * (i + 1)))

        echo "RE-Uploading '${FILE}' at $( date "+%T" )"
        gh release upload --repo "${ASSETS_REPOSITORY}" "${RELEASE_VERSION}" "${FILE}" "${FILE}.sha1" "${FILE}.sha256"

        EXIT_STATUS=$?
        echo "exit: ${EXIT_STATUS}"

        if ! (( "${EXIT_STATUS}" )); then
          break
        fi
      done
      echo "exit: ${EXIT_STATUS}"

      if (( "${EXIT_STATUS}" )); then
        echo "'${FILE}' hasn't been uploaded!"

        github-release delete --owner "${REPOSITORY_OWNER}" --repo "${REPOSITORY_NAME}" --tag "${RELEASE_VERSION}" "${FILE}" "${FILE}.sha1" "${FILE}.sha256"

        exit 1
      fi
    fi

    echo "::endgroup::"
  fi
done

cd ..
