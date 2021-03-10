#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
BIN_DIR="${SCRIPT_DIR}/../bin"
TMP_DIR="${SCRIPT_DIR}/../tmp"

export PATH=$BIN_DIR:$PATH

while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
    --orderer-ca-url)
    orderer_ca_url="$2"
    shift
    shift
    ;;
    --orderer-hostname)
    orderer_hostname="$2"
    shift
    shift
    ;;
    --orderer-id)
    orderer_id="$2"
    shift
    shift
    ;;
    --orderer-pw)
    orderer_pw="$2"
    shift
    shift
    ;;
    *)
    shift # past argument
    ;;
  esac
done

orderer_id="${orderer_id:-orderer1}"
orderer_pw="${orderer_pw:-orderer1pw}"

if [ -z "${orderer_ca_url}" -o -z "${orderer_hostname}" ]; then
    echo "Please provide OrdererOrg CA's URL and the orderer's hostname / public IP"
    exit 1
fi

if [[ $orderer_ca_url != https://* ]]; then
    echo "Provided OrdererOrg CA's URL does not begin with \"https://\""
    exit 1
fi
orderer_ca_url=${orderer_ca_url#"https://"}

# save orderer ca's ssl certificate
ca_cert_file="${TMP_DIR}/orderer_ca.crt"
ca_cert_output=$(echo 'q' | openssl s_client -showcerts -connect $orderer_ca_url 2>/dev/null)
echo "$ca_cert_output" | awk 'BEGIN {cert=0;} {
    if ($0 ~ /BEGIN CERTIFICATE/)
        cert=1
    if (cert)
        print $0
    if ($0 ~ /END CERTIFICATE/)
        cert=0
}' > $ca_cert_file


# enroll orderer for MSP
enroll_url="https://${orderer_id}:${orderer_pw}@${orderer_ca_url}"
enroll_dir="${TMP_DIR}/enroll"
rm -fr $enroll_dir

orderer_msp_dir="${enroll_dir}/orderer_msp"
mkdir -p $orderer_msp_dir
fabric-ca-client enroll -u $enroll_url -M $orderer_msp_dir --tls.certfiles $ca_cert_file

# enroll orderer for TLS
orderer_tls_dir="${enroll_dir}/orderer_tls"
mkdir -p $orderer_tls_dir
fabric-ca-client enroll -u $enroll_url -M $orderer_tls_dir --tls.certfiles $ca_cert_file \
    --enrollment.profile tls --caname tlsca --csr.hosts $orderer_hostname
