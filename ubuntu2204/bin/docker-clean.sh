#!/bin/bash

function f-docker-clean() {
    docker image prune -f -a --filter "until=24h"
    # docker image prune -f
    docker container prune -f
    docker system prune -f
    docker volume prune -f
    if docker builder 1>/dev/null 2>/dev/null ; then
        docker builder prune -f
    fi
}

f-docker-clean

    # docker image prune -f
    # docker container prune -f
    # docker system prune -f
    # docker image prune -f
    # docker image prune -a --filter "until=24h"
    # docker builder prune
