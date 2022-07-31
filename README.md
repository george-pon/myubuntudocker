# myubuntudocker

This image is my convinient environment on Ubuntu 22.04 Jammy Jellyfish
includes man pages, git, jq, ansible, bind-utils, kubectl CLI, docker CLI, helm, kustomize, envsubst, expect, gettext

## how to use

### run via Docker

```
function docker-run-myubuntudocker() {
    ${WINPTY_CMD} docker run -i -t --rm \
        -e http_proxy=${http_proxy} -e https_proxy=${https_proxy} -e no_proxy="${no_proxy}" \
        docker.io/georgesan/myubuntudocker:latest
}
docker-run-myubuntudocker
```

### run via Kubernetes

```
function kube-run-myubuntudocker() {
    local tmp_no_proxy=$( echo $no_proxy | sed -e 's/,/\,/g' )
    ${WINPTY_CMD} kubectl run myubuntudocker -i --tty \
        --image=docker.io/georgesan/myubuntudocker:latest --rm \
        --env="http_proxy=${http_proxy}" --env="https_proxy=${https_proxy}" --env="no_proxy=${tmp_no_proxy}"
}
kube-run-myubuntudocker
```

### run via Kubernetes with new service account

This pod runs with service account myubuntudocker that has ClusterRoleBindings cluster-admin.

```
function kube-run-myubuntudocker() {
    local namespace=
    local tmp_no_proxy=$( echo $no_proxy | sed -e 's/,/\,/g' )
    while [ $# -gt 0 ]
    do
        if [ x"$1"x = x"-n"x -o x"$1"x = x"--namespace"x ]; then
            namespace=$2
            shift
            shift
            continue
        fi
        shift
    done
    if [ -z "$namespace" ]; then
        namespace=default
    fi

    kubectl -n ${namespace} create serviceaccount myubuntudocker

    kubectl create clusterrolebinding myubuntudocker \
        --clusterrole cluster-admin \
        --serviceaccount=${namespace}:myubuntudocker

    ${WINPTY_CMD} kubectl run myubuntudocker -i --tty --image=docker.io/georgesan/myubuntudocker:latest --rm \
        --serviceaccount=myubuntudocker \
        --namespace=${namespace} \
        --env="http_proxy=${http_proxy}" --env="https_proxy=${https_proxy}" --env="no_proxy=${tmp_no_proxy}"
}

kube-run-myubuntudocker -n default
```


### run via kube-run-v.sh

* https://gitlab.com/george-pon/myubuntudocker/raw/master/ubuntu2204/bin/kube-run-v.sh

```
mkdir -p /home/george/podwork
cd /home/george/podwork
curl -LO https://gitlab.com/george-pon/myubuntudocker/raw/master/bin/kube-run-v.sh
bash kube-run-v.sh --image docker.io/georgesan/myubuntudocker:latest
```

### what is kube-run-v.sh ?

To carry on current directory files on a "working" pod, 
kube-run-v.sh creates a "working" pod, archive current directory, copy it into the pod (by kubectl cp), extract it in the pod , and exec -i -t the pod bash --login.

When you exit from the pod, To carry out current directory files from pod,
kube-run-v.sh creates archive file in the pod, copy it form the pod (by kubectl cp), extract it in current directory(over-write).

kube-run-v.sh can also use official docker image or your own docker image with option "--image centos:7" or "--image debian:9" .

```
curl -LO https://raw.githubusercontent.com/george-pon/mycentos7docker/master/bin/kube-run-v.sh
bash kube-run-v.sh --image debian:9
```

kube-run-v.sh requires bash --login, bash, tar command in the docker image.

SECURITY WARNING: kube-run-v.sh creates the serviceaccount and gives him cluster-admin role, 
then run a pod with the serviceacount.


### tips run kubectl in kubernetes pod

```
kubectl proxy &
kubectl get cluster-info
kubectl get pod,svc
```



### other tips winpty ( Git-Bash for Windows )(MSYS2)

the environment variable WINPTY_CMD is set by below.

```
# set WINPTY_CMD environment variable when it need.
function check_winpty() {
    if type tty.exe 1>/dev/null 2>/dev/null ; then
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
check_winpty

```

### how to build

```
bash build-image.sh
```

### local test memo via Docker

```
function docker-run-myubuntudocker() {
    ${WINPTY_CMD} docker run -i -t --rm \
        -e http_proxy=${http_proxy} -e https_proxy=${https_proxy} -e no_proxy="${no_proxy}" \
        myubuntudocker:latest
}
docker-run-myubuntudocker
```
