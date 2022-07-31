FROM ubuntu:22.04

ENV MYUBUNTUDOCKER_VERSION build-target-1
ENV MYUBUNTUDOCKER_VERSION ubuntu-2204
ENV MYUBUNTUDOCKER_VERSION latest
ENV MYUBUNTUDOCKER_IMAGE docker.io/georgesan/myubuntudocker

ENV DEBIAN_FRONTEND noninteractive

# Do not exclude man pages & other documentation
RUN rm /etc/dpkg/dpkg.cfg.d/excludes

# set locale
ENV LANG ja_JP.UTF-8
RUN apt update && \
    apt install -y \
    tzdata \
    locales && \
    locale-gen ja_JP.UTF-8 && \
    apt clean

# set timezone
ENV TZ Asia/Tokyo

# re-install packages with manual
# RUN dpkg -l | grep ^ii | cut -d' ' -f3 | xargs apt install -y --reinstall && apt clean
# install man pages
RUN apt install -y man-db  manpages && apt clean

# install etc utils
RUN apt update && apt install -y --fix-missing \
        bash-completion \
        connect-proxy \
        curl \
        dnsutils \
        emacs-nox \
        expect \
        gettext \
        git \
        gnupg2 \
        iproute2 \
        jq \
        lsof \
        netcat \
        net-tools \
        python3 python3-pip \
        rsync \
        sudo \
        tcpdump \
        traceroute \
        tree \
        unzip \
        vim \
        w3m \
        wget \
        zip \
    && apt clean all


#        ansible \
#        make \
#        postgresql-client \


# install docker client ( 2020.05.05 Release not found )
#RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - && \
#    add-apt-repository  "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" && \
#    apt-get update && \
#    apt-get install -y docker-ce-cli containerd.io && \
#    apt-get clean all

# install docker ce client
RUN apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release && \
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg && \
        echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null && \
        apt-get update --allow-releaseinfo-change && \
        apt-get install -y docker-ce-cli


# install docker-compose
RUN apt-get install -y docker-compose && apt-get clean

# install kubectl CLI
RUN curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - && \
    echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" >/etc/apt/sources.list.d/kubernetes.list && \
    apt-get update && \
    apt-get install -y kubectl && apt-get clean
# RUN apt-mark hold kubectl

# install helm CLI v2
#ENV HELM_CLIENT_VERSION v2.9.1
#RUN curl -fLO https://storage.googleapis.com/kubernetes-helm/helm-${HELM_CLIENT_VERSION}-linux-amd64.tar.gz && \
#    tar xzf  helm-${HELM_CLIENT_VERSION}-linux-amd64.tar.gz && \
#    /bin/cp  linux-amd64/helm   /usr/bin && \
#    /bin/rm -rf rm helm-${HELM_CLIENT_VERSION}-linux-amd64.tar.gz linux-amd64

# install helm CLI v3
# https://github.com/helm/helm/releases
ENV HELM3_VERSION v3.9.2
RUN \
    machine=$( uname -m ) && \
    if [ x"$machine"x = x"x86_64"x ] ; then arch=amd64 ; fi && \
    if [ x"$machine"x = x"aarch64"x ] ; then arch=arm64 ; fi && \
    curl -fLO https://get.helm.sh/helm-${HELM3_VERSION}-linux-${arch}.tar.gz && \
    tar xzf  helm-${HELM3_VERSION}-linux-${arch}.tar.gz && \
    /bin/cp  linux-${arch}/helm   /usr/bin && \
    /bin/rm -rf helm-${HELM3_VERSION}-linux-${arch}.tar.gz linux-${arch}

# install kompose v1.18.0
# https://github.com/kubernetes/kompose/releases
# ENV KOMPOSE_VERSION v1.26.1
# RUN curl -fLO https://github.com/kubernetes/kompose/releases/download/${KOMPOSE_VERSION}/kompose-linux-amd64.tar.gz && \
#     tar xzf kompose-linux-amd64.tar.gz && \
#     chmod +x kompose-linux-amd64 && \
#     mv kompose-linux-amd64 /usr/bin/kompose && \
#     rm kompose-linux-amd64.tar.gz

# install stern
# ENV STERN_VERSION 1.10.0
# RUN curl -fLO https://github.com/wercker/stern/releases/download/${STERN_VERSION}/stern_linux_amd64 && \
#     chmod +x stern_linux_amd64 && \
#     mv stern_linux_amd64 /usr/bin/stern

# install kustomize
# https://github.com/kubernetes-sigs/kustomize/releases
# ENV KUSTOMIZE_VERSION 4.5.5
# RUN curl -fLO https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz && \
#     tar xvzf kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz && \
#     chmod +x kustomize && \
#     mv kustomize /usr/bin/ && \
#     rm kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz

# install kubectx, kubens. see https://github.com/ahmetb/kubectx
RUN curl -fLO https://raw.githubusercontent.com/ahmetb/kubectx/master/kubectx && \
    curl -fLO https://raw.githubusercontent.com/ahmetb/kubectx/master/kubens && \
    chmod +x kubectx kubens && \
    mv kubectx kubens /usr/local/bin

# install yamlsort see https://github.com/george-pon/yamlsort/releases
ENV YAMLSORT_VERSION v0.1.20
RUN \
    machine=$( uname -m ) && \
    if [ x"$machine"x = x"x86_64"x ] ; then arch=amd64 ; fi && \
    if [ x"$machine"x = x"aarch64"x ] ; then arch=arm64 ; fi && \
    curl -fLO https://github.com/george-pon/yamlsort/releases/download/${YAMLSORT_VERSION}/linux_${arch}_yamlsort_${YAMLSORT_VERSION}.tar.gz && \
    tar xzf linux_${arch}_yamlsort_${YAMLSORT_VERSION}.tar.gz && \
    chmod +x linux_${arch}_yamlsort && \
    mv linux_${arch}_yamlsort /usr/bin/yamlsort && \
    rm linux_${arch}_yamlsort_${YAMLSORT_VERSION}.tar.gz



ADD docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ADD bashrc       /root/.bashrc
ADD inputrc      /root/.inputrc
ADD bash_profile /root/.bash_profile
ADD vimrc        /root/.vimrc
ADD emacsrc      /root/.emacs
ADD bin /usr/local/bin
RUN chmod +x /usr/local/bin/*.sh

ENV HOME /root
ENV ENV $HOME/.bashrc

# add sudo user
# https://qiita.com/iganari/items/1d590e358a029a1776d6 Dockerコンテナ内にsudoユーザを追加する - Qiita
# ユーザー名 ubuntu
# パスワード hogehoge
RUN groupadd -g 1000 ubuntu && \
    useradd  -g      ubuntu -G sudo -m -s /bin/bash ubuntu && \
    echo 'ubuntu:hogehoge' | chpasswd && \
    echo 'Defaults visiblepw'            >> /etc/sudoers && \
    echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# use normal user ubuntu
# USER ubuntu

CMD ["/usr/local/bin/docker-entrypoint.sh"]

