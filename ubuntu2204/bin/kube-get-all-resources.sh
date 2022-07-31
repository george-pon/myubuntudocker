#!/bin/bash
#
#  kube get all で表示されない Secret / ConfigMap / Ingress なども全部表示する
#

#
# 全namespaceで何か操作する
#
function f-kube-get-all-resources() {
    KUBE_GET_DEFAULT_OPT=" -A "
    # kubectl get "$@" $(kubectl api-resources --namespaced=true --verbs=list -o name | tr '\n' ',' | sed -e 's%,$%%g')
    API_RESOURCES=$(kubectl api-resources --namespaced=true --verbs=list -o name)
    for i in ${API_RESOURCES}
    do
        IS_RESOURCE=$( kubectl get "$@" $i 2>&1 | grep "No resources found in " )
        if [ -z "$IS_RESOURCE" ] ; then
            echo ""
            echo ""
            echo "### kubectl get $KUBE_GET_DEFAULT_OPT "$@" $i"
            kubectl get $KUBE_GET_DEFAULT_OPT "$@" $i
            echo ""
            echo ""
        else
            echo "No resources found in $i"
        fi
    done
}

# if source this file, define function only ( not run )
# echo "BASH_SOURCE count is ${#BASH_SOURCE[@]}"
# echo "BASH_SOURCE is ${BASH_SOURCE[@]}"
if [ ${#BASH_SOURCE[@]} = 1 ]; then
    f-kube-get-all-resources "$@"
    RC=$?
    exit $RC
else
    echo "source from $0. define function only. not run." > /dev/null
fi

#
# end of file
#
