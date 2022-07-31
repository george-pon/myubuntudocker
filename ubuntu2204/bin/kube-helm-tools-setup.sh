#!/bin/bash
#
#  色々なツールを helm でガンガンインストールしていく元ネタ
#
#  このシェルで直接インストールするわけではない
#
#
# http://master.default.svc.k8s.local/
# http://kubernetes-dashboard.minikube.local/
# http://grafana.minikube.local/                admin  prom-operator
# http://kjwikigdocker.minikube.local/kjwikigdocker/
# http://growi.minikube.local/
#

#
# download kube-run-v.sh
#
function f-download-kube-run-v-sh() {
    if [ -d /usr/local/bin ]; then
      pushd /usr/local/bin
      for i in kube-run-v.sh  ssh-run-v.sh  kube-all.sh  kube-all-check.sh  docker-clean.sh  download-my-shells.sh  kube-helm-client-init.sh  kube-helm-tools-setup.sh  docker-run-ctop.sh curl-no-proxy.sh  kube-flannel-reset.sh download-my-shells.sh
      do
        curl -LO https://raw.githubusercontent.com/george-pon/mycentos7docker/master/bin/$i
        chmod +x $i
      done
      popd
    fi
}



# yamlsortコマンドをダウンロードする
function f-download-yamlsort-command() {

    export YAMLSORT_VERSION=v0.1.19

    # download yamlsort command
    local UNAMEO=$( uname -o )
    case $UNAMEO in
    GNU/Linux)
        if [ -r yamlsort ]; then
            return 0
        fi
        curl -fLO https://github.com/george-pon/yamlsort/releases/download/${YAMLSORT_VERSION}/linux_amd64_yamlsort_${YAMLSORT_VERSION}.tar.gz
        tar xvzf linux_amd64_yamlsort_${YAMLSORT_VERSION}.tar.gz
        mv linux_amd64_yamlsort yamlsort
        chmod +x yamlsort
        rm linux_amd64_yamlsort_${YAMLSORT_VERSION}.tar.gz
        ;;
    Msys)
        if [ -r yamlsort.exe ]; then
            return 0
        fi
        curl -fLO https://github.com/george-pon/yamlsort/releases/download/${YAMLSORT_VERSION}/windows_amd64_yamlsort_${YAMLSORT_VERSION}.tar.gz
        tar xvzf windows_amd64_yamlsort_${YAMLSORT_VERSION}.tar.gz
        mv windows_amd64_yamlsort.exe yamlsort.exe
        rm windows_amd64_yamlsort_${YAMLSORT_VERSION}.tar.gz
        ;;
    FreeBSD)
        if [ -r yamlsort ]; then
            return 0
        fi
        curl -fLO https://github.com/george-pon/yamlsort/releases/download/${YAMLSORT_VERSION}/freebsd_amd64_yamlsort_${YAMLSORT_VERSION}.tar.gz
        tar xvzf freebsd_amd64_yamlsort_${YAMLSORT_VERSION}.tar.gz
        mv freebsd_amd64_yamlsort yamlsort
        chmod +x yamlsort
        rm freebsd_amd64_yamlsort_${YAMLSORT_VERSION}.tar.gz
        ;;
    *)
        echo "unsupported"
        return 1
        ;;
    esac
}



# PATHに追加する。
# 既にある場合は何もしない。
function f-path-add() {
    local addpath=$1
    if [ -z "$addpath" ]; then
        echo "f-path-add  path"
        return 0
    fi
    if [ ! -d "$addpath" ]; then
        echo "not a directory : $addpath"
        return 1
    fi
    local result=$( echo "$PATH" | sed -e 's/:/\n/g' | awk -v va=$addpath '{ if ( $0 == va ) { print $0 } }' )
    if [ -z "$result" ]; then
        export PATH="$PATH:$addpath"
        echo "PATH add $addpath"
    fi
}


