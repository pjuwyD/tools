#!/bin/bash
 
usage="$(basename "$0") [-h] [-i d l] -- script to introduce network delay (in ms) to a specified link
 
where:
    -h  show help and usage
    -r reset interface settings
    -i set the interface
    -d set the destination IP address
    -l set the delay in ms
 
note:
 
After the tests are done, dont forget to reset the interface settings using flag -r
 
example usage:
$(basename "$0") -i eth0 -d 10.34.4.102 -l 100ms
$(basename "$0") -r -i eth0"
 
 
while getopts ":hri:d:l:" OPTION; do
    case $OPTION in
        i)
            INTERFACE="$OPTARG"
            ;;
        d)
            IP_DEST="$OPTARG"
            ;;
        l)
            DELAY="$OPTARG"
            ;;
        r) RESET=true
            ;;
        h)
            echo "$usage"
            exit 1
            ;;
        :) printf "missing argument for -%s\n" "$OPTARG" >&2; echo "$usage" >&2; exit 1;;
    esac
done
shift "$(($OPTIND -1))"
 
if [[ $RESET = true ]]; then
  if [ ! "$INTERFACE" ]; then
    echo "argument -i must be provided"
    echo "$usage" >&2; exit 1
  else
    tc qdisc del dev $INTERFACE root
  fi
else
  if [ ! "$INTERFACE" ] || [ ! "$IP_DEST" ] || [ ! "$DELAY" ]; then
    echo "arguments -i -d -l must be provided"
    echo "$usage" >&2; exit 1
  else
    tc qdisc add dev $INTERFACE root handle 1: prio
    tc filter add dev $INTERFACE parent 1:0 protocol ip prio 1 u32 match ip dst $IP_DEST flowid 2:1
    tc qdisc add dev $INTERFACE parent 1:1 handle 2: netem delay $DELAY
  fi
fi