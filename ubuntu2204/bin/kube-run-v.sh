#!/bin/bash
#
# kube-run-v.sh  自作イメージ(mycentos7docker/mydebian9docker)を起動する
#
#   bashが入っているイメージなら、centosでもdebianでもubuntuでも動く
#
#   pod起動後、カレントディレクトリの内容をPodの中にコピーしてから、kubectl exec -i -t する
#
#   podからexitした後、ディレクトリの内容をPodから取り出してカレントディレクトリに上書きする。
#
#   お気に入りのコマンドをインストール済みのdockerイメージを使ってカレントディレクトリをコンテナに持ち込んで作業しよう。
#
#   docker run -v $PWD:$( basename $PWD ) debian みたいなモノ
#

# set WINPTY_CMD environment variable when it need. (for Windows MSYS2)
function f-check-winpty() {
    if type tty.exe  1>/dev/null 2>/dev/null ; then
        if type winpty.exe 1>/dev/null 2>/dev/null ; then
            local ttycheck=$( tty | grep "/dev/pty" )
            if [ ! -z "$ttycheck" ]; then
                export WINPTY_CMD=winpty
                return 0
            else
                export WINPTY_CMD=
                return 0
            fi
        fi
    fi
    return 0
}

#
# MSYS2 黒魔術
#
# MSYS2では、実行するコマンドが Windows用のexeで、
# コマンドの引数が / からはじまったらファイル名だと思って C:\Program Files\ に変換をかける
# コマンドの引数がファイルならこれで良いのだが、 /C=JP/ST=Tokyo/L=Tokyo みたいなファイルではないパラメータに変換がかかると面倒
# ここでは、条件によってエスケープをかける
#
#   1. cmdがあって、/CがProgram Filesに変換されれば、Windows系 MSYS
#   1. / から始まる場合、MSYS
#
function f-msys-escape() {
    local args="$@"
    export MSYS_FLAG=

    # check cygwin
    if type uname 2>/dev/null 1>/dev/null ; then
        local result=$( uname -o )
        if [ x"$result"x = x"Cygwin"x ]; then
            MSYS_FLAG=
            # if not MSYS, normal return
            echo "$@"
            return 0
        fi
    fi

    # check Msys
    if type uname 2>/dev/null 1>/dev/null ; then
        local result=$( uname -o )
        if [ x"$result"x = x"Msys"x ]; then
            MSYS_FLAG=true
        fi
    fi

    # check cmd is found
    if type cmd 2>/dev/null 1>/dev/null ; then
        # check msys convert ( Git for Windows )
        local result=$( cmd //c echo "/CN=Name")
        if [ x"$result"x = x"/CN=Name"x ]; then 
            MSYS_FLAG=
        else
            MSYS_FLAG=true
        fi
    fi

    # if not MSYS, normal return
    if [ x"$MSYS_FLAG"x = x""x ]; then
        echo "$@"
        return 0
    fi

    # if MSYS mode...
    # MSYSの場合、/から始まり、/の数が1個の場合は、先頭に / を加えれば望む結果が得られる
    # MSYSの場合、/から始まり、/の数が2個以上の場合は、先頭に // を加え、文中の / を \ に変換すれば望む結果が得られる (UNCファイル指定と誤認させる)
    local i=""
    for i in "$@"
    do
        # if argument starts with /
        local startWith=$( echo $i | awk '/^\// { print $0  }' )
        local slashCount=$( echo $i | awk '{ for ( i = 1 ; i < length($0) ; i++ ) { ch = substr($0,i,1) ; if (ch=="/") { count++; print count }  }  }' | wc -l )
        if [ -n "$startWith"  ]; then
            if [ $slashCount -eq 1 ]; then
                echo "/""$i"
            fi
            if [ $slashCount -gt 1 ]; then
                echo "//"$( echo $i | sed -e 's%^/%%g' -e 's%/%\\%g' )
            fi
        else
            echo "$i"
        fi
    done
}


# Windows環境のみ。rsync.exeは、 Git Bash for Windows から実行した場合、/hoge のような絶対パス表記を受け付けない
# ( 内部で C:/tmp に変換されて C というホストの /hoge にアクセスしようとする)ため、PWDからの相対パスに変更する；；
function f-rsync-escape-relative() {
    realpath --relative-to="$PWD" "$1"
}

#
# ../*-recover.sh ファイルがあれば実行する
#
function f-check-and-run-recover-sh() {
    local i
    local ans
    for i in ../*-recover.sh
    do
        if [ -f "$i" ]; then
            while true
            do
                echo    "  warning. found $i file.  run $i and remove it before run kube-run-v."
                echo -n "  do you want to run $i ? [y/n/c] : "
                read ans
                if [ x"$ans"x = x"y"x  -o  x"$ans"x = x"yes"x ]; then
                    bash -x "$i"
                    /bin/rm -f "$i"
                    /bin/rm -f "../kube-run-v-kubeconfig-*"
                    break
                fi
                if [ x"$ans"x = x"n"x  -o  x"$ans"x = x"no"x ]; then
                    break
                fi
                if [ x"$ans"x = x"c"x  -o  x"$ans"x = x"clear"x ]; then
                    /bin/rm -f "$i"
                    /bin/rm -f "../kube-run-v-kubeconfig-*"
                    break
                fi
            done
        fi
    done
}


# kubernetes server version文字列(1.11.6)をechoする
# k3s環境だと1.14.1-k3s.4なので、-k3s.4の部分はカットする
function f-kubernetes-server-version() {
    local RESULT1=$( kubectl version --short 2>/dev/null | grep "Server Version" | sed -e 's/^.*://g' | sed -e 's/^.*v//g' )
    local RESULT2=$( kubectl version 2>/dev/null | grep "Server Version" | sed -e 's/^.*GitVersion://g' -e 's/, GitCommit.*$//g' -e 's/"//g' -e 's/^v//g' -e 's/-.*$//g' )
    if [ -n "$RESULT1" ] ; then
	echo $RESULT1
	return
    fi
    if [ -n "$RESULT2" ] ; then
	echo $RESULT2
	return
    fi
}

# kubernetes client version文字列(1.11.6)をechoする
# k3s環境だと1.14.1-k3s.4なので、-k3s.4の部分はカットする
function f-kubernetes-client-version() {
    local RESULT1=$( kubectl version --short 2>/dev/null | grep "Client Version" | sed -e 's/^.*://g' | sed -e 's/^.*v//g' )
    local RESULT2=$( kubectl version 2>/dev/null | grep "Client Version" | sed -e 's/^.*GitVersion://g' -e 's/, GitCommit.*$//g' -e 's/"//g' -e 's/^v//g' -e 's/-.*$//g' )
    if [ -n "$RESULT1" ] ; then
	echo $RESULT1
	return
    fi
    if [ -n "$RESULT2" ] ; then
	echo $RESULT2
	return
    fi
}

# kubernetes version 文字列(1.11.6)を比較する
# ピリオド毎に4桁の整数(000100110006)に変換してechoする
function f-version-convert() {
    local ARGVAL=$( echo $1 | sed -e 's/\./ /g' )
    local i
    local RESULT=""
    for i in $ARGVAL
    do
        if [ -z "$RESULT" ]; then
            RESULT="$(printf "%04d" $i)"
        else
            RESULT="${RESULT}$(printf "%04d" $i)"
        fi
    done
    echo $RESULT
}

# kubernetes 1.10, 1.11ならcarry-on-kubeconfigする必要がある
# kubernetes 1.13.4ならcarry-on-kubeconfigしなくて良い可能性がある
# ただ、周辺ツール ( helm とか stern ) は相変わらず ~/.kube/config を必要としているので、デフォルトで持ち込む
function f-check-kubeconfig-carry-on() {
    export KUBE_SERV_VERSION=$( f-kubernetes-server-version )
    if [ -z "$KUBE_SERV_VERSION" ]; then
        echo "yes"
        return
    fi
    local NOW_KUBE_SERV_VERSION=$( f-version-convert $KUBE_SERV_VERSION )
    local CMP_KUBE_SERV_VERSION=$( f-version-convert "1.13.0" )
    if [ $CMP_KUBE_SERV_VERSION -le $NOW_KUBE_SERV_VERSION ]; then
        echo "yes"
        # echo "no"
        return
    else
        echo "yes"
        return
    fi
}

# kubernetes 1.18 以降なら kubectl run --dry-run=client --output=json とする
# kubernetes 1.18 以前なら kubectl run --dry-run
function f-check-dry-run-pod() {
    export KUBE_SERV_VERSION=$( f-kubernetes-server-version )
    if [ -z "$KUBE_SERV_VERSION" ]; then
        echo "no"
        return
    fi
    local NOW_KUBE_SERV_VERSION=$( f-version-convert $KUBE_SERV_VERSION )
    local CMP_KUBE_SERV_VERSION=$( f-version-convert "1.18.0" )
    if [ $CMP_KUBE_SERV_VERSION -le $NOW_KUBE_SERV_VERSION ]; then
        echo "yes"
        return
    else
        echo "no"
        return
    fi
}

# kubernetes 1.18 では廃止された。
# kubernetes 1.17 以降なら kubectl run --generator=run-pod/v1 とする yesを返却
# kubernetes 1.16 以前なら kubectl run で良い no を返却
function f-check-generator-run-pod() {
    export KUBE_SERV_VERSION=$( f-kubernetes-server-version )
    if [ -z "$KUBE_SERV_VERSION" ]; then
        echo "no"
        return
    fi
    local NOW_KUBE_SERV_VERSION=$( f-version-convert $KUBE_SERV_VERSION )
    local CMP_KUBE_SERV_VERSION=$( f-version-convert "1.18.0" )
    if [ $CMP_KUBE_SERV_VERSION -le $NOW_KUBE_SERV_VERSION ]; then
        echo "no"
        return
    fi
    local CMP_KUBE_SERV_VERSION=$( f-version-convert "1.17.0" )
    if [ $CMP_KUBE_SERV_VERSION -le $NOW_KUBE_SERV_VERSION ]; then
        echo "yes"
        return
    else
        echo "no"
        return
    fi
}

# kubectl run --serviceaccount オプションの判定
# kubernetes 1.21 ではdeprecatedになった。
function f-check-run-pod-serviceaccount() {
    export KUBE_SERV_VERSION=$( f-kubernetes-client-version )
    if [ -z "$KUBE_SERV_VERSION" ]; then
        echo "no"
        return
    fi
    local NOW_KUBE_SERV_VERSION=$( f-version-convert $KUBE_SERV_VERSION )
    local CMP_KUBE_SERV_VERSION=$( f-version-convert "1.21.0" )
    if [ $CMP_KUBE_SERV_VERSION -le $NOW_KUBE_SERV_VERSION ]; then
        echo "no"
        return
    fi
    echo "yes"
    return
}

#
# 自作イメージを起動して、カレントディレクトリのファイル内容をPod内部に持ち込む
#   for kubernetes  ( Linux Bash or Git-Bash for Windows MSYS2 )
#
# カレントディレクトリのディレクトリ名の末尾(basename)の名前で、
# Pod内部のルート( / )にディレクトリを作ってファイルを持ち込む
# 
# Podの中のシェル終了後、Podからファイルの持ち出しをやる。rsyncがあればrsync -crvを使う。無ければtarで上書き展開する。
#
#   https://hub.docker.com/r/georgesan/mycentos7docker/  docker hub に置いてあるイメージ(default)
#
#   https://github.com/george-pon/mycentos7docker  イメージの元 for centos
#   https://gitlab.com/george-pon/mydebian9docker  イメージの元 for debian
#
#
# パスの扱いがちとアレすぎるので kubectl cp は注意。
# ファイルの実行属性を落としてくるので kubectl cp は注意。
#
function f-kube-run-v() {

    # check PWD ( / で実行は許可しない )
    if [ x"$PWD"x = x"/"x ]; then
        echo "kube-run-v: can not run. PWD is / . abort."
        return 1
    fi
    # check PWD ( /tmp で実行は許可しない )
    if [ x"$PWD"x = x"/tmp"x ]; then
        echo "kube-run-v: can not run. PWD is /tmp . abort."
        return 1
    fi

    # check rsync command present.
    local RSYNC_MODE=true
    if type rsync  2>/dev/null 1>/dev/null ; then
        echo "command rsync OK" > /dev/null
    else
        echo "command rsync not found." > /dev/null
        RSYNC_MODE=false
    fi

    # check sudo command present.
    local DOCKER_SUDO_CMD=sudo
    if type sudo 2>/dev/null 1>/dev/null ; then
        echo "command sudo OK" > /dev/null
    else
        echo "command sudo not found." > /dev/null
        DOCKER_SUDO_CMD=
    fi

    # check kubectl version
    kubectl version 1>/dev/null 2>/dev/null
    RC=$? ; if [ $RC -ne 0 ]; then echo "kubectl version error. abort." ; return $RC; fi

    local namespace=
    local serviceaccount=
    local kubectl_run_opt_serviceaccount=
    local serviceaccount_json=
    local kubectl_cmd_namespace_opt=
    local interactive=
    local tty=
    local i_or_tty=
    local image=registry.gitlab.com/george-pon/mydebian11docker:latest
    local pod_name_prefix=
    local pod_timeout=600
    local imagePullOpt=
    local image_pull_policy_json="IfNotPresent"
    local command_line=
    local env_opts=
    local env_json=
    local limits_memory=
    local limits_memory_json=
    local runas_option=
    local runas_option_json=
    local pseudo_volume_bind=true
    local pseudo_volume_list=
    local pseudo_volume_left=
    local pseudo_volume_right=
    local add_hosts_list=
    local docker_pull=
    # kubectl v 1.11 なら ~/.kube/config をpod内部に持ち込む必要があるかもしれない
    # kubectl v 1.13.4 なら ~/.kube/config をpod内部に持ち込む必要は無い
    # https://qiita.com/sotoiwa/items/aff12291957d85069a76 Kubernetesクラスター内のPodからkubectlを実行する - Qiita
    local carry_on_kubeconfig=
    local carry_on_kubeconfig_file=
    local pseudo_workdir=/$( basename $PWD )
    local workingdir=
    local workingdir_json=
    local pseudo_profile=
    local volume_carry_out=true
    local image_pull_secrets_json=
    local node_select_json=
    local no_carry_on_proxy=
    local no_carry_on_docker_host=
    # kubectl create secret docker-registry <name> --docker-server=DOCKER_REGISTRY_SERVER --docker-username=DOCKER_USER --docker-password=DOCKER_PASSWORD --docker-email=DOCKER_EMAIL
    local docker_registry_name=
    local docker_registry_username=
    local docker_registry_password=
    local command_line_pass_mode=
    # support hostpath
    local hostpath_list=
    local hostpath_volume_mounts_json=
    local hostpath_volumes_json=
    local generator_opt=
    local dry_run=

    f-check-winpty 2>/dev/null

    # environment variables
    if [ ! -z "$KUBE_RUN_V_IMAGE" ]; then
        image=${KUBE_RUN_V_IMAGE}
    fi
    if [ ! -z "$KUBE_RUN_V_ADD_HOST_1" ]; then
        add_hosts_list="$add_hosts_list $KUBE_RUN_V_ADD_HOST_1"
    fi
    if [ ! -z "$KUBE_RUN_V_ADD_HOST_2" ]; then
        add_hosts_list="$add_hosts_list $KUBE_RUN_V_ADD_HOST_2"
    fi
    if [ ! -z "$KUBE_RUN_V_ADD_HOST_3" ]; then
        add_hosts_list="$add_hosts_list $KUBE_RUN_V_ADD_HOST_3"
    fi
    if [ ! -z "$KUBE_RUN_V_ADD_HOST_4" ]; then
        add_hosts_list="$add_hosts_list $KUBE_RUN_V_ADD_HOST_4"
    fi
    if [ ! -z "$KUBE_RUN_V_ADD_HOST_5" ]; then
        add_hosts_list="$add_hosts_list $KUBE_RUN_V_ADD_HOST_5"
    fi

    # parse argument option
    while [ $# -gt 0 ]
    do
        # コマンドライン pass モードチェック
        if [ x"$command_line_pass_mode"x = x"yes"x ]; then
            if [ -z "$command_line" ]; then
                command_line="$1"
            else
                command_line="$command_line $1"
            fi
            shift
            continue
        fi
        if [ x"$1"x = x"--add-host"x ]; then
            add_hosts_list="$add_hosts_list $2"
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"-n"x -o x"$1"x = x"--namespace"x ]; then
            namespace=$2
            kubectl_cmd_namespace_opt="--namespace $namespace"
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"-w"x -o x"$1"x = x"--workdir"x ]; then
            pseudo_workdir=$2
            if echo "$pseudo_workdir" | egrep -e '^/.*$' > /dev/null ; then 
                echo "OK. workdir is absolute path." > /dev/null
            else
                echo "OK. workdir is NOT absolute path. abort."
                return 1
            fi
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"-w"x -o x"$1"x = x"--workingdir"x ]; then
            workingdir=$2
            if echo "$workingdir" | egrep -e '^/.*$' > /dev/null ; then 
                echo "OK. workingdir is absolute path." > /dev/null
            else
                echo "OK. workingdir is NOT absolute path. abort."
                return 1
            fi
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"--source-profile"x ]; then
            pseudo_profile=$2
            if [ -r "$pseudo_profile" ] ; then 
                echo "OK. pseudo_profile is readable." > /dev/null
            else
                echo "OK. pseudo_profile is NOT readable. abort." > /dev/null
                return 1
            fi
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"-e"x -o x"$1"x = x"--env"x ]; then
            local env_key_val=$2
            local env_key=${env_key_val%%=*}
            local env_val=${env_key_val#*=}
            if [ -z "$env_opts" ]; then
                env_opts="--env $env_key=$( f-msys-escape $env_val) "
                env_json=' , { "name":  "'$env_key'" , "value": "'$( f-msys-escape $env_val)'" } '
            else
                env_opts="$env_opts --env $env_key=$( f-msys-escape $env_val ) "
                env_json="$env_json"' , {  "name" : "'$env_key'" , "value" : "'$( f-msys-escape $env_val )'" } '
            fi
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"-i"x -o x"$1"x = x"--interactive"x ]; then
            interactive="-i"
            i_or_tty=yes
            shift
            continue
        fi
        if [ x"$1"x = x"-t"x -o x"$1"x = x"--tty"x ]; then
            tty="-t"
            i_or_tty=yes
            shift
            continue
        fi
        if [ x"$1"x = x"--no-rsync"x ]; then
            RSYNC_MODE=false
            shift
            continue
        fi
        if [ x"$1"x = x"-v"x -o x"$1"x = x"--volume"x ]; then
            pseudo_volume_bind=true
            pseudo_volume_left=${2%%:*}
            pseudo_volume_right=${2##*:}
            if [ x"$pseudo_volume_left"x = x"$2"x ]; then
                echo "  volume list is hostpath:destpath.  : is not found. abort."
                return 1
            elif [ -f "$pseudo_volume_left" ]; then
                echo "OK" > /dev/null
            elif [ -d "$pseudo_volume_left" ]; then
                echo "OK" > /dev/null
            else
                echo "  volume list is hostpath:destpath.  hostpath $pseudo_volume_left is not a directory nor file. abort."
                return 1
            fi
            pseudo_volume_list="$pseudo_volume_list $2"
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"--hostpath"x ]; then
            hostpath_left=${2%%:*}
            hostpath_right=${2##*:}
            hostpath_name=$( echo $hostpath_left | sed -e 's%[^a-zA-Z0-9]%%g' )
            if [ x"$hostpath_left"x = x"$2"x ]; then
                echo "  hostpath_leftis hostpath:mountpath.  : is not found. abort."
                return 1
            fi
            hostpath_list="$hostpath_list $2"
            if [ -n "$hostpath_volume_mounts_json" ]; then
                hostpath_volume_mounts_json="$hostpath_volume_mounts_json , "
            fi
            hostpath_volume_mounts_json="$hostpath_volume_mounts_json { \"name\" : \"$hostpath_name\" , \"mountPath\" : \"$hostpath_right\" } "
            if [ -n "$hostpath_volumes_json" ]; then
                hostpath_volumes_json="$hostpath_volumes_json , "
            fi
            hostpath_volumes_json="$hostpath_volumes_json { \"name\" : \"$hostpath_name\" , \"hostPath\" : { \"path\" : \"$hostpath_left\" } } "
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"+v"x -o x"$1"x = x"++volume"x -o x"$1"x = x"--no-volume"x ]; then
            pseudo_volume_bind=
            shift
            continue
        fi
        if [ x"$1"x = x"--image"x ]; then
            image=$2
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"--image-centos"x ]; then
            image=georgesan/mycentos7docker:latest
            shift
            continue
        fi
        if [ x"$1"x = x"--image-centos7"x ]; then
            image=georgesan/mycentos7docker:latest
            shift
            continue
        fi
        if [ x"$1"x = x"--image-debian"x ]; then
            image=registry.gitlab.com/george-pon/mydebian11docker:latest
            shift
            continue
        fi
        if [ x"$1"x = x"--image-debian9"x ]; then
            image=registry.gitlab.com/george-pon/mydebian9docker:latest
            shift
            continue
        fi
        if [ x"$1"x = x"--image-debian10"x ]; then
            image=registry.gitlab.com/george-pon/mydebian10docker:latest
            shift
            continue
        fi
        if [ x"$1"x = x"--image-debian11"x ]; then
            image=registry.gitlab.com/george-pon/mydebian11docker:latest
            shift
            continue
        fi
        if [ x"$1"x = x"--image-ubuntu"x ]; then
            image=docker.io/georgesan/myubuntu2004docker:latest
            shift
            continue
        fi
        if [ x"$1"x = x"--image-ubuntu1804"x ]; then
            image=docker.io/georgesan/myubuntu1804docker:latest
            shift
            continue
        fi
        if [ x"$1"x = x"--image-ubuntu2004"x ]; then
            image=docker.io/georgesan/myubuntu2004docker:latest
            shift
            continue
        fi
        if [ x"$1"x = x"--image-alpine"x ]; then
            image=registry.gitlab.com/george-pon/myalpine3docker:latest
            shift
            continue
        fi
        if [ x"$1"x = x"--image-oraclelinux8"x ]; then
            image=docker.io/georgesan/myoraclelinux8docker:latest
            shift
            continue
        fi
        if [ x"$1"x = x"--image-oraclelinux7"x ]; then
            image=docker.io/georgesan/myoraclelinux7docker:latest
            shift
            continue
        fi
        if [ x"$1"x = x"--docker-pull"x ]; then
            docker_pull=yes
            shift
            continue
        fi
        if [ x"$1"x = x"--carry-on-kubeconfig"x ]; then
            carry_on_kubeconfig=yes
            shift
            continue
        fi
        if [ x"$1"x = x"++carry-on-kubeconfig"x ]; then
            carry_on_kubeconfig=no
            shift
            continue
        fi
        if [ x"$1"x = x"--read-only"x ]; then
            volume_carry_out=
            shift
            continue
        fi
        if [ x"$1"x = x"--name"x ]; then
            pod_name_prefix=$2
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"--timeout"x ]; then
            pod_timeout=$2
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"--pull"x ]; then
            imagePullOpt=" --image-pull-policy=Always "
            image_pull_policy_json="Always"
            shift
            continue
        fi
        if [ x"$1"x = x"--image-pull-secrets"x ]; then
            image_pull_secrets_json=' "imagePullSecrets" : [ { "name" : "'$2'" } ] '
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"--node-selector"x ]; then
            node_select_json=' "nodeSelector" : { "kubernetes.io/hostname" : "'$2'" } '
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"--node-selector2"x ]; then
            node_select_json=' "nodeSelector" : { "'$2'" : "'$3'" } '
            shift
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"--limit-memory"x ]; then
            limits_memory=$2
            limits_memory_json=' "limits" : { "memory" : "'$2'" } , "requests" : { "memory" : "1M" } '
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"--runas"x ]; then
            runas_option=$2
            runas_option_json=' "securityContext" : { "runAsUser" : '$2' } '
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"--no-carry-on-proxy"x -o x"$1"x = x"--no-proxy"x ]; then
            no_carry_on_proxy=true
            shift
            continue
        fi
        if [ x"$1"x = x"--no-carry-on-docker-host"x -o x"$1"x = x"--no-docker-host"x ]; then
            no_carry_on_docker_host=true
            shift
            continue
        fi
        if [ x"$1"x = x"--docker-registry-name"x -o x"$1"x = x"--docker-registry-server"x ]; then
            docker_registry_name=$2
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"--docker-registry-username"x ]; then
            docker_registry_username=$2
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"--docker-registry-password"x ]; then
            docker_registry_password=$2
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"--command"x ]; then
            command_line_pass_mode=yes
            shift
            continue
        fi
        if [ x"$1"x = x"--dry-run"x ]; then
            dry_run=yes
            shift
            continue
        fi
        if [ x"$1"x = x"--help"x ]; then
            echo "kube-run-v"
            echo "    -n, --namespace  namespace        set kubectl run namespace"
            echo "        --command                     after this option , arguments pass to kubectl exec command line"
            echo "        --image  image-name           set kubectl run image name. default is $image "
            echo "        --image-centos                set image to docker.io/georgesan/mycentos7docker:latest"
            echo "        --image-ubuntu                set image to docker.io/georgesan/myubuntu2004docker:latest"
            echo "        --image-debian                set image to registry.gitlab.com/george-pon/mydebian11docker:latest  (default)"
            echo "        --image-alpine                set image to registry.gitlab.com/george-pon/myalpine3docker:latest"
            echo "        --image-oraclelinux8          set image to docker.io/georgesan/myoraclelinux8docker:latest"
            echo "        --image-oraclelinux7          set image to docker.io/georgesan/myoraclelinux7docker:latest"
            echo "        --carry-on-kubeconfig         carry on kubeconfig file into pod"
            echo "        --docker-pull                 docker pull image before kubectl run"
            echo "        --pull                        always pull image"
            echo "        --image-pull-secrets name     image pull secrets name"
            echo "        --node-selector nodename      set nodeSelector. selector key is kubernetes.io/hostname , selector value is value"
            echo "        --node-selector2 key value    set nodeSelector. selector key is key , selector value is value"
            echo "        --add-host host:ip            add a custom host-to-IP to /etc/hosts"
            echo "        --name pod-name               set pod name prefix. default: taken from image name"
            echo "    -e, --env key=value               set environment variables"
            echo "        --timeout seconds             set pod run timeout (default 300 seconds)"
            echo "    -i, --interactive                 Keep stdin open on the container(s) in the pod"
            echo "    -t, --tty                         Allocated a TTY for each container in the pod."
            echo "    -v, --volume hostpath:destpath    pseudo volume bind (copy current directory) to/from pod."
            echo "    +v, ++volume                      stop automatic pseudo volume bind PWD to/from pod."
            echo "        --read-only                   carry on volume files into pod, but not carry out volume files from pod"
            echo "        --hostpath hostpath:mountpath use hostpath and pod-mount-path"
            echo "    -w, --workdir pathname            set pseudo working directory (must be absolute path name)"
            echo "        --workingdir pathname         set workingDir to pod (must be absolute path name)"
            echo "        --source-profile file.sh      set pseudo profile shell name in workdir"
            echo "        --limit-memory value          set resources.limits.memory value for pod"
            echo "        --runas  uid                  set runas user for pod"
            echo "        --no-proxy                    do not set proxy environment variables for pod"
            echo "        --no-docker-host              do not set DOCKER_HOST environment variables for pod"
            echo "        --dry-run                     print out pod yaml and exit."
            echo "        --docker-registry-server      create secrets for imagePullSecrets part 1"
            echo "                                      (https://index.docker.io/v1/ for DockerHub)"
            echo "                                      secret name regcred is generated"
            echo "        --docker-registry-username    create secrets for imagePullSecrets part 2"
            echo "        --docker-registry-password    create secrets for imagePullSecrets part 3"
            echo ""
            echo "    ENVIRONMENT VARIABLES"
            echo "        KUBE_RUN_V_IMAGE              set default image name"
            echo "        KUBE_RUN_V_ADD_HOST_1         set host:ip for apply --add-host option"
            echo "        DOCKER_HOST                   pass to pod when kubectl run"
            echo "        http_proxy                    pass to pod when kubectl run"
            echo "        https_proxy                   pass to pod when kubectl run"
            echo "        ftp_proxy                     pass to pod when kubectl run"
            echo "        no_proxy                      pass to pod when kubectl run"
            echo ""
            return 0
        fi
        # それ以外のオプションならkubectl execに渡すコマンドラインオプションとみなす
        if [ -z "$command_line" ]; then
            command_line="$1"
        else
            command_line="$command_line $1"
        fi
        shift
    done

    # after argument check
    if [ -z "$namespace" ]; then
        namespace="default"
        kubectl_cmd_namespace_opt="--namespace $namespace"
    fi
    if [ -z "$serviceaccount" ]; then
        serviceaccount="mycentos7docker-${namespace}"
        chk=$( f-check-run-pod-serviceaccount )
        if [ x"$chk"x = x"yes"x ] ; then
            echo "  f-check-run-pod-serviceaccount result is $chk"
            kubectl_run_opt_serviceaccount="--serviceaccount=${serviceaccount}"
        else
            serviceaccount_json=' "serviceAccountName": "'${serviceaccount}'" '
        fi
    fi
    if [ -z "$pod_name_prefix" ]; then
        pod_name_prefix=${image##*/}
        pod_name_prefix=${pod_name_prefix%%:*}
    fi
    if [ -z "$pseudo_volume_list" ]; then
        # current directory copy into pod.
        pseudo_volume_list="$PWD:/$( basename $PWD )"
    fi
    if [ -z "$command_line" ]; then
            interactive="-i"
            tty="-t"
            i_or_tty=yes
    fi
    if [ ! -z "$docker_pull" ]; then
        $DOCKER_SUDO_CMD docker pull $image
    fi

    # check ../*-recover.sh file when volume carry out is true
    if [ x"$volume_carry_out"x = x"true"x ]; then
        f-check-and-run-recover-sh
    fi

    # set default value for carry_on_kubeconfig
    if [ -z "$carry_on_kubeconfig" ]; then
        # automatic detect
        local kubectl_current_context=$( kubectl config current-context 2>/dev/null )
        if [ x"$kubectl_current_context"x = x"docker-for-desktop"x ]; then
            carry_on_kubeconfig=no
        else
            carry_on_kubeconfig=$( f-check-kubeconfig-carry-on )
        fi
    fi
    if [ x"$carry_on_kubeconfig"x = x"yes"x  ]; then
        tmp_kubeconfig=$( mktemp "$PWD/../kube-run-v-kubeconfig-XXXXXXXXXXXX" )
        RC=$? ; if [ $RC -ne 0 ]; then echo "  mktemp failed. abort." ; return 1; fi
        carry_on_kubeconfig_file=$( realpath $tmp_kubeconfig )
        kubectl config view --raw > $carry_on_kubeconfig_file
        RC=$? ; if [ $RC -ne 0 ]; then echo "  kubectl config view failed. abort." ; return 1; fi
        pseudo_volume_list="$pseudo_volume_list $carry_on_kubeconfig_file:~/.kube/config"
    fi

    # check kubectl run dry-run optin
    dry_run_result=$( f-check-dry-run-pod )
    if [ x"$dry_run_result"x = x"yes"x ] ; then
        dry_run_opt=" --dry-run=client -o yaml "
    else
        dry_run_opt=" --dry-run -o yaml "
    fi

    # check kubectl run generator option
    generator_result=$( f-check-generator-run-pod )
    if [ x"$generator_result"x = x"yes"x ]; then
        generator_opt=" --generator=run-pod/v1 "
    fi

    # setup namespace
    if kubectl get namespace $namespace ; then
        echo "namespace $namespace is found."
    else
        echo "namespace $namespace is not found. create it."
        kubectl create namespace $namespace
        RC=$? ; if [ $RC -ne 0 ]; then echo "create namespace error. abort." ; return $RC; fi
    fi

    # setup serviceaccount
    if  kubectl ${kubectl_cmd_namespace_opt} get serviceaccount ${serviceaccount} > /dev/null ; then
        echo "  service account ${serviceaccount} found."
    else
        kubectl ${kubectl_cmd_namespace_opt} create serviceaccount ${serviceaccount}
        RC=$? ; if [ $RC -ne 0 ]; then echo "create serviceaccount error. abort." ; return $RC; fi

    fi

    # setup cluster role binding
    if kubectl get clusterrolebinding ${serviceaccount} ; then
        echo "  cluster role binding ${serviceaccount} found."
    else
        kubectl create clusterrolebinding ${serviceaccount} \
            --clusterrole cluster-admin \
            --serviceaccount=${namespace}:${serviceaccount}
        RC=$? ; if [ $RC -ne 0 ]; then echo "create clusterrolebinding error. abort." ; return $RC; fi
    fi
    
    # setup imagePullSecrets , if set
    if [ -n "$docker_registry_name" -o -n "$docker_registry_username" -o -n "$docker_registry_password" ] ; then
        if  kubectl ${kubectl_cmd_namespace_opt} get secrets regcred > /dev/null ; then
            echo "  secrets regcred found."
        else
            # docker registry 用のsecretsを作成する
            echo "kubectl create secret docker-registry regcred"
            kubectl ${kubectl_cmd_namespace_opt} create secret docker-registry regcred \
                --docker-server="$docker_registry_name" \
                --docker-username="$docker_registry_username" \
                --docker-password="$docker_registry_password" \
                --docker-email="mycentos7docker@example.com"
            RC=$? ; if [ $RC -ne 0 ] ; then echo "create secrets docker-registry error. abort."; return 1; fi
            # set image pull secret name
            image_pull_secrets_json=' "imagePullSecrets" : [ { "name" : "regcred" } ] '
        fi
    fi

    local TMP_RANDOM=$( date '+%Y%m%d%H%M%S' )
    local POD_NAME="${pod_name_prefix}-$TMP_RANDOM"
    if  kubectl ${kubectl_cmd_namespace_opt} get pod/${POD_NAME} > /dev/null 2>&1 ; then
        echo "  already running pod/${POD_NAME}"
    else
        # support workingdir
        if [ -n "$workingdir" -o -n "$limits_memory" -o -n "$hostpath_volume_mounts_json" ]; then
            # PODの中をoverrideする場合は、全部ここに記述しないといけない；；
            tmp_docker_host_kv=
            tmp_proxy_kv=
            if [ -z "$no_carry_on_docker_host" ]; then
                tmp_docker_host_kv="DOCKER_HOST=$DOCKER_HOST"
            fi
            if [ -z "$no_carry_on_proxy" ]; then
                tmp_proxy_kv="http_proxy=$http_proxy https_proxy=$https_proxy ftp_proxy=$ftp_proxy no_proxy=$no_proxy"
            fi
            for envproxy in  $tmp_proxy_kv  $tmp_docker_host_kv
            do
                local env_key_val=$envproxy
                local env_key=${env_key_val%%=*}
                local env_val=${env_key_val#*=}
                if [ -z "$env_opts" ]; then
                    env_opts="--env $env_key=$env_val"
                    env_json=' { "name":  "'$env_key'" , "value": "'$env_val'" } '
                else
                    env_opts="$env_opts --env $env_key=$env_val"
                    env_json="$env_json"' , {  "name" : "'$env_key'" , "value" : "'$env_val'" } '
                fi
            done
            workingdir_json=' "containers" : [ {
                "name": "'$POD_NAME'" ,
                "image": "'$image'",
                "imagePullPolicy": "'$image_pull_policy_json'",
                "workingDir" : "'$workingdir'" ,
                "command" : [ "tail", "-f", "/dev/null" ],
                "env": [
                    '"$env_json"'
                ],
                "resources" : { '"$limits_memory_json"' },
                "volumeMounts" : [ '"$hostpath_volume_mounts_json"' ]
            } ] '
            # echo "workingdir_json is $workingdir_json"
        fi
        local volume_elem_json=
        # generate override json
        local override_base_json=
        local override_elem=
        local override_buff=
        local volumes_elem=
        if [ -n "$hostpath_volumes_json" ]; then
            volumes_elem=" \"volumes\" : [ $hostpath_volumes_json ] "
        fi
        for override_elem in "$runas_option_json" "$image_pull_secrets_json" "$node_select_json" "$workingdir_json" "$volumes_elem" "$serviceaccount_json"
        do
            if [ -n "$override_elem" ]; then
                if [ -z "$override_buff" ]; then
                    override_buff="$override_elem"
                else
                    override_buff="${override_buff}, ${override_elem}"
                fi
            fi
        done
        if [ x"$override_buff"x = x""x ] ; then
            override_opt=" --overrides "
            override_base_json=
        else
            override_opt=" --overrides "
            override_base_json=' { "apiVersion": "v1", "spec" : { '"${override_buff}"' } } '
        fi
        local kubectl_proxy_env_opt=
        if [ -z "$no_carry_on_docker_host" ]; then
            kubectl_proxy_env_opt="${kubectl_proxy_env_opt}"' --env='"DOCKER_HOST=${DOCKER_HOST} "
        fi
        if [ -z "$no_carry_on_proxy" ]; then
            kubectl_proxy_env_opt="${kubectl_proxy_env_opt}"'--env='"http_proxy=${http_proxy}"' --env='"https_proxy=${https_proxy}"' --env='"ftp_proxy=${ftp_proxy}"' --env='"no_proxy=${no_proxy}"
        fi

        # echo "override_base_json is $override_base_json"
        if true ; then
            # dry run
            echo "  "
            echo "  ### dry-run : Pod yaml info start"
            echo ""
            set -x
            kubectl run ${generator_opt} ${POD_NAME} --restart=Never \
                ${override_opt}  "${override_base_json}" \
                --image=$image \
                $imagePullOpt \
                ${kubectl_run_opt_serviceaccount} \
                ${kubectl_cmd_namespace_opt} \
                ${kubectl_proxy_env_opt} \
                ${env_opts} \
                ${dry_run_opt} \
                --command -- sleep 9999999
            RC=$? 
            set +x
            if [ $RC -ne 0 ]; then echo "kubectl dry-run error. abort." ; return $RC; fi
            echo ""
            echo "  ### dry-run : Pod yaml info end"
            echo "  "
        fi

        # if dry-run , exit here
        if [ x"$dry_run"x = x"yes"x ] ; then
            echo "  dry_run mode. abort here."
            return 0
        fi

        # run
        set -x
        kubectl run ${generator_opt} ${POD_NAME} --restart=Never \
            --image=$image \
            $imagePullOpt \
            ${override_opt}  "${override_base_json}" \
            ${kubectl_run_opt_serviceaccount} \
            ${kubectl_cmd_namespace_opt} \
            ${kubectl_proxy_env_opt}  ${env_opts} -- sleep 9999999
        RC=$?
        set +x
        if [ $RC -ne 0 ]; then echo "kubectl run error. abort." ; return $RC; fi

        # wait for pod Running
        local count=0
        while true
        do
            sleep 2
            local STATUS=$(kubectl ${kubectl_cmd_namespace_opt} get pod/${POD_NAME} | awk '{print $3}' | grep Running)
            RC=$? ; if [ $RC -ne 0 ]; then echo "error. abort." ; return $RC; fi
            if [ ! -z "$STATUS" ]; then
                echo ""
                break
            fi
            echo -n -e "\r  waiting for running pod ... $count / $pod_timeout seconds ..."
            sleep 3
            count=$( expr $count + 5 )
            if [ $count -gt ${pod_timeout} ]; then
                echo "timeout for pod Running. abort."
                return 1
            fi
        done
    fi

    # archive current directory
    local TMP_ARC_FILE=$( mktemp  "../${POD_NAME}-XXXXXXXXXXXX.tar.gz" )
    local TMP_ARC_FILE_RECOVER=${TMP_ARC_FILE}-recover.sh
    local TMP_ARC_FILE_IN_POD=$( echo $TMP_ARC_FILE | sed -e 's%^\.\./%%g' )
    local TMP_DEST_FILE=${namespace}/${POD_NAME}:${TMP_ARC_FILE}
    local TMP_DEST_MSYS2=$( echo $TMP_DEST_FILE | sed -e 's%:\.\./%:%g' )
    local TMP_ARC_DIR=$( echo $TMP_ARC_FILE | sed -e 's%.tar.gz%%g' )
    local TMP_ARC_DIR_FILE=${TMP_ARC_DIR}/$( echo $TMP_ARC_FILE | sed -e 's%^../%%g' )
    local TMP_ARC_FILE_CURRENT_DIR=$( echo $TMP_ARC_FILE | sed -e 's%^../%%g' )

    # pseudo volume bind
    if [ ! -z "$pseudo_volume_bind" ]; then
        # volume list
        for volarg in $pseudo_volume_list
        do
            # parse argument
            pseudo_volume_left=${volarg%%:*}
            pseudo_volume_right=${volarg##*:}
            if [ x"$pseudo_volume_left"x = x"$volarg"x ]; then
                echo "  volume list is hostpath:destpath.  : is not found. abort."
                return 1
            elif [ -f "$pseudo_volume_left" ]; then
                echo "OK" > /dev/null
            elif [ -d "$pseudo_volume_left" ]; then
                echo "OK" > /dev/null
            else
                echo "  volume list is hostpath:destpath.  hostpath $pseudo_volume_left is not a directory nor file. abort."
                return 1
            fi
            echo "  process ... $pseudo_volume_left : $pseudo_volume_right ..."

            # create archive file
            echo "  creating archive file : $TMP_ARC_FILE"
            if [ -f "$pseudo_volume_left" ]; then
                ( cd $( dirname $pseudo_volume_left ) ; tar czf - $( basename $pseudo_volume_left ) ) > $TMP_ARC_FILE
                RC=$? ; if [ $RC -ne 0 ]; then echo "tar error. abort." ; return $RC; fi
            elif [ -d "$pseudo_volume_left" ]; then
                ( cd $pseudo_volume_left ; tar czf - . ) > $TMP_ARC_FILE
                RC=$? ; if [ $RC -ne 0 ]; then echo "tar error. abort." ; return $RC; fi
            else
                echo "path $pseudo_volume_left is not a directory nor file. abort."
                return 1
            fi

            # kubectl cp
            echo "  kubectl cp into pod ${TMP_ARC_FILE}  ${TMP_DEST_MSYS2}"
            kubectl cp  ${kubectl_cmd_namespace_opt}  ${TMP_ARC_FILE}  ${TMP_DEST_MSYS2}
            RC=$? ; if [ $RC -ne 0 ]; then echo "kubectl cp error. abort." ; return $RC; fi

            # kubectl exec ... import and extract archive
            echo "  kubectl exec extract archive in pod"
            if [ -f "$pseudo_volume_left" ]; then
                # ファイルの場合は特例。一度tmpで展開してからターゲットにmvする。
                kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " mkdir -p $( dirname $pseudo_volume_right )"
                kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " mkdir -p /tmp/kube-run-v-tmp"
                kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " tar xzf $TMP_ARC_FILE_IN_POD -C /tmp/kube-run-v-tmp"
                kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " alias mv=mv ; mv /tmp/kube-run-v-tmp/$( basename $pseudo_volume_left ) $pseudo_volume_right "
                kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " alias rm=rm ; rm -rf /tmp/kube-run-v-tmp"
            elif [ -d "$pseudo_volume_left" ]; then
                kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " mkdir -p $pseudo_volume_right "
                kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " tar xzf $TMP_ARC_FILE_IN_POD -C $pseudo_volume_right "
            fi
            kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " alias rm=rm ; rm $TMP_ARC_FILE_IN_POD "
        done
    fi

    if [ ! -z "$add_hosts_list" ] ; then
        local i=
        for i in $add_hosts_list
        do
            local tmp_host=${i%%:*}
            local tmp_ip=${i##*:}
            # kubectl exec ... add /etc/hosts
            echo "  kubectl exec add $tmp_ip $tmp_host to /etc/hosts"
            kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " echo $tmp_ip $tmp_host >> /etc/hosts "
        done
    fi

    if [ ! -z "$pseudo_workdir" ]; then
        # kubectl exec ... set workdir
        kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " mkdir -p /etc/profile.d "
        kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " echo cd $pseudo_workdir >> /etc/profile.d/workdir.sh "
        kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " mkdir -p $pseudo_workdir "
    fi

    if [ ! -z "$pseudo_profile" ]; then
        # kubectl exec ... set profile
        kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " mkdir -p /etc/profile.d "
        kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " echo source $pseudo_profile >> /etc/profile.d/workdir.sh "
    fi

    # create recover shell , when terminal is suddenly gone.
    if [ ! -z "$pseudo_volume_bind" ]; then
        if [ ! -z "$volume_carry_out" ]; then
            echo "  create recover shell ${TMP_ARC_FILE_RECOVER}"
            echo "#!/bin/bash" >> ${TMP_ARC_FILE_RECOVER}
            echo "#" >> ${TMP_ARC_FILE_RECOVER}
            echo "# recover shell when terminal is abort, but pod is running." >> ${TMP_ARC_FILE_RECOVER}
            echo "#" >> ${TMP_ARC_FILE_RECOVER}
            echo "" >> ${TMP_ARC_FILE_RECOVER}
            echo "set -ex" >> ${TMP_ARC_FILE_RECOVER}
            echo "" >> ${TMP_ARC_FILE_RECOVER}
            echo "cd $PWD" >> ${TMP_ARC_FILE_RECOVER}
            echo "" >> ${TMP_ARC_FILE_RECOVER}
            for volarg in $pseudo_volume_list
            do
                # parse argument
                pseudo_volume_left=${volarg%%:*}
                pseudo_volume_right=${volarg##*:}
                if [ x"$pseudo_volume_left"x = x"$volarg"x ]; then
                    echo "  volume list is hostpath:destpath.  : is not found. abort."
                    return 1
                elif [ -f "$pseudo_volume_left" ]; then
                    echo "OK" > /dev/null
                elif [ -d "$pseudo_volume_left" ]; then
                    echo "OK" > /dev/null
                else
                    echo "  volume list is hostpath:destpath.  hostpath is not a directory nor file. abort."
                    return 1
                fi

                # kubectl exec ... create archive and kubectl cp to export
                if [ -d "$pseudo_volume_left" ]; then
                    echo "kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c \" ( cd $pseudo_volume_right && tar czf - . ) > $TMP_ARC_FILE_IN_POD \"" >> ${TMP_ARC_FILE_RECOVER}
                elif [ -f "$pseudo_volume_left" ]; then
                    echo "kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c \" ( cd $( dirname $pseudo_volume_right ) && tar czf - $( basename $pseudo_volume_right ) ) > $TMP_ARC_FILE_IN_POD \"" >> ${TMP_ARC_FILE_RECOVER}
                else
                    echo "volume list $pseudo_volume_list is not a directory for file. aobrt."
                    return 1
                fi

                # kubectl cp get archive file
                echo "/bin/rm -f $TMP_ARC_FILE"  >> ${TMP_ARC_FILE_RECOVER}
                echo "mkdir -p $TMP_ARC_DIR"  >> ${TMP_ARC_FILE_RECOVER}
                echo "if kubectl cp  ${kubectl_cmd_namespace_opt}  ${TMP_DEST_MSYS2}  ${TMP_ARC_DIR} ; then"  >> ${TMP_ARC_FILE_RECOVER}
                echo "    /bin/mv ${TMP_ARC_DIR_FILE} $TMP_ARC_FILE"  >> ${TMP_ARC_FILE_RECOVER}
                echo "    /bin/rmdir $TMP_ARC_DIR"  >> ${TMP_ARC_FILE_RECOVER}
                echo "elif kubectl cp  ${kubectl_cmd_namespace_opt}  ${TMP_DEST_MSYS2}  ${TMP_ARC_FILE_CURRENT_DIR} ; then"  >> ${TMP_ARC_FILE_RECOVER}
                echo "    /bin/mv ${TMP_ARC_FILE_CURRENT_DIR} $TMP_ARC_FILE"  >> ${TMP_ARC_FILE_RECOVER}
                echo "    /bin/rmdir $TMP_ARC_DIR"  >> ${TMP_ARC_FILE_RECOVER}
                echo "else"  >> ${TMP_ARC_FILE_RECOVER}
                echo "    echo kubectl cp error."  >> ${TMP_ARC_FILE_RECOVER}
                echo "    exit 1"  >> ${TMP_ARC_FILE_RECOVER}
                echo "fi"  >> ${TMP_ARC_FILE_RECOVER}

                # if rsync is present, use rsync
                if [ x"$RSYNC_MODE"x = x"true"x ]; then
                    # extract archive file into temp directory
                    local TMP_EXT_DIR=$( mktemp -d ../${POD_NAME}-tmp-XXXXXXXXXXXX )
                    echo "mkdir -p ${TMP_EXT_DIR}" >> ${TMP_ARC_FILE_RECOVER}
                    echo "tar xzf $TMP_ARC_FILE -C $TMP_EXT_DIR" >> ${TMP_ARC_FILE_RECOVER}
                    echo "/bin/rm -f $TMP_ARC_FILE" >> ${TMP_ARC_FILE_RECOVER}

                    # rsync data copy
                    if [ -f "$pseudo_volume_left" ]; then
                        echo "rsync -rvc --delete $TMP_EXT_DIR/$( basename $pseudo_volume_right )  $( f-rsync-escape-relative $pseudo_volume_left )" >> ${TMP_ARC_FILE_RECOVER}
                    elif [ -d "$pseudo_volume_left" ]; then
                        echo "rsync -rvc --delete $TMP_EXT_DIR/  $( f-rsync-escape-relative $pseudo_volume_left/ )" >> ${TMP_ARC_FILE_RECOVER}
                    fi
                    # remove temp dir
                    echo "/bin/rm -rf $TMP_EXT_DIR" >> ${TMP_ARC_FILE_RECOVER}
                    /bin/rm -rf $TMP_EXT_DIR
                else
                    # rsync is not present.  tar overwrite
                    if [ -f "$pseudo_volume_left" ]; then
                        echo "tar xzf $TMP_ARC_FILE -C $( dirname $pseudo_volume_left )" >> ${TMP_ARC_FILE_RECOVER}
                    elif [ -d "$pseudo_volume_left" ]; then
                        echo "( tar xzf $TMP_ARC_FILE -C $pseudo_volume_left )" >> ${TMP_ARC_FILE_RECOVER}
                    fi
                    echo "/bin/rm -f $TMP_ARC_FILE" >> ${TMP_ARC_FILE_RECOVER}
                fi

                # delete pod
                echo "if kubectl ${kubectl_cmd_namespace_opt} delete pod ${POD_NAME} --grace-period 3 ; then" >> ${TMP_ARC_FILE_RECOVER}
                echo "    echo pod delete success." >> ${TMP_ARC_FILE_RECOVER}
                echo "else" >> ${TMP_ARC_FILE_RECOVER}
                echo "    echo pod delete failure." >> ${TMP_ARC_FILE_RECOVER}
                echo "fi" >> ${TMP_ARC_FILE_RECOVER}
            done
        fi
    fi
    if [ x"$carry_on_kubeconfig"x = x"yes"x ]; then
        echo "/bin/rm -f $carry_on_kubeconfig_file" >> ${TMP_ARC_FILE_RECOVER}
    fi


    # exec into pod
    if [ ! -z "$i_or_tty" ]; then
        # interactive mode
        echo "  # main command run"
        echo "  base workdir name : $pseudo_workdir"
        echo "  interactive mode"
        set -x
        ${WINPTY_CMD} kubectl exec ${interactive}  ${tty}  ${kubectl_cmd_namespace_opt} ${POD_NAME}  -- bash --login
        RC=$?
        set +x
    else
        echo "  # main command run"
        echo "  base workdir name : $pseudo_workdir"
        echo "  running command : $command_line"
        set -x
        ${WINPTY_CMD} kubectl exec                         ${kubectl_cmd_namespace_opt} ${POD_NAME}  -- bash --login -c  "$command_line"
        RC=$?
        set +x
    fi

    # after pod exit
    if [ ! -z "$pseudo_volume_bind" ]; then
        if [ ! -z "$volume_carry_out" ]; then
            for volarg in $pseudo_volume_list
            do
                # parse argument
                pseudo_volume_left=${volarg%%:*}
                pseudo_volume_right=${volarg##*:}
                if [ x"$pseudo_volume_left"x = x"$volarg"x ]; then
                    echo "  volume list is hostpath:destpath.  : is not found. abort."
                    return 1
                elif [ -f "$pseudo_volume_left" ]; then
                    echo "OK" > /dev/null
                elif [ -d "$pseudo_volume_left" ]; then
                    echo "OK" > /dev/null
                else
                    echo "  volume list is hostpath:destpath.  hostpath is not a directory nor file. abort."
                    return 1
                fi
                echo "  processing volume list ... $pseudo_volume_left : $pseudo_volume_right "

                # kubectl exec ... create archive and kubectl cp to export
                echo "  creating archive file in pod : $TMP_ARC_FILE_IN_POD"
                if [ -d "$pseudo_volume_left" ]; then
                    kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " ( cd $pseudo_volume_right && tar czf - . ) > $TMP_ARC_FILE_IN_POD "
                    RC=$? ; if [ $RC -ne 0 ]; then echo "kubectl exec error. abort." ; return $RC; fi
                elif [ -f "$pseudo_volume_left" ]; then
                    kubectl exec ${kubectl_cmd_namespace_opt} ${POD_NAME} -- bash -c " ( cd $( dirname $pseudo_volume_right ) && tar czf - $( basename $pseudo_volume_right ) ) > $TMP_ARC_FILE_IN_POD "
                    RC=$? ; if [ $RC -ne 0 ]; then echo "kubectl exec error. abort." ; return $RC; fi
                else
                    echo "volume list $pseudo_volume_list is not a directory for file. aobrt."
                    return 1
                fi

                # kubectl cp get archive file
                echo "  kubectl cp from pod"
                /bin/rm -f $TMP_ARC_FILE
                mkdir -p $TMP_ARC_DIR
                # kubectl cp pod から ローカルへ。
                # kubernetes 1.14.2 より前は、ローカル側はディレクトリしか指定できない
                # kubernetes 1.14.2 以降は、コピー元がファイルなら、ローカル側もファイルを指定しないといけない
                if echo "  trying directory mode ..." ; kubectl cp  ${kubectl_cmd_namespace_opt}  ${TMP_DEST_MSYS2}  ${TMP_ARC_DIR} ; then
                    echo "  directory mode success."
                    /bin/mv ${TMP_ARC_DIR_FILE} $TMP_ARC_FILE
                    /bin/rmdir $TMP_ARC_DIR
                elif echo "  trying file mode ..." ; kubectl cp  ${kubectl_cmd_namespace_opt}  ${TMP_DEST_MSYS2}  ${TMP_ARC_FILE_CURRENT_DIR} ; then
                    echo "  file mode success."
                    /bin/mv ${TMP_ARC_FILE_CURRENT_DIR} $TMP_ARC_FILE
                    /bin/rmdir $TMP_ARC_DIR
                else
                    echo "kubectl cp error. abort."
                    return 1
                fi

                # if rsync is present, use rsync
                if [ x"$RSYNC_MODE"x = x"true"x ]; then
                    # extract archive file into temp directory
                    local TMP_EXT_DIR=$( mktemp -d "../${POD_NAME}-tmp-XXXXXXXXXXXX" )
                    echo "  tar extracting in $TMP_EXT_DIR"
                    tar xzf $TMP_ARC_FILE -C $TMP_EXT_DIR
                    RC=$? ; if [ $RC -ne 0 ]; then echo "tar error. abort." ; return $RC; fi
                    /bin/rm -f $TMP_ARC_FILE

                    # rsync data copy
                    if [ -f "$pseudo_volume_left" ]; then
                        # ファイルの場合は特例。一度テンポラリで展開してmvする。
                        echo "  rsync -rvc --delete $TMP_EXT_DIR/$( basename $pseudo_volume_right )  $( f-rsync-escape-relative $pseudo_volume_left )"
                        rsync -rvc --delete $TMP_EXT_DIR/$( basename $pseudo_volume_right )  $( f-rsync-escape-relative $pseudo_volume_left )
                        RC=$? ; if [ $RC -ne 0 ]; then echo "  rsync error. abort." ; return $RC; fi
                    elif [ -d "$pseudo_volume_left" ]; then
                        echo "  rsync -rvc --delete $TMP_EXT_DIR/  $( f-rsync-escape-relative $pseudo_volume_left/ ) "
                        rsync -rvc --delete $TMP_EXT_DIR/  $( f-rsync-escape-relative $pseudo_volume_left/ )
                        RC=$? ; if [ $RC -ne 0 ]; then echo "  rsync error. abort." ; return $RC; fi
                    fi
                    # remove temp dir
                    /bin/rm -rf $TMP_EXT_DIR
                else
                    # rsync is not present.  tar overwrite
                    echo "  tar extract from : $TMP_ARC_FILE "
                    if [ -f "$pseudo_volume_left" ]; then
                        tar xzf $TMP_ARC_FILE -C $( dirname $pseudo_volume_left )
                        RC=$? ; if [ $RC -ne 0 ]; then echo "tar error. abort." ; return $RC; fi
                    elif [ -d "$pseudo_volume_left" ]; then
                        ( tar xzf $TMP_ARC_FILE -C $pseudo_volume_left )
                        RC=$? ; if [ $RC -ne 0 ]; then echo "tar error. abort." ; return $RC; fi
                    fi
                    /bin/rm -f $TMP_ARC_FILE
                fi
            done
        fi
    fi

    if [ x"$carry_on_kubeconfig"x = x"yes"x ]; then
        /bin/rm -f $carry_on_kubeconfig_file
    fi

    # delete pod
    echo "  delete pod ${POD_NAME} ${kubectl_cmd_namespace_opt}"
    kubectl delete pod ${POD_NAME} ${kubectl_cmd_namespace_opt} --grace-period 3
    RC=$? ; if [ $RC -ne 0 ]; then echo "kubectl delete error. abort." ; return $RC; fi

    # delete recover shell
    echo "  delete recover shell ${TMP_ARC_FILE_RECOVER}"
    /bin/rm -f ${TMP_ARC_FILE_RECOVER}
}

# if source this file, define function only ( not run )
if [ ${#BASH_SOURCE[@]} = 1 ]; then
    f-kube-run-v "$@"
    RC=$?
    exit $RC
else
    echo "source from $0. define function only. not run." > /dev/null
fi

#
# end of file
#