# helm server (tiller) をインストールする kube 1.15まで
function f-helm-install-tiller-server-kube1-15() {
    # helmのインストール
    if ! type helm ; then
        echo "install helm client (linux)"
        export HELM_VERSION=v2.14.3
        cd /tmp
        curl -LO https://storage.googleapis.com/kubernetes-helm/helm-${HELM_VERSION}-linux-amd64.tar.gz
        tar xzf  helm-${HELM_VERSION}-linux-amd64.tar.gz
        /bin/cp  linux-amd64/helm  linux-amd64/tiller  /usr/bin
        /bin/rm  -rf  linux-amd64
    fi

    echo "helm tiller 実行のためのサービスアカウント設定 node1でのみ実施"
    kubectl -n kube-system create serviceaccount tiller

    kubectl create clusterrolebinding tiller \
      --clusterrole cluster-admin \
      --serviceaccount=kube-system:tiller

    helm init --service-account tiller

    # wait for helm deploy
    kubectl -n kube-system  rollout status deploy/tiller-deploy

    echo "helm起動待ち"
    while true
    do
        helm version
        RC=$?
        if [ $RC -eq 0 ]; then
            break
        fi
    done
}




# helm server (tiller) をインストールする kube 1.16以降
function f-helm-install-tiller-server() {
    # helmのインストール
    if ! type helm ; then
        echo "install helm client (linux)"
        export HELM_VERSION=v2.14.3
        cd /tmp
        curl -LO https://storage.googleapis.com/kubernetes-helm/helm-${HELM_VERSION}-linux-amd64.tar.gz
        tar xzf  helm-${HELM_VERSION}-linux-amd64.tar.gz
        /bin/cp  linux-amd64/helm  linux-amd64/tiller  /usr/bin
        /bin/rm  -rf  linux-amd64
    fi

    echo "helm tiller 実行のためのサービスアカウント設定 node1でのみ実施"
    kubectl -n kube-system create serviceaccount tiller

    kubectl create clusterrolebinding tiller \
      --clusterrole cluster-admin \
      --serviceaccount=kube-system:tiller

    # apps/v1 ではないのでエラーになる
    # helm init --service-account tiller

kubectl apply -f - << "EOF"

---
apiVersion: apps/v1
kind: Deployment
metadata:
  creationTimestamp: null
  labels:
    app: helm
    name: tiller
  name: tiller-deploy
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: helm
      name: tiller
  strategy: {}
  template:
    metadata:
      creationTimestamp: null
      labels:
        app: helm
        name: tiller
        app.kubernetes.io/name: tiller
    spec:
      automountServiceAccountToken: true
      containers:
      - env:
        - name: TILLER_NAMESPACE
          value: kube-system
        - name: TILLER_HISTORY_MAX
          value: "0"
        image: gcr.io/kubernetes-helm/tiller:v2.14.3
        imagePullPolicy: IfNotPresent
        livenessProbe:
          httpGet:
            path: /liveness
            port: 44135
          initialDelaySeconds: 1
          timeoutSeconds: 1
        name: tiller
        ports:
        - containerPort: 44134
          name: tiller
        - containerPort: 44135
          name: http
        readinessProbe:
          httpGet:
            path: /readiness
            port: 44135
          initialDelaySeconds: 1
          timeoutSeconds: 1
        resources: {}
      serviceAccountName: tiller
status: {}

---
apiVersion: v1
kind: Service
metadata:
  creationTimestamp: null
  labels:
    app: helm
    name: tiller
  name: tiller-deploy
  namespace: kube-system
spec:
  ports:
  - name: tiller
    port: 44134
    targetPort: tiller
  selector:
    app: helm
    name: tiller
  type: ClusterIP
status:
  loadBalancer: {}

EOF
    
    # wait for helm deploy
    kubectl -n kube-system  rollout status deploy/tiller-deploy

    echo "helm起動待ち"
    while true
    do
        helm version
        RC=$?
        if [ $RC -eq 0 ]; then
            break
        fi
    done
}




