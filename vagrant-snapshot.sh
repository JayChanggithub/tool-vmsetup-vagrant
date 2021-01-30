#!/bin/bash

# color code
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC1='\033[0m'

# define variable
cwd=$PWD
args="$@"
__file__=$(basename $0)
log_name=$(basename $__file__ .sh).log
logdir=$cwd/reports
exe_path='/root/vagrant-home'
revision="$(grep 'Rev:' README.md | grep -Eo '([0-9]+\.){2}[0-9]+')"
tm=$(date +'%Y%m%d%T' | tr -s ':' ' ' | tr -d ' ')
snap=($@)

function snapshot
{
    for e in "${snap[@]}"
    do
        cd $exe_path/${e}
        local n=$(echo $e | tr -d ' ')
        if [ $(vagrant snapshot list \
             | grep -Eco "${n}-${tm}") -eq 1 ]; then
            
            cd $cwd; printf "%s\t%30s${RED} %s ${NC1}]\n" \
                            " * ${n}-${tm} " \
                            "[" "snapshot: exist."
            return 0
        fi 
        vagrant snapshot save "${n}-${tm}"
        cd $cwd
    done
}

function delbefore
{
    for e in "${snap[@]}"
    do
        cd $exe_path/${e}
        local n=$(echo $e | tr -d ' ')
        if [ $(vagrant snapshot list | grep -Eco "$n") -gt 3 ]; then
            local snapshot_len=$(vagrant snapshot list | grep -c "$n")
            local snpshot_rm=($(vagrant snapshot list \
                               | grep "$n" \
                               | sort -Vr \
                               | sed -n 4,${snapshot_len}p))
            for s in "${snpshot_rm[@]}"
            do
                printf "%s\t%30s${YELLOW} %s ${NC1}]\n" \
                            " * delete snaoshot " \
                            "[" "snapshot: "$s"."
                vagrant snapshot delete "${s}"
            done
        fi
        cd $cwd
    done
}

function main
{
    # take snapshot for VM's
    snapshot

    # delete snapshot for VM's save latest 3 snapshot
    delbefore
}

main | tee $cwd/reports/${log_name}
