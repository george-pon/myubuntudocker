#!/bin/bash
#
# docker-run-v.sh  自作イメージ(mycentos7docker/mydebian9docker)を起動する
#
#   bashが入っているイメージなら、centosでもdebianでもubuntuでも動く
#
#   コンテナ起動後、カレントディレクトリの内容をコンテナの中にコピーしてから、docker exec -i -t する
#
#   コンテナからexitした後、ディレクトリの内容をコンテナから取り出してカレントディレクトリに上書きする。
#
#   お気に入りのコマンドをインストール済みのdockerイメージを使って作業しよう
#
#   docker run -v $PWD:$( basename $PWD ) centos  みたいなモノ
#   DOCKER_HOSTがローカルに無くて volume mount が使えない場合の代替品のシェル
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
            FSYS_FLAG=
            # if not MSYS, normal return
            echo "$@"
            return 0
        fi
    fi

    # check cmd is found
    if type cmd 2>/dev/null 1>/dev/null ; then
        # check msys convert
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
                echo    "  warning. found $i file.  run $i and remove it before run docker-run-v."
                echo -n "  do you want to run $i ? [yes/no/clear] : "
                read ans
                if [ x"$ans"x = x"y"x  -o  x"$ans"x = x"yes"x ]; then
                    bash -x "$i"
                    /bin/rm -f "$i"
                    /bin/rm -f "../docker-run-v-kubeconfig-*"
                    break
                fi
                if [ x"$ans"x = x"n"x  -o  x"$ans"x = x"no"x ]; then
                    break
                fi
                if [ x"$ans"x = x"c"x  -o  x"$ans"x = x"clear"x ]; then
                    /bin/rm -f "$i"
                    /bin/rm -f "../docker-run-v-kubeconfig-*"
                    break
                fi
            done
        fi
    done
}


