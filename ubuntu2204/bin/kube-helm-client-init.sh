#!/bin/bash
#
#  helm client 側のセットアップを行う
#
#  helm server のバージョンに合わせて helm client をインストールする
#
# 2019.03.04
#

function f-kube-helm-client-init() {

    # helm コマンド存在チェック
    if type helm 2>/dev/null 1>/dev/null ; then
        echo "helm client found."
    else
        # 適当なバージョンのクライアントを入手
        HELM_SERVER_VERSION=v2.12.3
        curl -f -s -S -LO https://storage.googleapis.com/kubernetes-helm/helm-${HELM_SERVER_VERSION}-linux-amd64.tar.gz
        tar xvzf helm-${HELM_SERVER_VERSION}-linux-amd64.tar.gz
        /bin/cp linux-amd64/helm /usr/bin
        /bin/rm -rf linux-amd64  helm-${HELM_SERVER_VERSION}-linux-amd64.tar.gz
    fi

    # helm version チェック
    if helm version 2>/dev/null 1>/dev/null ; then
        echo "helm version success."
    else
        echo "helm version failure. abort."
        return 1
    fi

    # ~/.helm チェック
    if [ -d ~/.helm ]; then
        echo "~/.helm found."
    else
        echo "~/.helm not found."
        helm init --client-only
    fi

    # 使用しているhelm serverのバージョンを得る
    HELM_CLIENT_VERSION=$( helm version | grep "Client" | sed -e 's/^.*SemVer:"//g' -e 's/", GitCommit.*$//g' )
    HELM_SERVER_VERSION=$( helm version | grep "Server" | sed -e 's/^.*SemVer:"//g' -e 's/", GitCommit.*$//g' )
    # 使用しているhelm serverのバージョンに合わせてダウンロードする
    if [ x"$HELM_CLIENT_VERSION"x != x"$HELM_SERVER_VERSION"x ]; then
        echo "install helm client command helm-${HELM_SERVER_VERSION}-linux-amd64.tar.gz"
        curl -f -s -S -LO https://storage.googleapis.com/kubernetes-helm/helm-${HELM_SERVER_VERSION}-linux-amd64.tar.gz
        tar xzf helm-${HELM_SERVER_VERSION}-linux-amd64.tar.gz
        /bin/cp linux-amd64/helm /usr/bin
        /bin/rm -rf linux-amd64  helm-${HELM_SERVER_VERSION}-linux-amd64.tar.gz
    fi
}

# if source this file, define function only ( not run )
if [ ${#BASH_SOURCE[@]} = 1 ]; then
    f-kube-helm-client-init "$@"
    RC=$?
    exit $RC
else
    echo "source from $0. define function only. not run." > /dev/null
fi

#
# end of file
#
