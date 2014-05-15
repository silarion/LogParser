#!/bin/bash

NBLIGNES=`cat $1 | wc -l`
echo "$NBLIGNES lines"
COUNT=0

JSONFILE=$1.json
SORTEDFILE=$1.sorted
DEBUGFILE=$1.debug
rm -vf ${JSONFILE}
rm -vf ${SORTEDFILE}
rm -vf ${DEBUGFILE}

function json {
    echo $* >> $JSONFILE
	debug "JSON : " $*
}

function debug {
    echo $* >> $DEBUGFILE
}

function sorted {
    echo $* >> $SORTEDFILE
}

function isChild {
	RESULT=false
    L=LOGIN$1
    debug "$L : ${!L}"
    T=THREAD$1
    debug "$T : ${!T}"
    END=END$1
    debug "END : ${!END} < $START ?"
    if [[ "${!L}" == "$LOGIN" ]] && [[ "${!T}" == "$THREAD" ]] && [[ ${!END} -ge $START ]]
    then
        RESULT=true
    fi

    #cas root
	if [[ $1 -eq 0 ]] || [[ "${!L}" == "perfs" ]]
	then
		RESULT=true
	fi

	debug "Child of $1 ? : $RESULT"
	echo $RESULT
}

function isFirstChild {
    RESULT=true
	FIRSTCHILD=FIRSTCHILD$1
	debug "$FIRSTCHILD : ${!FIRSTCHILD}"
	if [ "false" == "${!FIRSTCHILD}" ]
	then
	    RESULT=false
	fi
	echo $RESULT
	debug "1st child of $1 ? : $RESULT"
}

function majVar {
    eval $1=$2
	debug "$1 -> ${!1}"
}

function getVar {
    echo ${!1}
}

function tree {
    if [[ "$(isChild $LEVEL)" == "true" ]]
  then
	if [[ "$(isFirstChild $LEVEL)" == "true" ]]
	then
		json ",\"children\":["
		majVar FIRSTCHILD$LEVEL false
	else
		json ","
	fi
	majVar LEVEL $((LEVEL + 1))
  else
    if [[ "$(isFirstChild $LEVEL)" == "true" ]]
	then
		json '}'
	else
		json ']}'
		majVar FIRSTCHILD$LEVEL true
	fi
	if [[ "$(isChild $((LEVEL - 1)))" == "true" ]]
	then
		json ','
	else
		majVar LEVEL $((LEVEL - 1))
		tree
	fi
  fi
}

#init
LEVEL=0

#root
majVar LEVEL $((LEVEL + 1))
majVar FIRSTCHILD$LEVEL true
majVar LOGIN$LEVEL "perfs"
majVar THREAD$LEVEL "perfs"
majVar END$LEVEL 999999999999999999

json '{"name":"perfs"'

#transfo to CSV + sort by LOGIN then THREAD then START
cat $1 | sed 's/,/#/;s/log\[\(.*\)\] node\[\(.*\)\] thread\[\(.*\)\] login\[\(.*\)\] start\[\(.*\)\] time\[\(.*\)\] tag\[\(.*\)\]/\1,\2,\3,\4,\5,\6,\7/' | \
sort -t ',' -k 4,4 -k 3,3 -k 5,5 | \
{
while IFS=',' read LOG NODE THREAD LOGIN START TIME TAG MSG
do
    sorted "$LOG $NODE $THREAD $LOGIN $START $TIME $TAG $MSG"
	debug ""
    debug "$LOG $NODE $THREAD $LOGIN $START $TIME $TAG $MSG"
    debug "LEVEL : $LEVEL"

  tree
  
  json "{\"name\":\"$TAG\",\"size\":\"$TIME\",\"login\":\"$LOGIN\",\"thread\":\"$THREAD\""
  
  majVar LOGIN$LEVEL $LOGIN
  majVar THREAD$LEVEL $THREAD
  majVar END$LEVEL $(($START + $TIME))

  #count
  COUNT=$(($COUNT + 1))
  printf "%3d %%\r" $(($COUNT * 100 / $NBLIGNES))

done

#close last log
json '}'

#close all
while [ $LEVEL -ne 1 ]
do
    json "]}"
    LEVEL=$(($LEVEL - 1))
done
}

#json "]}"

echo
echo DONE
