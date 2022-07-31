#!/bin/bash
#
# Docker Desktop for Windows で docker コンテナを起動する
#
# ホスト側のWindowsマシンに OpenSSH で接続可能な設定をしてあれば、
# DOCKER_HOST に ssh://username@host.docker.internal を設定することで
# 起動された側のコンテナの中から docker コマンドを使用可能になる
#
# Windows PC側にssh接続を許可している場合
# Windows PC側のsshに接続する場合は以下のようにIPアドレスを指定する
# exoprt   DEFAULT_IPV4_ADDR=192.168.1.35
# docker-desktop-run-v.sh
# 
# 起動したコンテナから
# proxy経由で外部のマシンにssh接続する場合の
# SSH 用のパラメータを設定する
# export    DEFAULT_IPV4_ADDR=
# export    DOCKER_SSH_HOST_TITLE=workvm
# export    DOCKER_SSH_HOST=workvm.azure.com
# export    DOCKER_SSH_USER=azureuser
# export    DOCKER_SSH_PORT=22
# export    DOCKER_SSH_KEYFILE=azure_key
# export    DOCKER_SSH_PROXY_SERV="proxy.example.com:1080"
# export    DOCKER_SSH_PROXY_AUTH="user:pass"
# docker-desktop-run-v.sh
# 

function f-docker-desktop-run-v() {

    # SSH 用のパラメータを設定する
    DOCKER_SSH_HOST_TITLE=${DOCKER_SSH_HOST_TITLE:-host}
    DOCKER_SSH_HOST=${DOCKER_SSH_HOST:-host.docker.internal}
    DOCKER_SSH_USER=${DOCKER_SSH_USER:-${USER}}
    DOCKER_SSH_PORT=${DOCKER_SSH_PORT:-22}
    DOCKER_SSH_KEYFILE=${DOCKER_SSH_KEYFILE:-id_rsa}

    # DOCKER_SSH_PROXY_SERV=proxy.com:1080
    # DOCKER_SSH_PROXY_AUTH=user:pass

    # DEFAULT_IPV4_ADDR には ホスト側Windows PCのIPv4アドレスを定義しておくと、接続先ホストとして--add-hostする。
    if [ -z "${DEFAULT_IPV4_ADDR}" ] ; then
        ADD_HOST_OPT=
    else
        ADD_HOST_OPT="  --add-host ${DOCKER_SSH_HOST}:${DEFAULT_IPV4_ADDR} "
    fi

    # 秘密鍵ファイルを現在のディレクトリに持ってくる
    if [ -f ~/.ssh/${DOCKER_SSH_KEYFILE} ] ; then
        cp ~/.ssh/${DOCKER_SSH_KEYFILE}  ${DOCKER_SSH_KEYFILE}
    fi

    # コンテナの中でsshの初期化ファイルを作成する
cat > init-ssh-config.sh << "SCRIPTEOF"
#!/bin/bash

# copy ~/.ssh/config
mkdir -p $HOME/.ssh

# proxyコマンドを生成
if [ -n "${DOCKER_SSH_PROXY_SERV}" -a -n "${DOCKER_SSH_PROXY_AUTH}" ] ; then
    DOCKER_SSH_PROXY_CMD=${DOCKER_SSH_PROXY_CMD:-"ProxyCommand /usr/bin/ncat --proxy ${DOCKER_SSH_PROXY_SERV} --proxy-auth ${DOCKER_SSH_PROXY_AUTH} --proxy-type socks5 %h %p"}
elif [ -n "${DOCKER_SSH_PROXY_SERV}" ] ; then
    DOCKER_SSH_PROXY_CMD=${DOCKER_SSH_PROXY_CMD:-"ProxyCommand /usr/bin/ncat --proxy ${DOCKER_SSH_PROXY_SERV} --proxy-type socks5 %h %p"}
fi

if [ ! -f $HOME/.ssh/config ] ; then
# ssh configファイルを作成する
cat > $HOME/.ssh/config << EOF
Host ${DOCKER_SSH_HOST_TITLE}
  HostName ${DOCKER_SSH_HOST}
  User ${DOCKER_SSH_USER}
  Port ${DOCKER_SSH_PORT}
  StrictHostKeyChecking no
  PasswordAuthentication no
  IdentityFile ${PWD}/${DOCKER_SSH_KEYFILE}
  IdentitiesOnly yes
  LogLevel FATAL
  ServerAliveInterval 30
  ServerAliveCountMax 60
  ForwardX11 yes
  ForwardX11Trusted yes
  XAuthLocation /usr/bin/xauth
  ${DOCKER_SSH_PROXY_CMD}
EOF
fi

# chmod 0600 id_rsa file
if [ -f ${DOCKER_SSH_KEYFILE} ] ; then
    chmod 0600 ${DOCKER_SSH_KEYFILE}
fi

SCRIPTEOF

    # 起動する
    bash  docker-run-v.sh \
        --no-docker-host  \
        --env  DOCKER_HOST=ssh://${DOCKER_SSH_HOST_TITLE}  \
        --env  DOCKER_SSH_HOST_TITLE=${DOCKER_SSH_HOST_TITLE}  \
        --env  DOCKER_SSH_HOST=${DOCKER_SSH_HOST}  \
        --env  DOCKER_SSH_USER=${DOCKER_SSH_USER}  \
        --env  DOCKER_SSH_PORT=${DOCKER_SSH_PORT}  \
        --env  DOCKER_SSH_KEYFILE=${DOCKER_SSH_KEYFILE}  \
        --env  DOCKER_SSH_PROXY_SERV="${DOCKER_SSH_PROXY_SERV}"  \
        --env  DOCKER_SSH_PROXY_AUTH="${DOCKER_SSH_PROXY_AUTH}"  \
        --source-initfile init-ssh-config.sh  \
        ${ADD_HOST_OPT}  \
        --docker-pull  \
        --image-centos  \
        "$@"

}

f-docker-desktop-run-v "$@"

