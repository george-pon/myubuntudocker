#!/bin/bash

export http_proxy=
export HTTP_PROXY=
export https_proxy=
export HTTPS_PROXY=
export no_proxy=
export NO_PROXY=

curl "$@"
