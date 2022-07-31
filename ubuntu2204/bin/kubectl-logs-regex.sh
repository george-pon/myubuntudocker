#!/bin/bash
#
# kubectl logs の改良版。Pod名は一部一致していれば認める。
#

function f-kubectl-logs-regex() {

    # 変数定義
    options=""
    pod_name_pattern=""
    tail_mode=
    container_name_pattern=""

    # 引数解析
    while true
    do
        if [ $# -eq 0 ] ; then
            break
        fi
        if [ x"$1"x = x"-f"x ] ; then
            tail_mode=yes
            shift
            continue
        elif [ x"$1"x = x"-c"x ] ; then
            container_name_pattern=$2
            shift
            shift
            continue
        else
            pod_name_pattern=$1
            shift
            continue
        fi
    done
    
    # 引数チェック
    if [ -z "$pod_name_pattern" ] ; then
        echo "pod name pattern is null. abort."
        return 1
    fi

    # ループ初回フラグ
    first_time=yes

    # tailモード時は無限ループ
    while true
    do

        # Pod名取得
        pod_name_list=$( kubectl get pod -A | egrep -e "$pod_name_pattern" | awk '{print $2}' )
        pod_namespace_list=$( kubectl get pod -A | egrep -e "$pod_name_pattern" | awk '{print $1}' )

        # bash配列の宣言
        declare -a pod_name_array=( $pod_name_list )
        declare -a pod_namespace_array=( $pod_namespace_list )

        # kubectl logs 実施
        i=0
        while [ $i -lt ${#pod_name_array[*]} ]
        do
            pod_name=${pod_name_array[$i]}
            pod_namespace=${pod_namespace_array[$i]}

            if [ x"$tail_mode"x = x""x ] ; then
                if [ x"$first_time"x = x"yes"x ] ; then
                    # まずはdescribe
                    echo ""
                    echo ""
                    echo ""
                    echo "---------------------------------------------------------------------------------"
                    echo "### kubectl describe pod --namespace $pod_namespace $pod_name"
                    kubectl describe pod --namespace $pod_namespace $pod_name
                fi
            fi

            # pod の中にいる初期化コンテナ名一覧を取得
            init_container_name_list=$( kubectl get pod --namespace $pod_namespace $pod_name -o jsonpath='{range .spec.initContainers[*]}{@.name}{" "}{end}' )

            # pod の中にいるコンテナ名一覧を取得
            container_name_list=$( kubectl get pod --namespace $pod_namespace $pod_name -o jsonpath='{range .spec.containers[*]}{@.name}{" "}{end}' )

            for container_name in $init_container_name_list $container_name_list
            do
                disp_flag=
                if [ -z "$container_name_pattern" ] ; then
                    # コンテナ名パターンの指定が無ければ表示
                    disp_flag=yes
                elif echo $container_name | egrep -e "$container_name_pattern" 1>/dev/null ; then
                    # パターン指定がありマッチした場合は表示
                    disp_flag=yes
                fi
                if [ x"$disp_flag"x = x"yes"x ] ; then
                    if [ x"$tail_mode"x = x"yes"x ] ; then
                        # tail mode の場合は、前回ログから増えた部分のみを表示
                        log_prefix="${pod_namespace} ${pod_name} ${container_name}    "
                        log_file_name_old="kubectl-logs-regex-${pod_namespace}-${pod_name}-${container_name}-old.log"
                        log_file_name_new="kubectl-logs-regex-${pod_namespace}-${pod_name}-${container_name}-new.log"
                        log_file_name_tmp="kubectl-logs-regex-${pod_namespace}-${pod_name}-${container_name}-tmp.log"
                        if [ x"$first_time"x = x"yes"x ] ; then
                            /bin/rm -f $log_file_name_old
                            touch $log_file_name_old
                        fi
                        if [ ! -f $log_file_name_old ] ; then
                            touch $log_file_name_old
                        fi
                        kubectl logs $options --namespace $pod_namespace $pod_name -c $container_name > $log_file_name_new
                        # 長すぎるログはカット。最新100行。
                        cat $log_file_name_new | tail -n 100 > $log_file_name_tmp
                        mv $log_file_name_tmp $log_file_name_new
                        diff -uw $log_file_name_old $log_file_name_new | egrep -e "^\+" | awk -v pref="$log_prefix" '/^\+/ {print "\033[36m" pref "\033[0m" " " substr($0,2) } '
                        mv $log_file_name_new $log_file_name_old
                    else
                        # 通常モードの場合は、普通にログ表示
                        echo ""
                        echo ""
                        echo ""
                        echo "---------------------------------------------------------------------------------"
                        echo "### kubectl logs $options --namespace $pod_namespace $pod_name -c $container_name"
                        echo ""
                        kubectl logs $options --namespace $pod_namespace $pod_name -c $container_name
                    fi
                fi
            done

            # 次のpod
            i=$(( i + 1 ))
        done

        # tail mode ではないならここで終了
        if [ x"$tail_mode"x = x""x ] ; then
            break
        fi

        # tail mode なら連続して実施
        if [ x"$tail_mode"x = x"yes"x ] ; then
            sleep 5
            first_time=
        fi

    done
}

f-kubectl-logs-regex "$@"

