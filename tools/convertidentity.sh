#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

if [ "$#" -ne 2 ]; then
    echo "Must provide the identity json file and output folder name"
    exit 1
fi

IDENTITY_FILE="$1"
OUTPUT_DIR="$2"

ID_NAME=$(jq -r '.name' "$IDENTITY_FILE")
ID_TYPE=$(jq -r '.type' "$IDENTITY_FILE")
ID_PK=$(jq -r '.private_key' "$IDENTITY_FILE")
ID_CERT=$(jq -r '.cert' "$IDENTITY_FILE")

if [ "$ID_TYPE" != "identity" ]; then
    echo "$IDENTITY_FILE not an identity file"
    exit 1
fi

echo "Extracting identity folder for $ID_NAME ..."

rm -fr "${OUTPUT_DIR}"

mkdir -p "${OUTPUT_DIR}/signcerts"
echo $ID_CERT | base64 -d > "${OUTPUT_DIR}/signcerts/cert.pem"

mkdir -p "${OUTPUT_DIR}/keystore"
echo $ID_PK | base64 -d > "${OUTPUT_DIR}/keystore/priv_sk"

echo "Done, files are saved to ${OUTPUT_DIR}"
