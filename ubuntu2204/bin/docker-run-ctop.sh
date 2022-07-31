#!/bin/bash
#
# ctopイメージを起動する
#

function docker-run-ctop() {
    docker run --rm -ti \
        --name=ctop \
        -v /var/run/docker.sock:/var/run/docker.sock \
        quay.io/vektorlab/ctop:latest
}

# if source this file, define function only ( not run )
if [ ${#BASH_SOURCE[@]} = 1 ]; then
    docker-run-ctop "$@"
    RC=$?
    exit $RC
else
    echo "source from $0. define function only. not run." > /dev/null
fi
