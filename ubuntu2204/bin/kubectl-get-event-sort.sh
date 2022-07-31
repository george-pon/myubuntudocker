#!/bin/bash
#
# kubectl CLIでのKubernetesのイベント監視 - Qiita
# https://qiita.com/sotoiwa/items/ae371e615d2738fdc8a8
#

set -eu
set -o pipefail

# jqが無い場合は代替の簡略コマンドを実行
if ! type jq 1>/dev/null 2>/dev/null ; then
    kubectl get event --all-namespaces -o=jsonpath='{range .items[*]}{.lastTimestamp} {.involveObject.name} {.message}{"\n"}{end}' | sort
    RC=$?
    exit $RC
fi

# kubectl get nodeを実行して結果を変数に格納
# "jq -c"は結果を改行等で整形せずコンパクトにするオプション
json=$(kubectl get event --all-namespaces -o json | jq -c .)

# 結果を時刻でソートしてから、
# Warningでフィルタリングし、
# 300秒以内であるかでフィルタリング
warnings=$(echo ${json} | jq -c '.items
  | sort_by( .lastTimestamp )
  | .[]'
)

# 結果を整形
# <時刻> <Namespace名> <イベント名> <メッセージ>
# "jq -r"は出力をクオートしないオプション
results=$(echo ${warnings} | jq -r '.lastTimestamp + " "
                                      + .involvedObject.namespace + " "
                                      + .involvedObject.name + " "
                                      + .message')

# results が空文字の場合は正常
if [ -z "${results}" ]; then
  echo "eventはありません。"
else
  IFS=$'\n'
  for result in "${results}"; do
    echo "${result}"
  done
  unset IFS
  exit 1
fi