#
# ingress
#
function f-helm-install-ingress() {
curl -LO https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/mandatory.yaml
curl -LO https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/provider/cloud-generic.yaml
curl -LO https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/provider/baremetal/service-nodeport.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/mandatory.yaml
# kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/provider/cloud-generic.yaml
# kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/provider/baremetal/service-nodeport.yaml

# nodeport版だとポート番号30000になってしまうな。80とか443が使えない。
if false; then
cat > service-nodeport-my.yaml << "EOF"
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx
  namespace: ingress-nginx
  labels:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/part-of: ingress-nginx
spec:
  type: NodePort
  ports:
    - name: http
      port: 80
      targetPort: 80
      nodePort: 30000
      protocol: TCP
    - name: https
      port: 443
      targetPort: 443
      nodePort: 30443
      protocol: TCP
  selector:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/part-of: ingress-nginx
EOF
kubectl apply -f service-nodeport-my.yaml
# kubectl delete -f service-nodeport-my.yaml
fi

#
# type loadbalancer, externalIPsを使うのが良い模様。nodeが複数ある場合はexternalIPsを複数指定しておく
# externalTrafficPolicy: Localの場合、着信したnodeの内部にあるpodにしか転送しない変なingressになる。
# 1 node = 1 ingressで、通信相手が daemonset なら externalTrafficPolicy: Local でも良いけど
# https://thinkit.co.jp/article/13738?page=0%2C1 KubernetesのDiscovery＆LBリソース（その1） | Think IT（シンクイット）
# また、master node は通常 worker pod は起動できないので、node1, node2 の IPアドレスを書くのが良い
#
cat > cloud-generic-my.yaml << "EOF"
kind: Service
apiVersion: v1
metadata:
  name: ingress-nginx
  namespace: ingress-nginx
  labels:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/part-of: ingress-nginx
spec:
  externalTrafficPolicy: Cluster
  type: LoadBalancer
  externalIPs:
    - 192.168.33.11
  selector:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/part-of: ingress-nginx
  ports:
    - name: http
      port: 80
      targetPort: http
    - name: https
      port: 443
      targetPort: https
EOF
kubectl apply -f cloud-generic-my.yaml
# kubectl delete -f cloud-generic-my.yaml
}






# うーん。色々前後にやってやると、動作した。 in kubernetes 1.15。
# うーん。うごかない；； kubectl top pod が動かない...。 kubectl top node は動くみたいだけど...。 in k3s 0.80.0 (k8s 1.14相当)
function f-helm-install-heapster-1.0.1() {
#
#  heapster-1.0.1
#
#  --namespace kube-system にしないといけない
#  認証なしで接続できる kubelet port 10255 がkube 1.13系で廃止されたので、heapster対応待ち。 2019.08.16
#

  # 削除
  helm delete --purge heapster
  echo -n "sleeping 15 seconds..."
  sleep 15
  echo ""

  # inspect
  helm inspect stable/heapster \
      --version 1.0.1

# アクセス用のロールを作成
kubectl apply -f - << "EOF"
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: node-stats-full
rules:
- apiGroups: [""]
  resources: ["nodes/stats"]
  verbs: ["get", "watch", "list", "create"]
EOF

# kubeletアクセス用のheapsterにRoleをBindする。
kubectl apply -f - << "EOF"
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: heapster-node-stats
subjects:
- kind: ServiceAccount
  name: heapster
  namespace: kube-system
roleRef:
  kind: ClusterRole
  name: node-stats-full
  apiGroup: rbac.authorization.k8s.io
EOF

# Pod調査用のRoleを作る
kubectl apply -f - << "EOF"
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: heapster-custom-fix
rules:
- apiGroups:
  - ""
  resources:
  - pods
  - nodes
  - namespaces
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - extensions
  resources:
  - deployments
  verbs:
  - get
  - list
  - update
  - watch
- apiGroups:
  - ""
  resources:
  - nodes/stats
  verbs:
  - get
EOF

# kubeletアクセス用のheapsterにRoleをBindする。
kubectl apply -f - << "EOF"
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: heapster-custom-fix
subjects:
- kind: ServiceAccount
  name: heapster
  namespace: kube-system
roleRef:
  kind: ClusterRole
  name: heapster-custom-fix
  apiGroup: rbac.authorization.k8s.io
EOF

  # heapsterのインストール
  helm install stable/heapster \
      --name heapster \
      --namespace kube-system  \
      --version 1.0.1 \
      --values - << "EOF"
command:
- /heapster
- --source=kubernetes:kubernetes:https://kubernetes.default?useServiceAccount=true&kubeletHttps=true&kubeletPort=10250&insecure=true
rbac:
  create: true
  serviceAccountName: heapster
service:
  annotations:
    prometheus.io/path: /metrics
    prometheus.io/port: "8082"
    prometheus.io/scrape: "true"
EOF

  echo "# 情報が集まるまで120秒以上待機してから実行すること"
  echo "kubectl top node"
  echo "kubectl top pod --all-namespaces"

  # ログ監視
  # stern -n kube-system heapster
}
# f-helm-install-heapster-1.0.1




