#!/bin/bash
#
# Running 以外のステータスになっている Pod の describe とか logs を取得する
#
#  --all-namespaces を打った後に describe とか logs とか打つのが大変なので
#

#
# 全namespaceで何か操作する
#
function f-kube-all-check() {
    echo kubectl config get-contexts
    kubectl config get-contexts
    echo kubectl get pod --all-namespaces -o wide
    kubectl get pod --all-namespaces -o wide

    # 解析の自動化
    TMP_FILE=$( mktemp "tmp-kube-all-XXXXXXXX.txt" )
    kubectl get pod --all-namespaces -o wide | grep -v NAMESPACE | grep -v Running | grep -v Terminating | grep -v Completed > $TMP_FILE
    while true
    do
        read ans
        if [ -z "$ans" ]; then
            break
        fi
        echo "■--------------------------------------------------------------"
        echo "■ $ans"
        echo "■"
        LOCAL_DESCRIBE_CMD=$( echo $ans  | awk '{ cmdline = "kubectl describe pod -n " $1 "  " $2 ; print cmdline }' )
        echo "■"
        echo "■ $LOCAL_DESCRIBE_CMD"
        echo "■"
        eval $LOCAL_DESCRIBE_CMD
        LOCAL_LOGS_CMD=$( echo $ans  | awk '{ cmdline = "kubectl logs -n " $1 "  " $2 ; print cmdline }' )
        echo "■"
        echo "■ $LOCAL_LOGS_CMD"
        echo "■"
        eval $LOCAL_LOGS_CMD
    done < $TMP_FILE
    /bin/rm -f $TMP_FILE
}

# if source this file, define function only ( not run )
# echo "BASH_SOURCE count is ${#BASH_SOURCE[@]}"
# echo "BASH_SOURCE is ${BASH_SOURCE[@]}"
if [ ${#BASH_SOURCE[@]} = 1 ]; then
    f-kube-all-check "$@"
    RC=$?
    exit $RC
else
    echo "source from $0. define function only. not run." > /dev/null
fi

#
# end of file
#
