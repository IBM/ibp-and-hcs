#!/bin/bash
set -e

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
TMP_DIR="${PKG_DIR}/tmp"
BIN_DIR="${PKG_DIR}/bin"
PATH="$BIN_DIR":$PATH

usage="Usage:
$(basename "$0") --hcscli-config-file HCSCLI-CONFIG_FILE --orderer-ca-url ORDERER-CA-URL
  --orderer-admin-file ORDERER-ADMIN-FILE --orderer-hostname ORDERER-HOSTNAME 
  --orderer-msp-file ORDERER-MSP-FILE --org1-admin-file ORG1-ADMIN-FILE
  --org1-msp-file ORG1-MSP-FILE --peer1-hostname PEER1-HOSTNAME

script to prepare fabric network crypto materials, create genesis block, and channel creation transaction.

where:
    --hcscli-config-file Hcscli configuration file
    --orderer-ca-url The url of the orderer org's CA
    --orderer-hostname Hostname / Public IP of the orderer
    --orderer-admin-file The orderer org's Admin identity json file
    --orderer-msp-file The orderer org's MSP definition json file
    --org1-admin-file Org1's Admin identity json file
    --org1-msp-file Org1's MSP definition json file
    --peer1-hostname Peer1's hostname"

while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
    --hcscli-config-file)
    hcscli_config_file="$2"
    shift
    shift
    ;;
    --orderer-ca-url)
    orderer_ca_url="$2"
    shift
    shift
    ;;
    --orderer-admin-file)
    orderer_admin_file="$2"
    shift
    shift
    ;;
    --orderer-hostname)
    orderer_hostname="$2"
    shift
    shift
    ;;
    --orderer-msp-file)
    orderer_msp_file="$2"
    shift
    shift
    ;;
    --org1-admin-file)
    org1_admin_file="$2"
    shift
    shift
    ;;
    --org1-msp-file)
    org1_msp_file="$2"
    shift
    shift
    ;;
    --peer1-hostname)
    peer1_hostname="$2"
    shift
    shift
    ;;
    *)
    shift
    ;;
  esac
done

if [ -z "${hcscli_config_file}" -o -z "${orderer_ca_url}" -o -z "${orderer_admin_file}" -o -z "${orderer_hostname}" \
  -o -z "${orderer_msp_file}" -o -z "${org1_admin_file}" -o -z "${org1_msp_file}" -o -z "${peer1_hostname}" ]; then
  echo -e "Missing input\n\n${usage}"
  exit 1
fi

mkdir -p $TMP_DIR && mkdir -p $BIN_DIR

if [ ! -f "${BIN_DIR}/configtxgen" ]; then
  echo -e "\nBuilding and installing fabirc tools"
    
  cd $TMP_DIR
  if [ ! -d pluggable-hcs ]; then
    git clone https://github.com/hyperledger-labs/pluggable-hcs
  fi
  cd pluggable-hcs
  git pull
  make clean configtxgen
  cp build/bin/configtxgen $BIN_DIR
  cd $PKG_DIR
fi

if [ ! -f "${BIN_DIR}/fabric-ca-client" ]; then
  echo -e "\nInstalling fabric-ca-client"

  GOBIN=$BIN_DIR go install github.com/hyperledger/fabric-ca/cmd/fabric-ca-client
fi

if [ ! -f "${BIN_DIR}/hcscli" ]; then
  echo -e "\nInstalling hcscli"

  GO111MODULE=on GOBIN=$BIN_DIR go get github.com/hashgraph/hcscli@v0.3.1
fi

CONVERTMSP_PYENV_DIR="${TMP_DIR}/convertmsp"
if [ ! -d "${CONVERTMSP_PYENV_DIR}" ]; then
  echo -e "\nCreating python virtual environment for convertmsp"
  python3 -m venv ${CONVERTMSP_PYENV_DIR}
  . ${CONVERTMSP_PYENV_DIR}/bin/activate
  pip install -r tools/convertmsp/requirements.txt
  deactivate
fi

echo -e "\nConverting orderer admin identity"
rm -fr ${TMP_DIR}/orderer_admin
${PKG_DIR}/tools/convertidentity.sh "$orderer_admin_file" ${TMP_DIR}/orderer_admin

echo -e "\nConverting org1 admin identity"
rm -fr ${TMP_DIR}/org1_admin
${PKG_DIR}/tools/convertidentity.sh "$org1_admin_file" ${TMP_DIR}/org1_admin

. ${CONVERTMSP_PYENV_DIR}/bin/activate

echo -e "\nConverting orderer org msp"
rm -fr ${TMP_DIR}/orderer_msp
python ${PKG_DIR}/tools/convertmsp/convertmsp.py --dir ${TMP_DIR}/orderer_msp "$orderer_msp_file"

echo -e "\nConverting org1 msp"
rm -fr ${TMP_DIR}/org1_msp
python ${PKG_DIR}/tools/convertmsp/convertmsp.py --dir ${TMP_DIR}/org1_msp "$org1_msp_file"

deactivate

echo -e "\nEnrolling orderer for MSP and TLS"
rm -fr ${TMP_DIR}/enroll
${PKG_DIR}/tools/enrollorderer.sh --orderer-ca-url $orderer_ca_url --orderer-hostname $orderer_hostname