# kubernetes 1.15 では動作しない。rbacの制約が厳しくなった模様。
function f-helm-install-heapster-0.3.3() {
if true; then
#
#  heapster
#  heapster-0.3.2
#
# --namespace kube-system にしないといけない
#
#  認証なしで接続できる kubelet port 10255 がkube 1.13系で廃止されたので、heapster対応待ち。 2019.03.24
#  今後はサービスアカウントを使うようにして、認証ありでkubelet port 10250に接続して情報を取得するようになる
#  amazon 向け kubernetes では、readonly port 10255は廃止されているので、kubectl top nodeは heapsterが対応するまで利用できない
#  https://github.com/awslabs/amazon-eks-ami/issues/128
#

# アクセス用のロールを作成
kubectl apply -f - << "EOF"
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: node-stats-full
rules:
- apiGroups: [""]
  resources: ["nodes/stats"]
  verbs: ["get", "watch", "list", "create"]
EOF

# kubeletアクセス用のアカウントheapster-heapsterにRoleをBindする。
kubectl apply -f - << "EOF"
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: heapster-node-stats
subjects:
- kind: ServiceAccount
  name: heapster-heapster
  namespace: kube-system
roleRef:
  kind: ClusterRole
  name: node-stats-full
  apiGroup: rbac.authorization.k8s.io
EOF

# 削除
helm delete --purge heapster
sleep 15

# inspect
helm inspect stable/heapster \
    --version 0.3.3

# heapsterのインストール
helm install stable/heapster \
    --name heapster \
    --namespace kube-system  \
    --version 0.3.3 \
    --values - << "EOF"
command:
- /heapster
- --source=kubernetes:kubernetes:https://kubernetes.default?useServiceAccount=true&kubeletHttps=true&kubeletPort=10250&insecure=true
rbac:
  create: true
  serviceAccountName: heapster
service:
  annotations:
    prometheus.io/path: /metrics
    prometheus.io/port: "8082"
    prometheus.io/scrape: "true"
EOF

echo "# 情報が集まるまで300秒以上待機してから実行すること"
echo "kubectl top node"
echo "kubectl top pod --all-namespaces"

  # ログ監視
  # stern -n kube-system heapster

fi
}
# f-helm-install-heapster-0.3.3






#
#  nginx sample
#
function f-nginx-sample() {
# ベースとなるdocker-composeファイルを用意
export NGINX_NAME=sample-nginx
helm delete --purge $NGINX_NAME
cat > ${NGINX_NAME}.yml << EOF
#
# docker-compose file for ${NGINX_NAME}
#
version: '3'
services:
  ${NGINX_NAME}:
    image: "nginx:latest"
    ports:
     - "80:80"
EOF
kompose convert --chart --controller deployment --file ${NGINX_NAME}.yml
helm install $NGINX_NAME --name $NGINX_NAME
kubectl rollout status deploy/$NGINX_NAME
}





