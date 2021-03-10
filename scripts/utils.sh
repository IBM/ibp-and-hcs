PATH=$PATH:$GOPATH/bin
ORDERER_CA=/opt/fabric/crypto/ordererorg/orderers/orderer1/msp/tlscacerts/tlsca-cert.pem
PEER1_ORG1_CA=/opt/fabric/crypto/org1/msp/tlscacerts/tlsca-cert.pem
CORE_PEER_ADDRESS=$(yq r configtx.yaml 'Organizations[1].AnchorPeers[0].Host')":7051"
ORDERER_ADDRESS=$(yq r configtx.yaml 'Orderer.Addresses[0]')
PEER_CONN_PARMS="--peerAddresses $CORE_PEER_ADDRESS --tlsRootCertFiles $PEER1_ORG1_CA"

# Set OrdererOrg.Admin globals
setOrdererGlobals() {
  CORE_PEER_LOCALMSPID="OrdererMSP"
  CORE_PEER_TLS_ROOTCERT_FILE=$ORDERER_CA
  CORE_PEER_MSPCONFIGPATH=/opt/fabric/crypto/ordererorg/users/Admin@OrdererOrg/msp
}

setOrg1Globals() {
  CORE_PEER_LOCALMSPID="Org1MSP"
  CORE_PEER_TLS_ROOTCERT_FILE=$PEER1_ORG1_CA
  CORE_PEER_MSPCONFIGPATH=/opt/fabric/crypto/org1/users/Admin@Org1/msp
}

# verify the result of the end-to-end test
verifyResult() {
  if [ $1 -ne 0 ]; then
    echo "!!!!!!!!!!!!!!! "$2" !!!!!!!!!!!!!!!!"
    echo "========= ERROR !!! FAILED to execute End-2-End Scenario ==========="
    echo
    exit 1
  fi
}

signChannelCreateTx() {
  set -e

  echo "signing the channel create tx $CHANNEL_TX_FILE with ordererorg admin's signcerts..."
  setOrdererGlobals
  peer channel signconfigtx -f $CHANNEL_TX_FILE

  echo "signing the channel create tx $CHANNEL_TX_FILE with org1 admin's signcerts..."
  setOrg1Globals
  peer channel signconfigtx -f $CHANNEL_TX_FILE

  set +e
}


createChannel() {
  set -e

  echo "creating channel $CHANNEL_NAME..."
  setOrdererGlobals
  peer channel create -c $CHANNEL_NAME -f $CHANNEL_TX_FILE -t 30s -o $ORDERER_ADDRESS --tls --cafile $ORDERER_CA

  set +e
}

joinChannelWithRetry() {
  setOrg1Globals

  set -x
  peer channel join -b $CHANNEL_NAME.block >&log.txt
  res=$?
  set +x
  cat log.txt
  if [ $res -ne 0 -a $COUNTER -lt $MAX_RETRY ]; then
    COUNTER=$(expr $COUNTER + 1)
    echo "peer1.org1 failed to join the channel, Retry after 3 seconds"
    sleep 3
    joinChannelWithRetry $PEER $ORG
  else
    COUNTER=1
  fi
  verifyResult $res "After $MAX_RETRY attempts, peer1.org1 has failed to join channel '$CHANNEL_NAME' "
}

showInstalledCC() {
    set -e
    setOrg1Globals
    peer chaincode list --installed
    set +e
}

showInstanticatedCC() {
    set -e
    CHANNEL_NAME=$1
    setOrg1Globals
    peer chaincode list --instantiated -C $CHANNEL_NAME
    set +e
}

# packageChaincode VERSION
packageChaincode() {
  VERSION=$1
  setOrg1Globals
  set -x
  peer lifecycle chaincode package mycc.tar.gz --path ${CC_SRC_PATH} --lang ${CC_RUNTIME_LANGUAGE} --label mycc_${VERSION} >&log.txt
  res=$?
  set +x
  cat log.txt
  verifyResult $res "Chaincode packaging on peer1.org1 has failed"
  echo "===================== Chaincode is packaged on peer1.org1 ===================== "
  echo
}