# create directory structure and copy files for configtxgen
crypto_config_dir="${PKG_DIR}/crypto-config"
rm -fr $crypto_config_dir

# orderer org
ordererorg_config_dir="${crypto_config_dir}/ordererorg"
ordererorg_admin_config_dir="${ordererorg_config_dir}/users/Admin@OrdererOrg"
mkdir -p $ordererorg_config_dir
mkdir -p $ordererorg_admin_config_dir

cp -r ${TMP_DIR}/orderer_msp $ordererorg_config_dir/msp
cp -r ${TMP_DIR}/orderer_msp $ordererorg_admin_config_dir/msp
cp -r ${TMP_DIR}/orderer_admin/* $ordererorg_admin_config_dir/msp/

orderer1_config_dir="${ordererorg_config_dir}/orderers/orderer1"
mkdir -p $orderer1_config_dir
cp -r $ordererorg_config_dir/msp $orderer1_config_dir
cp -r ${TMP_DIR}/enroll/orderer_msp/{signcerts,keystore} $orderer1_config_dir/msp
mv $orderer1_config_dir/msp/keystore/*_sk $orderer1_config_dir/msp/keystore/priv_sk 

orderer1_tls_config_dir="${orderer1_config_dir}/tls"
mkdir -p $orderer1_tls_config_dir
orderer1_tls_enroll_dir="${TMP_DIR}/enroll/orderer_tls"
cp $orderer1_config_dir/msp/tlscacerts/tlsca-cert.pem $orderer1_tls_config_dir/ca.crt
cp $orderer1_tls_enroll_dir/signcerts/cert.pem $orderer1_tls_config_dir/server.crt
cp $orderer1_tls_enroll_dir/keystore/*_sk $orderer1_tls_config_dir/server.key

# org1
org1_config_dir="${crypto_config_dir}/org1"
org1_admin_config_dir="${org1_config_dir}/users/Admin@Org1"
mkdir -p $org1_config_dir
mkdir -p $org1_admin_config_dir

cp -r ${TMP_DIR}/org1_msp $org1_config_dir/msp
cp -r ${TMP_DIR}/org1_msp $org1_admin_config_dir/msp
cp -r ${TMP_DIR}/org1_admin/* $org1_admin_config_dir/msp/

peer1_config_dir="${org1_config_dir}/peers/peer1"
mkdir -p $peer1_config_dir
cp -r  $org1_config_dir/msp $peer1_config_dir

# create two hcs topics and substitue topic IDs and orderer hostname to createa configtx.yaml
topics=($(hcscli -c "$hcscli_config_file" topic create 2 2>/dev/null | grep -o '[0-9]\+\.[0-9\+\.[0-9]\+'))
sed -e 's/${HCS_TOPIC_ID_SYS}/'"${topics[0]}"'/g' -e 's/${HCS_TOPIC_ID_APP}/'"${topics[1]}"'/g' \
  -e 's/${ORDERER_HOSTNAME}/'"${orderer_hostname}"'/g' -e 's/${PEER1_HOSTNAME}/'"${peer1_hostname}"'/g' \
  ${PKG_DIR}/configtx-template.yaml > ${PKG_DIR}/configtx.yaml
echo -e "\nHCS Topic IDs: ${topics[0]} for system channel and ${topics[1]} for application channel"

channel_artifacts_dir="${PKG_DIR}/channel-artifacts"
mkdir -p "$channel_artifacts_dir"
echo -e "\nCreating genesis block and saving it as ${channel_artifacts_dir}/genesis.block"
configtxgen -profile SampleHcsSystemChannel -channelID syschannel -outputBlock "${channel_artifacts_dir}"/genesis.block

echo -e "\nCreating application channel creatioin tx and save it as ${channel_artifacts_dir}/channel.tx"
configtxgen -channelCreateTxBaseProfile SampleHcsSystemChannel -profile SingleOrgChannel -outputCreateChannelTx "${channel_artifacts_dir}"/channel.tx -channelID appchannel

# create k8s secrets for orderer
echo -e "\nCreating kubernetes secrets for orderer"
kubectl delete $(kubectl get secret -o name | grep '/orderer-') || true
kubectl create secret generic orderer-genesis --from-file="${channel_artifacts_dir}/genesis.block"
kubectl create secret generic orderer-tls --from-file="${orderer1_tls_config_dir}"
${PKG_DIR}/tools/createmspsecret.sh "${orderer1_config_dir}/msp"

# update custom.yaml
echo -e "\nUpdating account ID and private key in custom.yaml"
operator_id=$(jq -r '.operatorId' "${hcscli_config_file}")
operator_key=$(jq -r '.operatorKey' "${hcscli_config_file}")
yq w -i ${PKG_DIR}/custom.yaml 'config.hcs.Operator.Id' ${operator_id}
yq w -i ${PKG_DIR}/custom.yaml 'config.hcs.Operator.PrivateKey.Key' ${operator_key}

# install chart
echo -e "\nInstalling fabric-hcs-orderer helm chart"
helm dependency update ${PKG_DIR}/charts/fabric-hcs-orderer
helm install dev ${PKG_DIR}/charts/fabric-hcs-orderer -f custom.yaml

