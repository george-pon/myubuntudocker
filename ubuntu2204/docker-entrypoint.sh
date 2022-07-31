#!/bin/bash

set -e

while true
do
    if [ x"$1"x = x"-e"x ]; then
        eval $2
        export ${2%%=*}
        mkdir -p /etc/profile.d
        echo "export $2" >> /etc/profile.d/docker-entrypoint-env.sh
        shift
        shift
        continue
    fi
    break
done

if [ $# -eq 0 ]; then
    /bin/bash
fi
