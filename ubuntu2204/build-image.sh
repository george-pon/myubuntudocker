#!/bin/bash

function car() {
    echo $1
}

function cdr() {
    shift
    echo "$@"
}

function f_docker_build() {
    TAG_LIST=$(awk '/^ENV MYUBUNTUDOCKER_VERSION/ {print $3;}' Dockerfile)
    IMAGE_NAME=${PREFIX}$(awk '/^ENV MYUBUNTUDOCKER_IMAGE/ {print $3;}' Dockerfile)
    TAG_LIST="$TAG_LIST monthly$(date +%Y%m) "
    TAG_CAR=$(car $TAG_LIST)
    TAG_CDR=$(cdr $TAG_LIST)
    echo $TAG_CDR
    IMAGE_NAME=${PREFIX}$(awk '/^ENV MYUBUNTUDOCKER_IMAGE/ {print $3;}' Dockerfile)
    echo IMAGE_NAME is $IMAGE_NAME

    if [ ! -z "$HTTP_PROXY" ]; then
        BUILD_OPT="$BUILD_OPT  --build-arg HTTP_PROXY=$HTTP_PROXY"
    fi
    if [ ! -z "$HTTPS_PROXY" ]; then
        BUILD_OPT="$BUILD_OPT  --build-arg HTTPS_PROXY=$HTTPS_PROXY"
    fi
    if [ ! -z "$http_proxy" ]; then
        BUILD_OPT="$BUILD_OPT  --build-arg http_proxy=$http_proxy"
    fi
    if [ ! -z "$https_proxy" ]; then
        BUILD_OPT="$BUILD_OPT  --build-arg https_proxy=$https_proxy"
    fi
    if [ ! -z "$NO_PROXY" ]; then
        BUILD_OPT="$BUILD_OPT  --build-arg NO_PROXY=$NO_PROXY"
    fi
    if [ ! -z "$no_proxy" ]; then
        BUILD_OPT="$BUILD_OPT  --build-arg no_proxy=$no_proxy"
    fi

    if [ ! -z "$no_cache" ]; then
        BUILD_OPT="$BUILD_OPT  --no-cache=$no_cache"
    fi

    # check use buildx
    if [ x"$USE_BUILDX"x = x""x  ] ; then
        if docker buildx ls 1>/dev/null 2>/dev/null ; then
            if docker buildx ls 2>/dev/null | grep linux/arm/v7 ; then
                if docker buildx ls 2>/dev/null | grep linux/amd64 ; then
                    USE_BUILDX=yes
                fi
            fi
        fi
    fi

    if [ x"$USE_BUILDX"x = x"yes"x ]; then
        # docker buildx is available
        PLATOPT=
        MACHINE=$( uname -m )
        case $MACHINE in
            x86_64) PLATOPT='--platform=linux/amd64' ;;
            armv7l) PLATOPT='--platform=linux/arm/v7' ;;
            aarch64) PLATOPT='--platform=linux/amd64,linux/arm64' ;;
        esac
        for TAG_CAR in $TAG_LIST
        do
            export DOCKER_BUILDKIT=1
            echo $SUDO_DOCKER docker buildx build $BUILD_OPT -t ${IMAGE_NAME}:${TAG_CAR} $PLATOPT --push  .
            $SUDO_DOCKER docker buildx build $BUILD_OPT -t ${IMAGE_NAME}:${TAG_CAR} $PLATOPT --push  .
            RC=$?
            if [ $RC -ne 0 ]; then
                echo "ERROR: docker build failed."
                return 1
            fi
            sleep 3
            docker buildx imagetools inspect ${IMAGE_NAME}:${TAG_CAR}
        done
    else
        export DOCKER_BUILDKIT=1
        echo $SUDO_DOCKER docker build $BUILD_OPT -t ${IMAGE_NAME}:${TAG_CAR} .
        $SUDO_DOCKER docker build $BUILD_OPT -t ${IMAGE_NAME}:${TAG_CAR} .
        RC=$?
        if [ $RC -ne 0 ]; then
            echo "ERROR: docker build failed."
            return 1
        fi
        for i in $TAG_CDR
        do
            echo docker tag ${IMAGE_NAME}:$TAG_CAR ${IMAGE_NAME}:$i
            $SUDO_DOCKER docker tag ${IMAGE_NAME}:$TAG_CAR ${IMAGE_NAME}:$i
        done
    fi

    return 0
}

f_docker_build