installChaincode() {
  setOrg1Globals
  set -x
  peer lifecycle chaincode install mycc.tar.gz >&log.txt
  res=$?
  set +x
  cat log.txt
  verifyResult $res "Chaincode installation on peer1.org1 has failed"
  echo "===================== Chaincode is installed on peer1.org$1 ===================== "
  echo
}

queryInstalled() {
  setOrg1Globals
  set -x
  peer lifecycle chaincode queryinstalled >&log.txt
  res=$?
  set +x
  cat log.txt
  PACKAGE_ID=`sed -n '/Package/{s/^Package ID: //; s/, Label:.*$//; p;}' log.txt`
  verifyResult $res "Query installed on peer1.org1 has failed"
  echo PackageID is ${PACKAGE_ID}
  echo "===================== Query installed successful on peer1.org1 on channel ===================== "
  echo
}

approveForMyOrg() {
  VERSION=$1
  setOrg1Globals

  set -x
  peer lifecycle chaincode approveformyorg --tls true --cafile $ORDERER_CA --channelID $CHANNEL_NAME --name mycc --version ${VERSION} \
    --init-required --package-id ${PACKAGE_ID} --sequence ${VERSION} --waitForEvent >&log.txt
  set +x

  cat log.txt
  verifyResult $res "Chaincode definition approved on peer1.org1 on channel '$CHANNEL_NAME' failed"
  echo "===================== Chaincode definition approved on peer1.org1 on channel '$CHANNEL_NAME' ===================== "
  echo
}

commitChaincodeDefinition() {
  VERSION=$1

  set -x
  peer lifecycle chaincode commit -o $ORDERER_ADDRESS --tls true --cafile $ORDERER_CA --channelID $CHANNEL_NAME --name mycc \
       ${PEER_CONN_PARMS} --version ${VERSION} --sequence ${VERSION} --init-required >&log.txt
  res=$?
  set +x

  cat log.txt
  verifyResult $res "Chaincode definition commit failed on peer1.org1 on channel '$CHANNEL_NAME' failed"
  echo "===================== Chaincode definition committed on channel '$CHANNEL_NAME' ===================== "
  echo
}

checkCommitReadiness() {
  VERSION=$1
  setOrg1Globals

  echo "===================== Checking the commit readiness of the chaincode definition on peer1.org1 on channel '$CHANNEL_NAME'... ===================== "
  local rc=1
  local starttime=$(date +%s)

  # continue to poll
  # we either get a successful response, or reach TIMEOUT
  while
    test "$(($(date +%s) - starttime))" -lt "$TIMEOUT" -a $rc -ne 0
  do
    sleep 3
    echo "Attempting to check the commit readiness of the chaincode definition on peer1.org1 ...$(($(date +%s) - starttime)) secs"
    set -x
    peer lifecycle chaincode checkcommitreadiness --channelID $CHANNEL_NAME --name mycc $PEER_CONN_PARMS --version ${VERSION} \
        --sequence ${VERSION} --output json --init-required >&log.txt
    res=$?
    set +x
    test $res -eq 0 || continue
    let rc=0
    for var in "$@"
    do
        grep "$var" log.txt &>/dev/null || let rc=1
    done
  done
  echo
  cat log.txt
  if test $rc -eq 0; then
    echo "===================== Checking the commit readiness of the chaincode definition successful on peer1.org1 on channel '$CHANNEL_NAME'     ===================== "
  else
    echo "!!!!!!!!!!!!!!! Check commit readiness result on peer1.org1 is INVALID !!!!!!!!!!!!!!!!"
    echo "================== ERROR !!! FAILED to execute End-2-End Scenario =================="
    echo
    exit 1
  fi
}