#
# cert-manager
#
# see https://hub.helm.sh/charts/jetstack/cert-manager
# see https://docs.cert-manager.io/en/latest/tasks/issuers/index.html
# see https://docs.cert-manager.io/en/latest/tutorials/acme/quick-start/index.html ( ACME型 Let's Encrypt を使う場合のチュートリアル )
#
# なんか設定が複雑だな・・・。
#
f-helm-cert-manager-0-9-1-self-sign() {

    # before install , you must apply CRDS
    kubectl apply -f https://raw.githubusercontent.com/jetstack/cert-manager/release-0.9/deploy/manifests/00-crds.yaml

    # Create the namespace for cert-manager
    kubectl create namespace cert-manager
    
    # Label the cert-manager namespace to disable resource validation
    kubectl label namespace cert-manager certmanager.k8s.io/disable-validation=true

    # Add the Jetstack Helm repository
    helm repo add jetstack https://charts.jetstack.io

    #  Updating the repo just incase it already existed
    helm repo update

    # Install the cert-manager helm chart
    helm install --name cert-manager --namespace cert-manager jetstack/cert-manager --version v0.9.1

    # wait for deploy
    kubectl rollout status --namespace cert-manager deploy/cert-manager
    kubectl rollout status --namespace cert-manager deploy/cert-manager-webhook


# Setting up self signing Issuers 自己署名タイプ
kubectl apply -f - << "EOF"
apiVersion: certmanager.k8s.io/v1alpha1
kind: ClusterIssuer
metadata:
  name: selfsigning-issuer
spec:
  selfSigned: {}
EOF


kubectl apply -f - << "EOF"
apiVersion: certmanager.k8s.io/v1alpha1
kind: Certificate
metadata:
  name: example-crt
spec:
  secretName: my-selfsigned-cert
  commonName: "my-selfsigned-root-ca"
  isCA: true
  issuerRef:
    name: selfsigning-issuer
    kind: ClusterIssuer
EOF

# 上の操作で、namespace default に secrets/my-selfsigned-cert  が生成される。
# ingressのtlsのsecretNameに指定すれば、httpsアクセスできる。 nginx に限るけど。traefikだとうまくいかない模様。

}




#
#  httpd サンプル
#
function f-httpd-sample() {
    helm repo add kjwikigdockerrepo  https://raw.githubusercontent.com/george-pon/kjwikigdocker/master/helm-chart/charts
    helm repo update
    helm delete --purge myhttpd2
    sleep 15
    helm install myhttpd2 --name myhttpd2 --values - << "EOF"
ingress:
  enabled: true
  hosts:
  - host: myhttpd2.minikube.local
    paths: [ "/" ]
EOF
    kubectl rollout status deploy/myhttpd2
}




#
# kjwikigdocker (emptyDir)
#
function f-helm-install-kjwikigdocker-emptydir() {
if true; then
    helm repo add kjwikigdockerrepo  https://raw.githubusercontent.com/george-pon/kjwikigdocker/master/helm-chart/charts
    helm repo update
    helm search kjwikigdocker
    helm inspect kjwikigdockerrepo/kjwikigdocker
    helm delete --purge kjwikigdocker
    sleep 15
    helm install kjwikigdockerrepo/kjwikigdocker \
        --name kjwikigdocker \
        --set ingress.hosts="{kjwikigdocker.minikube.local}"
    kubectl rollout status deploy/kjwikigdocker
    # テストアクセス
    # curl -v -k -H "Host: kjwikigdocker.minikube.local" http://192.168.33.10/kjwikigdocker/
    # curl -v -k -H "Host: kjwikigdocker.minikube.local" http://192.168.72.10/kjwikigdocker/
fi
}
# f-helm-install-kjwikigdocker-emptydir




