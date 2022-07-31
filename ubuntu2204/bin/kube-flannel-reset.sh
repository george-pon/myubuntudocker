#!/bin/bash
#
# kubernetes flannel reset
#

POD_LIST=$( kubectl get pod --namespace kube-system | grep  kube-flannel-ds | grep Running | awk '{print $1}' )
for i in $POD_LIST
do
    echo ""
    echo "  $i"
    echo ""
    kubectl logs --namespace kube-system $i
done

for j in "$@"
do
    if [ x"$j"x = x"reset"x ]; then
        kubectl delete pod --namespace kube-system $POD_LIST
    fi
done
