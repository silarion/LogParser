#!/bin/bash

NBLIGNES=`cat $1 | wc -l`
echo "$NBLIGNES lines"
COUNT=0

#FILENAME=$1
FILENAME=perfs
JSONFILE=$FILENAME.json
SORTEDFILE=$FILENAME.sorted
DEBUGFILE=$FILENAME.debug
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
    if [[ "${!L}" == "$LOGIN" ]] && [[ "${!T}" == "$THREAD" ]] && [[ ${!END} -ge $((START + TIME)) ]] #&& [[ $START -ne $(getVar START$LEVEL) ]]
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

		#init rest of time
		majVar REST$LEVEL $(getVar TIME$LEVEL)
	else
		json ","
	fi
	majVar LEVEL $((LEVEL + 1))
  else
    if [[ "$(isFirstChild $LEVEL)" == "true" ]]
	then
		json '}'
	else
	    #add 'unknown' node
	    UNKNOWN=$(getVar REST$LEVEL)
	    if [ $UNKNOWN -ge 0 ]
	    then
	        json ",{\"name\":\"unknown\",\"size\":\"$UNKNOWN\",\"login\":\"$LOGIN\",\"thread\":\"$THREAD\"}"
	    else
	        debug "UNKNOWN < 0 : $LOG $NODE $THREAD $LOGIN $START $TIME $TAG $MSG"
	        json ",{\"name\":\"unknown\",\"size\":\"0\",\"login\":\"$LOGIN\",\"thread\":\"$THREAD\"}"
	    fi
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
  
  json "{\"name\":\"$TAG\",\"size\":\"$TIME\",\"login\":\"$LOGIN\",\"thread\":\"$THREAD\",\"start\":\"$START\",\"time\":\"$TIME\""
  
  majVar LOGIN$LEVEL $LOGIN
  majVar THREAD$LEVEL $THREAD
  majVar TIME$LEVEL $TIME
  majVar START$LEVEL $START
  majVar END$LEVEL $(($START + $TIME))

  #maj rest of time
  REST=$(getVar REST$((LEVEL - 1)))
  majVar REST$((LEVEL - 1)) $(($REST - $TIME))

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

#server
if [[ "`command -v nc`" != "" ]]
then

    RESP=/tmp/webresp
    [ -p $RESP ] || mkfifo $RESP

    while true ; do
        ( cat $RESP ) | nc -l 9000 | (
        REQ=`while read L && [ " " "<" "$L" ] ; do echo "$L" ; done`
        URL=${REQ#GET /}
        URL=${URL% HTTP/*}
        echo "[`date '+%Y-%m-%d %H:%M:%S'`] $REQ" | head -1
        [ "$URL" == "perfs.html" ] && BODY=`cat perfs.html`
        [ "$URL" == "perfs.json" ] && BODY=`cat perfs.json`
        cat >$RESP <<EOF
        HTTP/1.0 200 OK
        Cache-Control: private
        Content-Type: text/html
        Server: bash/2.0
        Connection: Close
        Content-Length: ${#BODY}

        $BODY
        EOF
        )
    done

fi