#
# kjwikigdocker (emptyDir)(cert-manager self-signed https)
#
function f-helm-install-kjwikigdocker-emptydir-https() {
if true; then
    helm repo add kjwikigdockerrepo  https://raw.githubusercontent.com/george-pon/kjwikigdocker/master/helm-chart/charts
    helm repo update
    helm search kjwikigdocker
    helm inspect kjwikigdockerrepo/kjwikigdocker
    helm delete --purge kjwikigdocker
    sleep 15
    helm install kjwikigdockerrepo/kjwikigdocker \
        --name kjwikigdocker \
        --values - << "EOF"
ingress:
  enabled: true
  annotations:
    # kubernetes.io/ingress.class: nginx
    # kubernetes.io/tls-acme: "true"
    # for accept large file post
    # see https://github.com/kubernetes/ingress-nginx
    # see https://github.com/kubernetes/ingress-nginx/blob/master/docs/user-guide/annotations.md
    nginx.ingress.kubernetes.io/proxy-body-size: 1560m

  path: /kjwikigdocker/
  hosts:
    - kjwikigdocker.minikube.local
  tls:
  - secretName: my-selfsigned-cert
    hosts:
    - kjwikigdocker.minikube.local
EOF
    kubectl rollout status deploy/kjwikigdocker

    # テストアクセス
    # curl -v -k -H "Host: kjwikigdocker.minikube.local" https://192.168.33.10/kjwikigdocker/
    # curl -v -k -H "Host: kjwikigdocker.minikube.local" https://192.168.72.10/kjwikigdocker/
fi
}



#
# kjwikigdocker (PVC)
#
function f-helm-install-kjwikigdocker-pvc() {
if true; then
    helm repo add kjwikigdockerrepo  https://raw.githubusercontent.com/george-pon/kjwikigdocker/master/helm-chart/charts
    helm repo update
    helm search kjwikigdocker
    helm inspect kjwikigdockerrepo/kjwikigdocker
    helm delete --purge kjwikigdocker
    sleep 15
    helm install kjwikigdockerrepo/kjwikigdocker \
        --name kjwikigdocker \
        --set ingress.hosts="{kjwikigdocker.minikube.local}" \
        --set persistence.enabled="true"
    kubectl rollout status deploy/kjwikigdocker
fi
}
# f-helm-install-kjwikigdocker-pvc





#
# kjwikigdocker (hostpath /var/lib/kjwikigdocker)
#
function f-helm-install-kjwikigdocker-hostpath() {
if true; then
    helm repo add kjwikigdockerrepo  https://raw.githubusercontent.com/george-pon/kjwikigdocker/master/helm-chart/charts
    helm repo update
    helm search kjwikigdocker
    helm inspect kjwikigdockerrepo/kjwikigdocker
    helm delete --purge kjwikigdocker
    sleep 15
kubectl apply -f - << "EOF"
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-kjwikigdocker
  labels:
    type: local
spec:
  storageClassName: manual
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: "/var/lib/kjwikigdocker"
EOF
kubectl apply -f - << "EOF"
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: claim-kjwikigdocker
  # if you want dynamic persistent volume , un-comment below
  # annotations:
  #  volume.beta.kubernetes.io/storage-class: "standard"
spec:
  # if you want to use persistent volume created manually, uncomment below line.
  storageClassName: manual
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF
    helm install kjwikigdockerrepo/kjwikigdocker \
        --name kjwikigdocker \
        --set ingress.hosts="{kjwikigdocker.minikube.local}" \
        --set persistence.enabled="true" \
        --set persistence.existingClaim="claim-kjwikigdocker"
    kubectl rollout status deploy/kjwikigdocker
fi
}



#
# mydockerdind
#
function f-helm-install-mydockerdind() {
if true; then
    helm repo add myhelmchartrepo  https://gitlab.com/george-pon/my-helm-chart/raw/master/helm-chart/charts
    helm repo update
    helm search mydockerdind
    helm inspect myhelmchartrepo/mydockerdind
    helm delete --purge mydockerdind
    sleep 15
    helm install myhelmchartrepo/mydockerdind \
        --name mydockerdind \
        --set persistence.enabled="false"
    kubectl rollout status deploy/mydockerdind
    echo "# my docker dind 使用例"
    echo "export DOCKER_HOST=tcp://mydockerdind:2375"
    echo "docker version"
    echo "docker build"
    echo ""
fi
}
# f-helm-install-mydockerdind




