#!/bin/bash
set -e

if [ "$#" -ne 1 ]; then
  echo "Please provide orderer's msp directory, e.g., crypto-config/ordererorg/orderers/orderer1/msp"
  exit 1
fi

msp_dir=$1
from_file_args=""
for fname in $(find $1 -type f)
do
  echo "Add file $fname"
  from_file_args="${from_file_args} --from-file=${fname}"
done

if [ -z "${from_file_args}" ]; then
  echo "No files found in directory $msp_dir"
  exit 1
fi

kubectl create secret generic orderer-msp $from_file_args