queryCommitted() {
  VERSION=$1
  setOrg1Globals

  EXPECTED_RESULT="Version: ${VERSION}, Sequence: ${VERSION}, Endorsement Plugin: escc, Validation Plugin: vscc"
  echo "===================== Querying chaincode definition on peer1.org1 on channel '$CHANNEL_NAME'... ===================== "
  local rc=1
  local starttime=$(date +%s)

  # continue to poll
  # we either get a successful response, or reach TIMEOUT
  while
    test "$(($(date +%s) - starttime))" -lt "$TIMEOUT" -a $rc -ne 0
  do
    sleep 3
    echo "Attempting to Query committed status on peer1.org1 ...$(($(date +%s) - starttime)) secs"
    set -x
    peer lifecycle chaincode querycommitted --channelID $CHANNEL_NAME --name mycc >&log.txt
    res=$?
    set +x
    test $res -eq 0 && VALUE=$(cat log.txt | grep -o '^Version: [0-9], Sequence: [0-9], Endorsement Plugin: escc, Validation Plugin: vscc')
    test "$VALUE" = "$EXPECTED_RESULT" && let rc=0
  done
  echo
  cat log.txt
  if test $rc -eq 0; then
    echo "===================== Query chaincode definition successful on peer1.org1 on channel '$CHANNEL_NAME' ===================== "
  else
    echo "!!!!!!!!!!!!!!! Query chaincode definition result on peer1.org1 is INVALID !!!!!!!!!!!!!!!!"
    echo "================== ERROR !!! FAILED to execute End-2-End Scenario =================="
    echo
    exit 1
  fi
}

chaincodeQuery() {
  setOrg1Globals

  EXPECTED_RESULT=$1
  echo "===================== Querying on peer1.org1 on channel '$CHANNEL_NAME'... ===================== "
  local rc=1
  local starttime=$(date +%s)

  # continue to poll
  # we either get a successful response, or reach TIMEOUT
  while
    test "$(($(date +%s) - starttime))" -lt "$TIMEOUT" -a $rc -ne 0
  do
    sleep 3
    echo "Attempting to Query peer1.org1 ...$(($(date +%s) - starttime)) secs"
    set -x
    peer chaincode query -C $CHANNEL_NAME -n mycc -c '{"Args":["query","a"]}' >&log.txt
    res=$?
    set +x
    test $res -eq 0 && VALUE=$(cat log.txt | awk '/Query Result/ {print $NF}')
    test "$VALUE" = "$EXPECTED_RESULT" && let rc=0
    # removed the string "Query Result" from peer chaincode query command
    # result. as a result, have to support both options until the change
    # is merged.
    test $rc -ne 0 && VALUE=$(cat log.txt | egrep '^[0-9]+$')
    test "$VALUE" = "$EXPECTED_RESULT" && let rc=0
  done
  echo
  cat log.txt
  if test $rc -eq 0; then
    echo "===================== Query successful on peer1.org1 on channel '$CHANNEL_NAME' ===================== "
  else
    echo "!!!!!!!!!!!!!!! Query result on peer1.org1 is INVALID !!!!!!!!!!!!!!!!"
    echo "================== ERROR !!! FAILED to execute End-2-End Scenario =================="
    echo
    exit 1
  fi
}

chaincodeInvoke() {
  IS_INIT=$1
  setOrg1Globals

  if [ "${IS_INIT}" -eq "1" ]; then
    CCARGS='{"Args":["Init","a","100","b","100"]}'
    INIT_ARG="--isInit"
  else
    CCARGS='{"Args":["invoke","a","b","10"]}'
    INIT_ARG=""
  fi

  set -x
  peer chaincode invoke -o $ORDERER_ADDRESS --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA -C $CHANNEL_NAME \
    -n mycc $PEER_CONN_PARMS ${INIT_ARG} -c ${CCARGS} >&log.txt
  res=$?
  set +x

  cat log.txt
  verifyResult $res "Invoke execution on $PEERS failed "
  echo "===================== Invoke transaction successful on $PEERS on channel '$CHANNEL_NAME' ===================== "
  echo
}
