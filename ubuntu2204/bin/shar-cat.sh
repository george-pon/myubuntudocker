#!/bin/bash
#
#  コピーペーストしやすい形にテキストファイルを標準出力に出力する
#
#  2019.10.21 バイナリ転送モードも追加
#  2022.05.02 exclude オプション追加
#


#
# ファイルがテキストかどうか判定する。 0 ならテキスト。
#
function f_is_text_file() {
    local file=$1
    local fileType=$( file -i -b $file )
    local bText=false
    if echo $fileType | grep text/plain > /dev/null ; then
        return 0
    elif echo $fileType | grep text/x-shellscript > /dev/null ; then
        return 0
    elif echo $fileType | grep text/html > /dev/null ; then
        return 0
    elif echo $fileType | grep "text/xml" > /dev/null ; then
        return 0
    elif echo $fileType | grep "application/json" > /dev/null ; then
        return 0
    elif echo $fileType | grep "text/x-lisp" > /dev/null ; then
        return 0
    fi
    return 1
}

#
#  コピーペーストしやすい形にファイルを標準出力に出力する
#
function f-shar-cat() {

    # オプション
    local binary_mode=
    local allow_binary=
    local allow_newer_opt=
    local exclude_opt=
    # 引数解析
    while [ $# -gt 0 ];
    do
        if [ x"$1"x = x"--help"x ]; then
            echo "f-shar-cat  [options] directory-name or file-name"
            echo "    options"
            echo "        --binary-mode  ... transfer files in tar file and base64"
            echo "        --allow-binary ... allow binary file in base64 encode"
            echo "        --newer file ... find newer file"
            echo "        --exclude pattern ... exclude pattern"
            return 0
        fi
        if [ x"$1"x = x"--binary-mode"x ]; then
            binary_mode=true
            shift
            continue
        fi
        if [ x"$1"x = x"--allow-binary"x ]; then
            allow_binary=true
            shift
            continue
        fi
        if [ x"$1"x = x"--newer"x ]; then
            allow_newer_opt=" -newer $2 "
            if [ ! -r "$2" ]; then
                echo "file can not found. $2. abort."
                return 1
            fi
            shift
            shift
            continue
        fi
        if [ x"$1"x = x"--exclude"x ]; then
            exclude_opt="$2"
            shift
            shift
            continue
        fi
        break
    done

    local target_dir="$@"
    local file_list=
    if [ -n "$exclude_opt" ] ; then
        file_list=$( find $target_dir $allow_newer_opt | grep -v ".git/" | grep -v "$exclude_opt" )
    else
        file_list=$( find $target_dir $allow_newer_opt | grep -v ".git/"  )
    fi
    local i=
    if [ x"$binary_mode"x = x"true"x ]; then
        # binary mode の場合、全ファイルをtarで送る
        local tar_file=$( mktemp shar-cat-tar-XXXXXXXXXX.tar.gz )
        local tar_list_file=$( mktemp shar-cat-list-XXXXXXXXXX.tmp )
        echo "#"
        echo "# file $tar_file is binary file. "
        echo "#"
        for i in $file_list
        do
            if [ -d "$i" ]; then
                continue
            fi
            if [ -f "$i" ]; then
                echo "$i" >> $tar_list_file
                echo "# add $i"
            fi
        done
        tar czf $tar_file --files-from=$tar_list_file
        echo 'cat > '"$tar_file".base64' << "SCRIPTSHAREOF"'
        cat "$tar_file" | base64
        echo "SCRIPTSHAREOF"
        echo 'cat '"$tar_file".base64' | base64 -d > '"$tar_file"
        echo 'tar xvzf '"$tar_file"
        echo '/bin/rm '"$tar_file"  "$tar_file".base64
        echo ""
        echo ""
        echo ""
        /bin/rm $tar_file $tar_list_file        
    else
        # binary mode ではない場合、catを使ったヒアドキュメント形式で送る
        for i in $file_list
        do
            if [ -d "$i" ]; then
                echo "mkdir -p $i"
            fi
            if [ -f "$i" ]; then
                f_is_text_file "$i"
                local bText=$?
                if [ $bText -ne 0 ]; then
                    echo "#"
                    echo "# file $i is binary file. "
                    echo "#"
                    if [ x"$allow_binary"x = x"true"x ]; then
                        echo "mkdir -p $( dirname $i )"
                        echo 'cat > '"$i".base64' << "SCRIPTSHAREOF"'
                        cat "$i" | base64
                        echo "SCRIPTSHAREOF"
                        echo 'cat '"$i".base64' | base64 -d > '"$i"
                    else
                        echo "# skip"
                    fi
                else
                    echo "#"
                    echo "# $i"
                    echo "#"
                    echo "mkdir -p $( dirname $i )"
                    echo 'cat > '"$i"' << "SCRIPTSHAREOF"'
                    expand -t 4 $i | grep ^
                    echo "SCRIPTSHAREOF"
                    echo ""
                    echo ""
                fi
            fi
        done
    fi
}

# if source this file, define function only ( not run )
if [ ${#BASH_SOURCE[@]} = 1 ]; then
    f-shar-cat "$@"
    RC=$?
    exit $RC
else
    echo "source from $0. define function only. not run." > /dev/null
fi

#
# end of file
#
