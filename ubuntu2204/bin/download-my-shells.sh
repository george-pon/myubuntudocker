#!/bin/bash
#
# オレの作業シェルをダウンロードする
#
function f-download-my-shells() {
mkdir -p /usr/local/bin
pushd /usr/local/bin
for i in \
    kube-run-v.sh  ssh-run-v.sh  \
    kube-all-namespaces.sh  kube-get-all-resources.sh \
    kube-all-check.sh  docker-clean.sh  \
    kubectl-get-event-sort.sh \
    kubectl-logs-regex.sh \
    download-my-shells.sh  \
    kube-helm-client-init.sh  \
    kube-helm-tools-setup.sh  \
    docker-run-v.sh \
    docker-run-ctop.sh \
    curl-no-proxy.sh  \
    kube-flannel-reset.sh  at-cmd.sh  shar-cat.sh 
do
    curl -fLO https://gitlab.com/george-pon/my-helm-chart/raw/master/bin/$i
    chmod +x $i
done
popd
}

f-download-my-shells
