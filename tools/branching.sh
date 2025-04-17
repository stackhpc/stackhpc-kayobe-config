#!/bin/bash

SKC_BRANCH="$( git branch --show-current )" > /dev/null 2>&1

LOCAL_BRANCH=twig

if [ "$1" = "--delete" ];
then
    git switch $SKC_BRANCH > /dev/null 2>&1
    git branch -D $LOCAL_BRANCH > /dev/null 2>&1

elif [ "$1" = "--try" ];
then
    git checkout $LOCAL_BRANCH > /dev/null 2>&1
    if "$( git branch --show-current )" = $LOCAL_BRANCH;
    then
        git reset --hard 1720c91e4ad0429fd3c93310df3d244d351f6a84 > /dev/null 2>&1
    fi;
else
    git checkout -b $LOCAL_BRANCH
    git reset --hard 1720c91e4ad0429fd3c93310df3d244d351f6a84 > /dev/null 2>&1

fi;
