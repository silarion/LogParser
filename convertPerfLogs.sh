#!/bin/bash

NBLIGNES=`cat $1 | wc -l`
echo "$NBLIGNES lines"
COUNT=0

#TMPFILE=$1.tmp
JSONFILE=$1.json
SORTEDFILE=$1.sorted
#rm -vf $TMPFILE
rm -vf $JSONFILE
rm -vf $SORTEDFILE

echo -n '{"name":"perfs","children":[' >> $JSONFILE

#echo -n '{"name":"analytics", "children": [' >> $JSONFILE

LEVEL=0
declare FIRSTCHILD_LEVEL$LEVEL=true
declare FIRSTPARENT_LEVEL$LEVEL=true
LASTTAG=""
CURRENTLOGIN=""
CURRENTTHREAD=""

function checkNewLevel {
    if [[ $TAG == *_jsp\)* ]] || [[ $TAG == *Action.handleRequest* ]]
    then
        echo true
    fi
}

function checkSameLevel {
    if [[ $LASTTAG == *BannerFRH_jsp* ]] && [[ $TAG == *BreadcrumbFRH_jsp* ]] || \
        [[ $TAG == *HeaderNav*_jsp* ]]
    then
        echo true
    fi
}


#transfo en CSV
cat $1 | sed 's/,/#/;s/log\[\(.*\)\] node\[\(.*\)\] thread\[\(.*\)\] login\[\(.*\)\] start\[\(.*\)\] time\[\(.*\)\] tag\[\(.*\)\]/\1,\2,\3,\4,\5,\6,\7/' | \
sort -t ',' -k 4,4 -k 3,3 -k 5,5 | \
{
while IFS=',' read LOG NODE THREAD LOGIN START TIME TAG MSG
do
  echo "$LOG $NODE $THREAD $LOGIN $START $TIME $TAG $MSG" >> $SORTEDFILE
  #echo $LEVEL

    if [[ "$CURRENTLOGIN" != "$LOGIN" ]] || [[ "$CURRENTTHREAD" != "$THREAD" ]]
    then
        while [ $LEVEL -ne 0 ]
        do
            echo -n "]}" >> $JSONFILE
            LEVEL=$(($LEVEL - 1))
        done
        #echo -n "," >> $JSONFILE
        LASTTAG=""
    fi

    CURRENTLOGIN=$LOGIN
    CURRENTTHREAD=$THREAD

    NEWLEVEL=$(checkNewLevel $TAG)

  #check debut d'un nouveau groupe de log de + plus haut niveau
  if [[ $TAG == *AccessFilter.doFilter* ]]
  then
    #check si premier parent des enfants pour rajouter ou non ']},'
    FIRSTPARENT=FIRSTPARENT_LEVEL$LEVEL
    if [ "${!FIRSTPARENT}" == "true" ]
    then
        declare FIRSTPARENT_LEVEL$LEVEL=false
        FIRSTCHILD=FIRSTCHILD_LEVEL$LEVEL
        if [ "${!FIRSTCHILD}" == "true" ]
        then
            declare FIRSTCHILD_LEVEL$LEVEL=false
        else
            echo -n "," >> $JSONFILE
        fi
    else
        while [ $LEVEL -ne 0 ]
        do
            echo -n "]}" >> $JSONFILE
            LEVEL=$(($LEVEL - 1))
        done
        echo -n "," >> $JSONFILE
        LASTTAG=""
    fi

    LEVEL=$(($LEVEL + 1))
    declare FIRSTCHILD_LEVEL$LEVEL=true
    echo -n "{\"name\":\"$TAG\",\"size\":\"$TIME\",\"login\":\"$LOGIN\",\"children\":[" >> $JSONFILE
  elif [ "$NEWLEVEL" == "true" ]
  then
    #check si le nouveau TAG et l'ancien ne sont pas de meme niveau
    SAMELEVEL=$(checkSameLevel $LASTTAG $TAG)
    if [ "$SAMELEVEL" == "true" ]
    then
        LEVEL=$(($LEVEL - 1))
        echo -n "]}" >> $JSONFILE
    fi

    LASTTAG=$TAG

    #groupes secondaires
    FIRSTCHILD=FIRSTCHILD_LEVEL$LEVEL
    if [ "${!FIRSTCHILD}" == "true" ]
    then
        declare FIRSTCHILD_LEVEL$LEVEL=false
    else
        echo -n "," >> $JSONFILE
    fi
    LEVEL=$(($LEVEL + 1))
    declare FIRSTCHILD_LEVEL$LEVEL=true
    echo -n "{\"name\":\"$TAG\",\"size\":\"$TIME\",\"login\":\"$LOGIN\",\"children\":[" >> $JSONFILE

  else
    FIRSTCHILD=FIRSTCHILD_LEVEL$LEVEL
    if [ "${!FIRSTCHILD}" == "true" ]
    then
        declare FIRSTCHILD_LEVEL$LEVEL=false
    else
        echo -n "," >> $JSONFILE
    fi
    echo -n "{\"name\":\"$TAG\",\"size\":\"$TIME\",\"login\":\"$LOGIN\"}" >> $JSONFILE
  fi
  
  #echo "{ log:\"$LOG\", node:\"$NODE\", thread:\"$THREAD\", login:\"$LOGIN\", start:\"$START\", time:\"$TIME\", tag:\"$TAG\" }" >> $JSONFILE
  
  #echo -ne "$(($COUNT * 100 / $NBLIGNES)) %\r"
  COUNT=$(($COUNT + 1))
  printf "%3d %%\r" $(($COUNT * 100 / $NBLIGNES))

done

while [ $LEVEL -ne 0 ]
do
    echo -n "]}" >> $JSONFILE
    LEVEL=$(($LEVEL - 1))
done
}

echo -n "]}" >> $JSONFILE

echo
#echo DONE