#
# growi
#
function f-helm-install-growi() {
if true; then
    helm repo add  growirepo  https://raw.githubusercontent.com/george-pon/growi-helm-chart/master/helm-chart/charts
    helm repo update
    helm search growi
    helm inspect growirepo/growi
    helm delete growi --purge
    sleep 15
helm install growirepo/growi \
    --name growi  \
    --values - << "EOF"
    settings:
      appsiteurl: http://growi.minikube.local
    ingress:
      enabled: true
      hosts:
        - growi.minikube.local
      paths:
        - /
EOF
    kubectl rollout status deploy/growi
fi
}



#
#  kubernetes dashboard
#  kubernetes-dashboard-1.2.2
#
# helm inspect stable/kubernetes-dashboard
#
function f-helm-install-kubernetes-dashboard() {
helm install stable/kubernetes-dashboard \
    --name kubernetes-dashboard \
    --namespace kube-system \
    --values - << "EOF"
enableSkipLogin: true
enableInsecureLogin: true
rbac:
  clusterAdminRole: true
ingress:
  enabled: true
  hosts:
  - kubernetes-dashboard.minikube.local
EOF
kubectl --namespace kube-system rollout status deploy/kubernetes-dashboard
}



#
#  prometheus-operator
#
function f-helm-install-prometheus-operator() {
if true ; then
#
#  prometheus-operator
#  prometheus-operator-5.0.2
#  prometheus-operatorがあれば、prometheus不要かも
#  prometheusがインストール済みだと "prometheusrules.monitoring.coreos.com" が重複してインストールできない
#  prometheus-operatorを一回インストールしてしまうと、helm delete しても "prometheusrules.monitoring.coreos.com" が重複してインストールできない
#  kubectl get crd して、表示された prometheus 関連の crd を削除する必要がある
#
#  aksでkubeletのreadOnlyPort 10255が封鎖された。kubeletの認証付き 10250にアクセスして情報を取得する必要がある。
#    --set kubelet.serviceMonitor.https=true にする必要がある。
#  https://github.com/awslabs/amazon-eks-ami/issues/128
#
# prometheus-operator-5.7.0
#
helm inspect stable/prometheus-operator  --version 5.7.0

# kubectl apply -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/example/prometheus-operator-crd/alertmanager.crd.yaml
# kubectl apply -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/example/prometheus-operator-crd/prometheus.crd.yaml
# kubectl apply -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/example/prometheus-operator-crd/prometheusrule.crd.yaml
# kubectl apply -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/example/prometheus-operator-crd/servicemonitor.crd.yaml

helm install stable/prometheus-operator --version 5.7.0 \
    --name prometheus-operator \
    --namespace kube-system \
    --values - << "EOF"
grafana:
  enabled: true
  ingress:
    enabled: true
    hosts:
    - grafana.minikube.local
EOF

echo ""
echo "  access  http://grafana.minikube.local/"
echo "    username : admin"
echo "    password : prom-operator"
echo ""

fi

}


function f-helm-delete-prometheus-operator() {
if true ; then

helm delete --purge prometheus-operator

kubectl delete crd prometheuses.monitoring.coreos.com
kubectl delete crd prometheusrules.monitoring.coreos.com
kubectl delete crd servicemonitors.monitoring.coreos.com
kubectl delete crd alertmanagers.monitoring.coreos.com

# kubectl delete crd alertmanagers.myprometheus.monitoring.coreos.com
# kubectl delete crd prometheuses.myprometheus.monitoring.coreos.com
# kubectl delete crd prometheusrules.myprometheus.monitoring.coreos.com
# kubectl delete crd servicemonitors.myprometheus.monitoring.coreos.com

fi
}



