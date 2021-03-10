#!/bin/bash

SCRIPT_DIR=$(cd `dirname $0` && pwd)
. $SCRIPT_DIR/utils.sh

setOrg1Globals

KEY=$1
VAL=$2

# update the value of key
CTOR_STR=$(jq -n --arg key "$KEY" --arg val "$VAL" '{Args: ["createMetadata", $key, $val]}')
peer chaincode invoke -n fotoweb -C appchannel -c "$CTOR_STR" --peerAddresses $CORE_PEER_ADDRESS \
    --tlsRootCertFiles $PEER1_ORG1_CA -o $ORDERER_ADDRESS --tls --cafile $ORDERER_CA

if [ $? -ne 0 ]; then
    echo "failed to invoke chaincode to create/update metadata"
    exit 1
fi

CTOR_STR=$(jq -n --arg key "$KEY" '{Args: ["queryMetadata", $key]}')
while true; do
    OUTPUT=$(peer chaincode query -n fotoweb -C appchannel -c "$CTOR_STR" --peerAddresses $CORE_PEER_ADDRESS --tlsRootCertFiles $PEER1_ORG1_CA)
    echo $OUTPUT
    echo $OUTPUT | grep -o "$VAL"
    if [ $? -eq 0 ]; then
        exit 0
    fi
done
