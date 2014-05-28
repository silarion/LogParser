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
    debug "${!L} == $LOGIN"
    T=THREAD$1
    debug "${!T} == $THREAD"
    END=END$1
    debug "END : ${!END} >= $((START + TIME)) ?"
    if [[ "${!L}" == "$LOGIN" ]] && [[ "${!T}" == "$THREAD" ]] && [[ ${!END} -ge $((START + TIME)) ]]
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
      
      #add 'unknown' node
      LASTSTART=$(getVar START$LEVEL)
      if [ "$LASTSTART" != "" ] && [ $LASTSTART -ne $START ]
      then
        json "{\"name\":\"unknown\",\"size\":\"$((START - LASTSTART))\",\"login\":\"$LOGIN\",\"thread\":\"$THREAD\",\"start\":\"$LASTSTART\",\"end\":\"$START\"},"
        #update rest of time
        REST=$(getVar REST$LEVEL)
        majVar REST$LEVEL $((REST - START + LASTSTART))
      fi
        
  	else
  		json ","
      
      #hole in timeline
      LASTEND=$(getVar END$LEVEL)
      if [ "$LASTEND" != "" ] && [ $LASTEND -ne $START ]
      then
        json "{\"name\":\"unknown\",\"size\":\"$((START - LASTEND))\",\"login\":\"$LOGIN\",\"thread\":\"$THREAD\",\"start\":\"$LASTEND\",\"end\":\"$START\"},"
        #update rest of time
        REST=$(getVar REST$((LEVEL - 1)))
        majVar REST$((LEVEL - 1)) $((REST - START + LASTEND))
      fi
      
  	fi
	  majVar LEVEL $((LEVEL + 1))
  else
    if [[ "$(isFirstChild $LEVEL)" == "true" ]]
	  then
		  json '}'
	  else
	    #add 'unknown' node
	    UNKNOWN=$(getVar REST$LEVEL)
      LASTSTART=$(getVar START$((LEVEL - 1)))
      LASTEND=$(getVar END$((LEVEL - 1)))
	    if [ $UNKNOWN -ge 0 ]
	    then
	        json ",{\"name\":\"unknown\",\"size\":\"$UNKNOWN\",\"login\":\"$LOGIN\",\"thread\":\"$THREAD\",\"start\":\"$LASTSTART\",\"end\":\"$LASTEND\"}"
	    else
	        debug "UNKNOWN < 0 : $LOG $NODE $THREAD $LOGIN $START $TIME $TAG $MSG"
	        json ",{\"name\":\"unknown\",\"size\":\"0\",\"login\":\"$LOGIN\",\"thread\":\"$THREAD\",\"start\":\"$LASTSTART\",\"end\":\"$LASTEND\"}"
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
cat $1 | sed 's/,/#/g;s/log\[\(.*\)\] node\[\(.*\)\] thread\[\(.*\)\] login\[\(.*\)\] start\[\(.*\)\] time\[\(.*\)\] tag\[\(.*\)\]/\1,\2,\3,\4,\5,\6,\7/' | \
sort -t ',' -k 4,4 -k 3,3 -k 5,5 | \
{
while IFS=',' read LOG NODE THREAD LOGIN START TIME TAG MSG
do

    if [[ "$TAG" == ""  ]]
    then
        continue
    fi

    THREAD=${THREAD// /}
    THREAD=${THREAD//\'/}
    THREAD=${THREAD//(/}
    THREAD=${THREAD//)/}
    sorted "$LOG $NODE $THREAD $LOGIN $START $TIME $TAG $MSG"
	  debug ""
    debug "$LOG $NODE $THREAD $LOGIN $START $TIME $TAG $MSG"
    debug "LEVEL : $LEVEL"

  tree
  
  json "{\"name\":\"$TAG\",\"size\":\"$TIME\",\"login\":\"$LOGIN\",\"thread\":\"$THREAD\",\"start\":\"$START\",\"time\":\"$TIME\",\"end\":\"$((START + TIME))\""
  
  majVar LOGIN$LEVEL $LOGIN
  majVar THREAD$LEVEL $THREAD
  majVar TIME$LEVEL $TIME
  majVar START$LEVEL $START
  majVar END$LEVEL $(($START + $TIME))

  #update rest of time
  REST=$(getVar REST$((LEVEL - 1)))
  majVar REST$((LEVEL - 1)) $(($REST - $TIME))

  #display count
  COUNT=$(($COUNT + 1))
  printf "%3d %%\r" $(($COUNT * 100 / $NBLIGNES))

done

#close last log
json '}'

#close all
while [ $LEVEL -ne 1 ]
do
    
    #add 'unknown' node
    UNKNOWN=$(getVar REST$((LEVEL - 1)))
    LASTSTART=$(getVar START$((LEVEL - 1)))
    LASTEND=$(getVar END$((LEVEL - 1)))
    if [ $UNKNOWN -ge 0 ]
    then
        json ",{\"name\":\"unknown\",\"size\":\"$UNKNOWN\",\"login\":\"$LOGIN\",\"thread\":\"$THREAD\",\"start\":\"$LASTEND\",\"end\":\"$START\"}"
    else
        debug "UNKNOWN < 0 : $LOG $NODE $THREAD $LOGIN $START $TIME $TAG $MSG"
        json ",{\"name\":\"unknown\",\"size\":\"0\",\"login\":\"$LOGIN\",\"thread\":\"$THREAD\",\"start\":\"$LASTEND\",\"end\":\"$START\"}"
    fi
    
    json "]}"
    LEVEL=$(($LEVEL - 1))
done
}

#json "]}"

echo
echo DONE

#server
RESP=/tmp/webresp
[ -p $RESP ] || mkfifo $RESP

while true ; do
( cat $RESP ) | nc -l 9000 | (
REQ=`while read L && [ " " "<" "$L" ] ; do echo "$L" ; done`
URL=${REQ#GET /}
URL=${URL% HTTP/*}
echo "[`date '+%Y-%m-%d %H:%M:%S'`] $REQ" | head -1
[ "$URL" == "" ] && BODY=`cat perfs.html`
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

