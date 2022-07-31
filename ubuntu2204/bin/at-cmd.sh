#!/bin/bash
#
#  指定時刻まで待ってコマンドラインのコマンドを実行する
#  使用例  at-cmd.sh  1830  ls -la
#
#  時刻の左に日付指定をつけても良い
#  使用例  at-cmd.sh  051830  ls -la
#
#  時刻は HHMM 形式 or DDHHMM で指定する
#

function f-at-cmd-usage() {
    echo "at-cmd.sh  time  command ..."
    echo "    example:  at-cmd.sh  1830   ls -laF    : match HHMM"
    echo "    example:  at-cmd.sh  011830   ls -laF  : match DDMMHH"
}

function f-at-cmd() {

    local curtime=
    local curtime2=
    local targettime=

    # 引数解析
    while [ $# -gt 0 ];
    do
        if [ x"$targettime"x = x""x ]; then
            targettime=$1
            shift
            continue
        fi

        break
    done

    # チェック
    if [ -z "$targettime" ]; then
        f-at-cmd-usage
        return 0
    fi

    # 時間待ち
    while true
    do
        curtime=$( date +%H%M )
        curtime2=$( date +%d%H%M )
        echo -n -e  "\rtarget time : $targettime    current time : $curtime or $curtime2    command: $@"
        if [ x"$curtime"x = x"$targettime"x ] ; then
            echo " ... found."
            break
        fi
        if [ x"$curtime2"x = x"$targettime"x ] ; then
            echo " ... found."
            break
        fi
        sleep 20
    done

    # コマンド実行
    "$@"
    RC=$?
    echo "at-cmd end at $(date) . exit code is $RC"
    return $RC
}

f-at-cmd  "$@"

#
# end of file
#
