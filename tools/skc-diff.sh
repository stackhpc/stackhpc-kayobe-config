#!/bin/bash

# Simple script to get the difference between the current kayobe-config
# checkout and either upstream stackhpc-kayobe-config (default) or the same
# branch 4 weeks ago (add --month argument).

SKC_BRANCH=stackhpc/2024.1
LOCAL_BRANCH=HEAD

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

cd $SCRIPTPATH/..

git remote add nonduplicatedremotename https://github.com/stackhpc/stackhpc-kayobe-config

git fetch nonduplicatedremotename > /dev/null 2>&1

if [ "$1" = "--month" ];
then
    # Top version is the "working" but bad approach, bottom version is not working yet but will be better once we fix it
    git diff "$LOCAL_BRANCH@{4 weeks ago}" $LOCAL_BRANCH -- releasenotes/notes/ | grep '^\+' | grep -v '\(+++\|---\)' | sed s/^+//g
    # git diff --name-status "$LOCAL_BRANCH@{4 weeks ago}" $LOCAL_BRANCH -- releasenotes/notes/
else
    git diff $LOCAL_BRANCH nonduplicatedremotename/$SKC_BRANCH -- releasenotes/notes/ | grep '^\+' | grep -v '\(+++\|---\)' | sed s/^+//g
    # git diff --name-status $LOCAL_BRANCH nonduplicatedremotename/$SKC_BRANCH -- releasenotes/notes/
fi;

git remote rm nonduplicatedremotename

