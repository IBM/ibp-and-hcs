#!/bin/bash

CHANNEL_NAME="${1:-appchannel}"
CC_SRC_LANGUAGE="golang"
TIMEOUT=30

COUNTER=1
MAX_RETRY=20
PACKAGE_ID=""

CC_RUNTIME_LANGUAGE=golang
CC_SRC_PATH="/opt/fabric/chaincode/abstore/go/"
CHANNEL_TX_FILE="/opt/fabric/channel-artifacts/channel.tx"

echo "Channel name : "$CHANNEL_NAME

# import utils
. scripts/utils.sh

## sign the channel create tx
signChannelCreateTx

## Create channel
echo "Creating channel..."
createChannel

## Join all the peers to the channel
echo "Having all peers join the channel..."
joinChannelWithRetry

# when channel create tx is generated as a diff over the base profile, anchor peer configs
# are alreay added, so we skip the next two steps
## Set the anchor peers for each org in the channel
# echo "Updating anchor peers for org1..."
# updateAnchorPeers 0 1
# echo "Updating anchor peers for org2..."
# updateAnchorPeers 0 2

## at first we package the chaincode
packageChaincode 1

## Install chaincode on peer1.org1
echo "Installing chaincode on peer1.org1..."
installChaincode

## query whether the chaincode is installed
queryInstalled

## approve the definition for org1
approveForMyOrg 1

## check whether the chaincode definition is ready to be committed
checkCommitReadiness 1 "\"Org1MSP\": true"

## now that we know for sure both orgs have approved, commit the definition
commitChaincodeDefinition 1

## query on both orgs to see that the definition committed successfully
queryCommitted 1

# invoke init
chaincodeInvoke 1

# Query chaincode on peer0.org1
echo "Querying chaincode on peer1.org1..."
chaincodeQuery 100

	# Invoke chaincode on peer0.org1 and peer0.org2
echo "Sending invoke transaction on peer0.org1 peer0.org2..."
chaincodeInvoke 0

# Query chaincode on peer1.org1
echo "Querying chaincode on peer0.org1..."
chaincodeQuery 90

echo
echo "========= All DONE ======== "
echo

echo
echo " _____   _   _   ____   "
echo "| ____| | \ | | |  _ \  "
echo "|  _|   |  \| | | | | | "
echo "| |___  | |\  | | |_| | "
echo "|_____| |_| \_| |____/  "
echo

exit 0