#
# 自作イメージを起動して、カレントディレクトリのファイル内容をコンテナ内部に持ち込む
#   for kubernetes  ( Linux Bash or Git-Bash for Windows MSYS2 )
#
# カレントディレクトリのディレクトリ名の末尾(basename)の名前で、
# container内部のルート( / )にディレクトリを作ってファイルを持ち込む
# 
# containerの中のシェル終了後、containerからファイルの持ち出しをやる。rsyncがあればrsync -crvを使う。無ければtarで上書き展開する。
#
#   https://hub.docker.com/r/georgesan/mycentos7docker/  docker hub に置いてあるイメージ(default)
#   https://github.com/george-pon/mycentos7docker  イメージの元 for centos
#   https://gitlab.com/george-pon/mydebian9docker  イメージの元 for debian
#
#
# パスの扱いがちとアレすぎるので docker cp は注意。
# ファイルの実行属性を落としてくるので docker cp は注意。
#
function f-docker-run-v() {

    # check PWD ( / で実行は許可しない )
    if [ x"$PWD"x = x"/"x ]; then
        echo "docker-run-v: can not run. PWD is / . abort."
        return 1
    fi
    # check PWD ( /tmp で実行は許可しない )
    if [ x"$PWD"x = x"/tmp"x ]; then
        echo "docker-run-v: can not run. PWD is /tmp . abort."
        return 1
    fi

    # check rsync command present.
    local RSYNC_MODE=true
    if type rsync  2>/dev/null 1>/dev/null ; then
        echo "  command rsync OK" > /dev/null
    else
        echo "  command rsync not found." > /dev/null
        RSYNC_MODE=false
    fi

    # check sudo command present.
    local DOCKER_SUDO_CMD=sudo
    if type sudo 2>/dev/null 1>/dev/null ; then
        echo "  command sudo OK" > /dev/null
    else
        echo "  command sudo not found." > /dev/null
        DOCKER_SUDO_CMD=
    fi

    # check docker version
    docker version > /dev/null
    RC=$? ; if [ $RC -ne 0 ]; then echo "docker version error. abort." ; return $RC; fi

    local interactive=
    local tty=
    local i_or_tty=
    local image=registry.gitlab.com/george-pon/mydebian11docker:latest
    local container_name_prefix=
    local container_timeout=600
    local command_line=
    local env_opts=
    local memory_opt=
    local user_option=
    local pseudo_volume_bind=true
    local pseudo_volume_list=
    local pseudo_volume_left=
    local pseudo_volume_right=
    local real_volume_opt=
    local add_host_opt=
    local docker_pull=
    local pseudo_workdir=/$( basename $PWD )
    local workingdir=
    local pseudo_profile=
    local pseudo_initfile=
    local volume_carry_out=true
    local no_carry_on_proxy=
    local no_carry_on_docker_host=
    # docker create secret docker-registry <name> --docker-server=DOCKER_REGISTRY_SERVER --docker-username=DOCKER_USER --docker-password=DOCKER_PASSWORD --docker-email=DOCKER_EMAIL
    local command_line_pass_mode=
    local publish_port_opt=

    f-check-winpty 2>/dev/null

    # environment variables
    if [ ! -z "$DOCKER_RUN_V_IMAGE" ]; then
        image=${DOCKER_RUN_V_IMAGE}
    fi
    if [ ! -z "$DOCKER_RUN_V_ADD_HOST_1" ]; then
        add_host_opt="$add_host_opt --add-host $DOCKER_RUN_V_ADD_HOST_1"
    fi
    if [ ! -z "$DOCKER_RUN_V_ADD_HOST_2" ]; then
        add_host_opt="$add_host_opt --add-host $DOCKER_RUN_V_ADD_HOST_2"
    fi
    if [ ! -z "$DOCKER_RUN_V_ADD_HOST_3" ]; then
        add_host_opt="$add_host_opt --add-host $DOCKER_RUN_V_ADD_HOST_3"
    fi
    if [ ! -z "$DOCKER_RUN_V_ADD_HOST_4" ]; then
        add_host_opt="$add_host_opt --add-host $DOCKER_RUN_V_ADD_HOST_4"
    fi
    if [ ! -z "$DOCKER_RUN_V_ADD_HOST_5" ]; then
        add_host_opt="$add_host_opt --add-host $DOCKER_RUN_V_ADD_HOST_5"
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
            add_host_opt="$add_host_opt --add-host $2"
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
        if [ x"$1"x = x"--source-profile"x ]; then
            pseudo_profile=$2
            if [ -r "$pseudo_profile" ] ; then 
                echo "OK. pseudo_profile $pseudo_profile is readable." > /dev/null
            else
                echo "ERROR. pseudo_profile $pseudo_profile is NOT readable. abort."
                return 1
            fi
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"--source-initfile"x ]; then
            pseudo_initfile=$2
            if [ -r "$pseudo_initfile" ] ; then 
                echo "OK. pseudo_initfile $pseudo_initfile is readable." > /dev/null
            else
                echo "ERROR. pseudo_initfile $pseudo_initfile is NOT readable. abort."
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
            else
                env_opts="$env_opts --env $env_key=$( f-msys-escape $env_val ) "
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
        if [ x"$1"x = x"--timeout"x ]; then
            container_timeout=$2
            shift
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
        if [ x"$1"x = x"+v"x -o x"$1"x = x"++volume"x -o x"$1"x = x"--no-volume"x ]; then
            pseudo_volume_bind=
            shift
            continue
        fi
        if [ x"$1"x = x"--real-volume"x ]; then
            real_volume_opt="$real_volume_opt --volume $2 "
            shift
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
        if [ x"$1"x = x"--docker-pull"x -o x"$1"x = x"--pull"x ]; then
            docker_pull=yes
            shift
            continue
        fi
        if [ x"$1"x = x"--read-only"x ]; then
            volume_carry_out=
            shift
            continue
        fi
        if [ x"$1"x = x"--name"x ]; then
            container_name_prefix=$2
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"--memory"x ]; then
            memory_opt="$1 $2"
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"-u"x -o x"$1"x = x"--user"x ]; then
            user_option="--user $2"
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
        if [ x"$1"x = x"-p"x -o x"$1"x = x"--publish"x ]; then
            publish_port_opt="$publish_port_opt $1 $2"
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"--command"x ]; then
            command_line_pass_mode=yes
            shift
            continue
        fi
        if [ x"$1"x = x"--help"x ]; then
            echo "docker-run-v"
            echo "        --command                     after this option , arguments pass to docker exec command line"
            echo "        --image  image-name           set docker run image name. default is $image "
            echo "        --image-centos                set image to docker.io/georgesan/mycentos7docker:latest"
            echo "        --image-ubuntu                set image to docker.io/georgesan/myubuntu2004docker:latest"
            echo "        --image-debian                set image to registry.gitlab.com/george-pon/mydebian11docker:latest (default)"
            echo "        --image-alpine                set image to registry.gitlab.com/george-pon/myalpine3docker:latest"
            echo "        --image-oraclelinux8          set image to docker.io/georgesan/myoraclelinux8docker:latest"
            echo "        --docker-pull                 docker pull image before docker run"
            echo "        --pull                        docker pull image before docker run"
            echo "        --timeout value               timeout value wait for running contaner"
            echo "        --add-host host:ip            add a custom host-to-IP to /etc/hosts"
            echo "        --name container-name         set container name prefix. default: taken from image name"
            echo "    -e, --env key=value               set environment variables"
            echo "    -i, --interactive                 Keep stdin open on the container(s) in the container"
            echo "    -t, --tty                         Allocated a TTY for each container in the container."
            echo "    -v, --volume hostpath:destpath    pseudo volume bind (copy current directory) to/from container."
            echo "    +v, ++volume                      stop automatic pseudo volume bind PWD to/from container."
            echo "        --read-only                   carry on volume files into container, but not carry out volume files from container"
            echo "        --real-volume hostpath:destpath    direct volume bind to/from container. example /var/run/docker.sock:/var/run/docker.sock "
            echo "    -w, --workdir pathname            set working directory (must be absolute path name)"
            echo "        --source-profile profile.sh   set pseudo profile shell name in workdir"
            echo "        --source-initfile file.sh     set pseudo initialize file shell name in workdir"
            echo "        --memory value                set limits memory value for container"
            echo "        --runas  uid                  set runas user for container"
            echo "        --no-proxy                    do not set proxy environment variables to container"
            echo "        --no-docker-host              do not set DOCKER_HOST environment variables to container"
            echo "    -p, --publish port-list           Publish a container's port(s) to the host"
            echo ""
            echo "    ENVIRONMENT VARIABLES"
            echo "        DOCKER_RUN_V_IMAGE            set default image name"
            echo "        DOCKER_RUN_V_ADD_HOST_1       set host:ip for apply --add-host option"
            echo "        DOCKER_HOST                   pass to container when docker run"
            echo "        http_proxy                    pass to container when docker run"
            echo "        https_proxy                   pass to container when docker run"
            echo "        no_proxy                      pass to container when docker run"
            echo ""
            return 0
        fi
        # それ以外のオプションならdocker execに渡すコマンドラインオプションとみなす
        if [ -z "$command_line" ]; then
            command_line="$1"
        else
            command_line="$command_line $1"
        fi
        shift
    done

    # after argument check

    if [ -z "$container_name_prefix" ]; then
        container_name_prefix=${image##*/}
        container_name_prefix=${container_name_prefix%%:*}
    fi
    if [ -z "$pseudo_volume_list" ]; then
        # current directory copy into container.
        pseudo_volume_list="$PWD:/$( basename $PWD )"
    fi
    if [ -z "$command_line" ]; then
            interactive="-i"
            tty="-t"
            i_or_tty=yes
    fi
    if [ ! -z "$docker_pull" ]; then
        echo "  docker pull $image"
        $DOCKER_SUDO_CMD docker pull $image
    fi

    # check ../*-recover.sh file when volume carry out is true
    if [ x"$volume_carry_out"x = x"true"x ]; then
        f-check-and-run-recover-sh
    fi

    local TMP_RANDOM=$( date '+%Y%m%d%H%M%S' )
    local container_name="${container_name_prefix}-$TMP_RANDOM"
    if  docker ps --filter name=${container_name} | grep ${container_name} > /dev/null 2>&1 ; then
        echo "  already running container ${container_name}"
    else
        local proxy_env_opt=
        if [ -z "$no_carry_on_proxy" ]; then
            proxy_env_opt='--env='"http_proxy=${http_proxy}"' --env='"https_proxy=${https_proxy}"' --env='"no_proxy=${no_proxy}"
        fi
        local docker_host_env_opt=
        if [ -z "${no_carry_on_docker_host}" ] ; then
            if [ -n "${DOCKER_HOST}" ] ; then
                docker_host_env_opt=' --env='"DOCKER_HOST=${DOCKER_HOST}"
            fi
        fi

        # docker run
        docker run --name ${container_name} -d \
            --restart=no \
            ${add_host_opt} \
            ${user_option} \
            ${memory_opt} \
            ${publish_port_opt} \
            ${proxy_env_opt} \
            ${docker_host_env_opt} \
            ${env_opts} \
            ${real_volume_opt} \
            $image \
            tail -f $(  f-msys-escape '/dev/null' )
        RC=$? ; if [ $RC -ne 0 ]; then echo "docker run error. abort." ; return $RC; fi

        # wait for container Running
        local count=0
        while true
        do
            sleep 2
            if docker ps --filter name=${container_name} --filter status=running | grep ${container_name} > /dev/null ; then
                echo "  container running found" > /dev/null
                break
            fi
            echo -n -e "\r  waiting for running container ... $count / $container_timeout seconds ..."
            sleep 3
            count=$( expr $count + 5 )
            if [ $count -gt ${container_timeout} ]; then
                echo "timeout for container Running. abort."
                return 1
            fi
        done
    fi

    # archive current directory
    local TMP_ARC_FILE=$( mktemp  "../${container_name}-XXXXXXXXXXXX.tar.gz" )
    local TMP_ARC_FILE_RECOVER=${TMP_ARC_FILE}-recover.sh
    local TMP_ARC_FILE_IN_CONTAINER=$( echo $TMP_ARC_FILE | sed -e 's%^\.\./%%g' )
    local TMP_DEST_FILE=${container_name}:${TMP_ARC_FILE}
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

            # docker cp
            echo "  docker cp into container ... docker cp  ${TMP_ARC_FILE}  ${TMP_DEST_MSYS2}"
            docker cp  ${TMP_ARC_FILE} ${TMP_DEST_MSYS2}
            RC=$? ; if [ $RC -ne 0 ]; then echo "docker cp error. abort." ; return $RC; fi

            # docker exec ... import and extract archive
            echo "  docker exec extract archive in container"
            if [ -f "$pseudo_volume_left" ]; then
                # ファイルの場合は特例。一度tmpで展開してからターゲットにmvする。
                docker exec ${container_name} bash -c " mkdir -p $( dirname $pseudo_volume_right )"
                docker exec ${container_name} bash -c " mkdir -p /tmp/docker-run-v-tmp"
                docker exec ${container_name} bash -c " tar xzf $TMP_ARC_FILE_IN_CONTAINER -C /tmp/docker-run-v-tmp"
                docker exec ${container_name} bash -c " alias mv=mv ; mv /tmp/docker-run-v-tmp/$( basename $pseudo_volume_left ) $pseudo_volume_right "
                docker exec ${container_name} bash -c " alias rm=rm ; rm -rf /tmp/docker-run-v-tmp"
            elif [ -d "$pseudo_volume_left" ]; then
                docker exec ${container_name} bash -c " mkdir -p $pseudo_volume_right "
                docker exec ${container_name} bash -c " tar xzf $TMP_ARC_FILE_IN_CONTAINER -C $pseudo_volume_right "
            fi
            docker exec ${container_name} bash -c " alias rm=rm ; rm $TMP_ARC_FILE_IN_CONTAINER "
        done
    fi

    if [ ! -z "$pseudo_workdir" ]; then
        # docker exec ... set workdir
        docker exec ${container_name} bash -c " mkdir -p /etc/profile.d "
        docker exec ${container_name} bash -c " echo cd $pseudo_workdir >> /etc/profile.d/workdir.sh "
        docker exec ${container_name} bash -c " mkdir -p $pseudo_workdir "
    fi

    if [ ! -z "$pseudo_profile" ]; then
        # docker exec ... set profile
        docker exec ${container_name} bash -c " mkdir -p /etc/profile.d "
        docker exec ${container_name} bash -c " echo source $pseudo_profile >> /etc/profile.d/workdir.sh "
    fi

    if [ ! -z "$pseudo_initfile" ]; then
        # docker exec ... set profile
        docker exec ${container_name} bash -c " mkdir -p /etc/profile.d "
        docker exec ${container_name} bash -c " echo source $pseudo_initfile >> /etc/profile.d/workdir.sh "
    fi

    # create recover shell , when terminal is suddenly gone.
    if [ ! -z "$pseudo_volume_bind" ]; then
        if [ ! -z "$volume_carry_out" ]; then
            echo "  create recover shell ${TMP_ARC_FILE_RECOVER}"
            echo "#!/bin/bash" >> ${TMP_ARC_FILE_RECOVER}
            echo "#" >> ${TMP_ARC_FILE_RECOVER}
            echo "# recover shell when terminal is abort, but container is running." >> ${TMP_ARC_FILE_RECOVER}
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

                # docker exec ... create archive and docker cp to export
                if [ -d "$pseudo_volume_left" ]; then
                    echo "docker exec ${container_name} bash -c \" ( cd $pseudo_volume_right && tar czf - . ) > $TMP_ARC_FILE_IN_CONTAINER \"" >> ${TMP_ARC_FILE_RECOVER}
                elif [ -f "$pseudo_volume_left" ]; then
                    echo "docker exec ${container_name} bash -c \" ( cd $( dirname $pseudo_volume_right ) && tar czf - $( basename $pseudo_volume_right ) ) > $TMP_ARC_FILE_IN_CONTAINER \"" >> ${TMP_ARC_FILE_RECOVER}
                else
                    echo "volume list $pseudo_volume_list is not a directory for file. aobrt."
                    return 1
                fi

                # docker cp get archive file
                echo "/bin/rm -f $TMP_ARC_FILE"  >> ${TMP_ARC_FILE_RECOVER}
                echo "mkdir -p $TMP_ARC_DIR"  >> ${TMP_ARC_FILE_RECOVER}
                echo "if docker cp   ${TMP_DEST_MSYS2}  ${TMP_ARC_DIR} ; then"  >> ${TMP_ARC_FILE_RECOVER}
                echo "    /bin/mv ${TMP_ARC_DIR_FILE} $TMP_ARC_FILE"  >> ${TMP_ARC_FILE_RECOVER}
                echo "    /bin/rmdir $TMP_ARC_DIR"  >> ${TMP_ARC_FILE_RECOVER}
                echo "elif docker cp   ${TMP_DEST_MSYS2}  ${TMP_ARC_FILE_CURRENT_DIR} ; then"  >> ${TMP_ARC_FILE_RECOVER}
                echo "    /bin/mv ${TMP_ARC_FILE_CURRENT_DIR} $TMP_ARC_FILE"  >> ${TMP_ARC_FILE_RECOVER}
                echo "    /bin/rmdir $TMP_ARC_DIR"  >> ${TMP_ARC_FILE_RECOVER}
                echo "else"  >> ${TMP_ARC_FILE_RECOVER}
                echo "    echo docker cp error."  >> ${TMP_ARC_FILE_RECOVER}
                echo "    exit 1"  >> ${TMP_ARC_FILE_RECOVER}
                echo "fi"  >> ${TMP_ARC_FILE_RECOVER}

                # if rsync is present, use rsync
                if [ x"$RSYNC_MODE"x = x"true"x ]; then
                    # extract archive file into temp directory
                    local TMP_EXT_DIR=$( mktemp -d ../${container_name}-tmp-XXXXXXXXXXXX )
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

                # delete container
                echo "if docker rm -f ${container_name}  ; then" >> ${TMP_ARC_FILE_RECOVER}
                echo "    echo container delete success." >> ${TMP_ARC_FILE_RECOVER}
                echo "else" >> ${TMP_ARC_FILE_RECOVER}
                echo "    echo container delete failure." >> ${TMP_ARC_FILE_RECOVER}
                echo "fi" >> ${TMP_ARC_FILE_RECOVER}
            done
        fi
    fi

    # exec into container
    if [ ! -z "$i_or_tty" ]; then
        # interactive mode
        echo "  base workdir name : $pseudo_workdir"
        echo "  interactive mode"
        echo "  ${WINPTY_CMD} docker exec ${interactive}  ${tty}  ${container_name}  bash --login"
        ${WINPTY_CMD} docker exec ${interactive}  ${tty}  ${container_name}  bash --login
    else
        echo "  base workdir name : $pseudo_workdir"
        echo "  running command : $command_line"
        echo "  ${WINPTY_CMD} docker exec                         ${container_name}  bash --login -c  $command_line"
        ${WINPTY_CMD} docker exec                         ${container_name}  bash --login -c  "$command_line"
    fi

    # after container exit
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

                # docker exec ... create archive and docker cp to export
                echo "  creating archive file in container : $TMP_ARC_FILE_IN_CONTAINER"
                if [ -d "$pseudo_volume_left" ]; then
                    docker exec ${container_name} bash -c " ( cd $pseudo_volume_right && tar czf - . ) > $TMP_ARC_FILE_IN_CONTAINER "
                    RC=$? ; if [ $RC -ne 0 ]; then echo "docker exec error. abort." ; return $RC; fi
                elif [ -f "$pseudo_volume_left" ]; then
                    docker exec ${container_name} bash -c " ( cd $( dirname $pseudo_volume_right ) && tar czf - $( basename $pseudo_volume_right ) ) > $TMP_ARC_FILE_IN_CONTAINER "
                    RC=$? ; if [ $RC -ne 0 ]; then echo "docker exec error. abort." ; return $RC; fi
                else
                    echo "volume list $pseudo_volume_list is not a directory for file. aobrt."
                    return 1
                fi

                # docker cp get archive file
                echo "  docker cp from container"
                /bin/rm -f $TMP_ARC_FILE
                mkdir -p $TMP_ARC_DIR
                # docker cp container から ローカルへ。
                # kubernetes 1.14.2 より前は、ローカル側はディレクトリしか指定できない
                # kubernetes 1.14.2 以降は、コピー元がファイルなら、ローカル側もファイルを指定しないといけない
                if echo "  trying file mode ..." ; docker cp   ${TMP_DEST_MSYS2}  ${TMP_ARC_FILE_CURRENT_DIR} ; then
                    echo "  file mode success."
                    /bin/mv ${TMP_ARC_FILE_CURRENT_DIR} $TMP_ARC_FILE
                    /bin/rmdir $TMP_ARC_DIR
                elif echo "  trying directory mode ..." ; docker cp   ${TMP_DEST_MSYS2}  ${TMP_ARC_DIR} ; then
                    echo "  directory mode success."
                    /bin/mv ${TMP_ARC_DIR_FILE} $TMP_ARC_FILE
                    /bin/rmdir $TMP_ARC_DIR
                else
                    echo "docker cp error. abort."
                    return 1
                fi

                # if rsync is present, use rsync
                if [ x"$RSYNC_MODE"x = x"true"x ]; then
                    # extract archive file into temp directory
                    local TMP_EXT_DIR=$( mktemp -d "../${container_name}-tmp-XXXXXXXXXXXX" )
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

    # delete container
    echo "  delete container ${container_name}"
    docker rm -f ${container_name}
    RC=$? ; if [ $RC -ne 0 ]; then echo "docker delete error. abort." ; return $RC; fi

    # delete recover shell
    echo "  delete recover shell ${TMP_ARC_FILE_RECOVER}"
    /bin/rm -f ${TMP_ARC_FILE_RECOVER}
}

# if source this file, define function only ( not run )
if [ ${#BASH_SOURCE[@]} = 1 ]; then
    f-docker-run-v "$@"
    RC=$?
    exit $RC
else
    echo "source from $0. define function only. not run." > /dev/null
fi

#
# end of file
#
