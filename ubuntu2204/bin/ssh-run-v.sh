#!/bin/bash
#
#  カレントディレクトリをtarでまとめてscpコピーしてからsshでログインする。
#  ログアウト時にはscpでコピーして手元に持ってくる。
#
#  接続先情報は、カレントディレクトリにssh-configファイルがあればそれを参照する
#  ssh-config が無い場合は、 ~/.ssh/config の中の Host から名前を一つ指定して使用する
#
#  ~/.ssh/config の記述例
# 
# Host *
#   ServerAliveInterval 30
#   ServerAliveCountMax 20
# 
# Host master1
#   HostName 127.0.0.1
#   User vagrant
#   Port 2200
#   UserKnownHostsFile /dev/null
#   StrictHostKeyChecking no
#   PasswordAuthentication no
#   IdentityFile C:/home/git/vagrant/02_centos7_kubernetes_with_kubeadm_1node/.vagrant/machines/master1/virtualbox/private_key
#   IdentitiesOnly yes
#   LogLevel FATAL
# 

# alias初期化
alias rm=rm
alias cp=cp
alias mv=mv
unalias rm
unalias cp
unalias mv

function f-ssh-run-v() {

    # rsyncコマンド存在チェック
    local HAS_RSYNC_CMD=true
    if type rsync 1>/dev/null 2>/dev/null ; then
        echo "  rsync found."
        HAS_RSYNC_CMD=true
    else
        echo "  rsync not found. using tar command."
        HAS_RSYNC_CMD=false
    fi

    local NO_CARRY_ON=
    local NO_CARRY_OUT=
    local SSH_CMD_HOST=
    local SSH_WITH_X=
    local SSH_WITH_Y=
    local ADD_RCFILE_LINE=
    # オプションチェック
    while [ $# -gt 0 ];
    do
        if [ x"$1"x = x"--help"x ]; then
            echo "ssh-run-v.sh  [options]  hostname"
            echo "    --help "
            echo "    --carry-on  (default) / --no-carry-on ... carry on current directory at ssh login"
            echo "    --carry-out (default) / --no-carry-out ... carry out files at ssh logout"
            echo "    --rsync (default) / --no-rsync ... use rsync command"
            echo "    -X ... same as ssh -X (enables X11 forwarding)"
            echo "    -Y ... same as ssh -Y (enables X11 forwarding)"
            echo "    --add-rcfile-line "'"export $(printf "%q" "VAR=VALUE")"'" ... append rcfile some command"
            return 0
        fi
        if [ x"$1"x = x"--no-carry"x ]; then
            NO_CARRY_ON=
            shift
            continue
        fi
        if [ x"$1"x = x"--no-carry-on"x ]; then
            NO_CARRY_ON=true
            shift
            continue
        fi
        if [ x"$1"x = x"--carry-out"x ]; then
            NO_CARRY_OUT=
            shift
            continue
        fi
        if [ x"$1"x = x"--no-carry-out"x ]; then
            NO_CARRY_OUT=true
            shift
            continue
        fi
        if [ x"$1"x = x"--rsync"x ]; then
            HAS_RSYNC_CMD=true
            shift
            continue
        fi
        if [ x"$1"x = x"--no-rsync"x ]; then
            HAS_RSYNC_CMD=false
            shift
            continue
        fi
        if [ x"$1"x = x"-X"x ]; then
            SSH_WITH_X=" -X "
            shift
            continue
        fi
        if [ x"$1"x = x"-Y"x ]; then
            SSH_WITH_Y=" -Y "
            shift
            continue
        fi
        if [ x"$1"x = x"--add-rcfile-line"x ]; then
            ADD_RCFILE_LINE="$2"
            shift
            shift
            continue
        fi
        if [ -z "$SSH_CMD_HOST" ]; then
            # 引数の先頭１個は、~/.ssh/config または ./ssh-config に記載されたホスト名と解釈する
            SSH_CMD_HOST=$1
            shift
            continue
        fi
        break
    done

    # オプション設定済みチェック
    if [ -z "$SSH_CMD_HOST" ]; then
        echo "ssh-run-v  needs hostname.  abort."
        return 1
    fi

    # カレントディレクトリに ssh-config があれば、それを使う
    SSH_CMD_CONFIG_OPT=""
    if [ -r ./ssh-config ]; then
        SSH_CMD_CONFIG_OPT=" -F ./ssh-config "
    fi

    SSH_CMD_COMMON_OPT=" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "
    YMD_HMS=$( date +%Y%m%d_%H%M%S )
    ARC_FILE_PATH=$( mktemp ../ssh-run-v-archive-$YMD_HMS-XXXXXXXXXXXX.tar.gz )
    ARC_FILE_NAME=$( basename $ARC_FILE_PATH )
    RC_FILE_PATH=$( echo $ARC_FILE_PATH | sed -e 's/.tar.gz/.sh/g' )
    RC_FILE_NAME=$( echo $ARC_FILE_NAME | sed -e 's/.tar.gz/.sh/g' )
    CURRENT_DIR_NAME=$( basename $PWD )

    # 動作ターゲットディレクトリ作成
    echo "  create target directory $CURRENT_DIR_NAME"
    ssh $SSH_CMD_CONFIG_OPT $SSH_CMD_COMMON_OPT $SSH_CMD_HOST -- mkdir -p $CURRENT_DIR_NAME
    RC=$? ; if [ $RC -ne 0 ]; then echo "error. abort." ; return 1; fi

    # ファイルの持ち込み実施
    if [ x"$NO_CARRY_ON"x = x""x ]; then

        echo "  creating archive file $ARC_FILE_NAME"
        tar czf  $ARC_FILE_PATH  .
        RC=$? ; if [ $RC -ne 0 ]; then echo "error. abort." ; return 1; fi

        echo "  sending archive file $ARC_FILE_NAME"
        scp $SSH_CMD_CONFIG_OPT $SSH_CMD_COMMON_OPT $ARC_FILE_PATH  $SSH_CMD_HOST:$ARC_FILE_NAME
        RC=$? ; if [ $RC -ne 0 ]; then echo "error. abort." ; return 1; fi

        echo "  recursive remove target directory $CURRENT_DIR_NAME"
        ssh $SSH_CMD_CONFIG_OPT $SSH_CMD_COMMON_OPT $SSH_CMD_HOST -- rm  -rf  $CURRENT_DIR_NAME
        RC=$? ; if [ $RC -ne 0 ]; then echo "error. abort." ; return 1; fi

        echo "  create target directory $CURRENT_DIR_NAME"
        ssh $SSH_CMD_CONFIG_OPT $SSH_CMD_COMMON_OPT $SSH_CMD_HOST -- mkdir -p $CURRENT_DIR_NAME
        RC=$? ; if [ $RC -ne 0 ]; then echo "error. abort." ; return 1; fi

        echo "  extracting archive file $ARC_FILE_NAME"
        ssh $SSH_CMD_CONFIG_OPT $SSH_CMD_COMMON_OPT $SSH_CMD_HOST -- tar xzf $ARC_FILE_NAME -C $CURRENT_DIR_NAME
        RC=$? ; if [ $RC -ne 0 ]; then echo "error. abort." ; return 1; fi

        ssh $SSH_CMD_CONFIG_OPT $SSH_CMD_COMMON_OPT $SSH_CMD_HOST -- rm  $ARC_FILE_NAME
        RC=$? ; if [ $RC -ne 0 ]; then echo "error. abort." ; return 1; fi
    fi

    # mktempでファイルを作っているのでここで削除
    rm $ARC_FILE_PATH

    echo "#!/bin/bash" > $RC_FILE_PATH
    echo 'source ~/.bashrc' >> $RC_FILE_PATH
    echo "cd $CURRENT_DIR_NAME" >> $RC_FILE_PATH
    echo "" >> $RC_FILE_PATH
    echo "$ADD_RCFILE_LINE" >> $RC_FILE_PATH
    echo "" >> $RC_FILE_PATH
    scp $SSH_CMD_CONFIG_OPT $SSH_CMD_COMMON_OPT $RC_FILE_PATH  $SSH_CMD_HOST:$RC_FILE_NAME
    RC=$? ; if [ $RC -ne 0 ]; then echo "error. abort." ; return 1; fi
    rm $RC_FILE_PATH

    if [ $# -gt 0 ] ; then
        # ssh でログイン (コマンドあり)
        echo "  ssh with command : $*"
        set -x
        ssh $SSH_CMD_CONFIG_OPT $SSH_CMD_COMMON_OPT -tt  $SSH_CMD_HOST -- "$@"
        set +x
    else
        # ssh でログイン (コマンドなし)
        ssh $SSH_WITH_X $SSH_WITH_Y $SSH_CMD_CONFIG_OPT $SSH_CMD_COMMON_OPT -tt  $SSH_CMD_HOST -- bash --rcfile $RC_FILE_NAME
    fi

    # ファイルの持ち出し実施
    if [ x"$NO_CARRY_OUT"x = x""x ]; then

        echo "  creating archive file $ARC_FILE_NAME"
        RECV_DIR_PATH=$( mktemp -d ../ssh-run-v-receive-$YMD_HMS-XXXXXXXXXXXX )
        ssh $SSH_CMD_CONFIG_OPT $SSH_CMD_COMMON_OPT $SSH_CMD_HOST  tar czf  $ARC_FILE_NAME  $CURRENT_DIR_NAME
        RC=$? ; if [ $RC -ne 0 ]; then echo "error. abort." ; return 1; fi

        scp $SSH_CMD_CONFIG_OPT $SSH_CMD_COMMON_OPT   $SSH_CMD_HOST:$ARC_FILE_NAME  $ARC_FILE_PATH
        RC=$? ; if [ $RC -ne 0 ]; then echo "error. abort." ; return 1; fi
        ssh $SSH_CMD_CONFIG_OPT $SSH_CMD_COMMON_OPT $SSH_CMD_HOST  rm  $ARC_FILE_NAME  $RC_FILE_NAME
        RC=$? ; if [ $RC -ne 0 ]; then echo "error. abort." ; return 1; fi


        if [ x"$HAS_RSYNC_CMD"x = x"true"x ]; then
            echo "  extracting archive file $ARC_FILE_NAME"
            tar xzf  $ARC_FILE_PATH  -C  $RECV_DIR_PATH
            RC=$? ; if [ $RC -ne 0 ]; then echo "error. abort." ; return 1; fi

            echo "  rsync files ..."
            rsync -rcv --delete  $RECV_DIR_PATH/$CURRENT_DIR_NAME/  ./
            RC=$? ; if [ $RC -ne 0 ]; then echo "error. abort." ; return 1; fi
        else
            echo "  tar overwrite ..."
            echo "  extracting archive file $ARC_FILE_NAME"
            tar xzf  $ARC_FILE_PATH  -C  ../
            RC=$? ; if [ $RC -ne 0 ]; then echo "error. abort." ; return 1; fi
        fi
        rm -rf $RECV_DIR_PATH  $ARC_FILE_PATH
    else
        ssh $SSH_CMD_CONFIG_OPT $SSH_CMD_COMMON_OPT $SSH_CMD_HOST  rm  $RC_FILE_NAME
        RC=$? ; if [ $RC -ne 0 ]; then echo "error. abort." ; return 1; fi
    fi
}


f-ssh-run-v "$@"

#
# end of file
#
