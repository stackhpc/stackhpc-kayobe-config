#!/bin/bash



SKC_BRANCH=stackhpc/2024.1
LOCAL_BRANCH=examplebranch
# SKC_branch is up to date, LOCAL_BRANCH is reset back ~ 1 month as an example customer config (last commit 5/3/25)

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
# For the script to work in its current state, should be in a kayobe-config directory in the tools folder and run on the LOCAL_BRANCH


cd $SCRIPTPATH/..

git checkout $SKC_BRANCH > /dev/null 2>&1
git pull $SKC_BRANCH > /dev/null 2>&1


# Below uses tags passed through by the python script to run each git diff, ideally would be accomplished with a function but haven't figured that out yet
if [ "$1" = "--kayobe" ];
then
    LATESTKAYOBE="$( cat $SCRIPTPATH/../requirements.txt | grep @stackhpc/ )" #gets whole line including kayobe tag
    LATESTKAYOBETAG="${LATESTKAYOBE##*@}" # gets the tag from the line
    echo "Latest kayobe tag: $LATESTKAYOBETAG" 

    git checkout $LOCAL_BRANCH > /dev/null 2>&1
    git pull $LOCAL_BRANCH > /dev/null 2>&1

    CURRENTKAYOBE="$( cat $SCRIPTPATH/../requirements.txt | grep @stackhpc/ )"
    CURRENTKAYOBETAG="${CURRENTKAYOBE##*@}"
    echo "Current kayobe tag: $CURRENTKAYOBETAG"

    git clone https://github.com/stackhpc/kayobe.git /tmp/kayobe
    cd /tmp/kayobe
    
    git diff --name-status $LATESTKAYOBETAG $CURRENTKAYOBETAG -- releasenotes/notes/

    cd $SCRIPTPATH/..
    rm -rf /tmp/kayobe

elif [ "$1" = "--kolla" ];
then
    LATESTKOLLA="$( cat $SCRIPTPATH/../etc/kayobe/stackhpc.yml | grep kolla_source_version )"
    LATESTKOLLATAG="${LATESTKOLLA##* }"
    echo "Latest kolla tag: $LATESTKOLLATAG"

    git checkout $LOCAL_BRANCH > /dev/null 2>&1
    git pull $LOCAL_BRANCH > /dev/null 2>&1

    CURRENTKOLLA="$( cat $SCRIPTPATH/../etc/kayobe/stackhpc.yml | grep kolla_source_version )"
    CURRENTKOLLATAG="${CURRENTKOLLA##* }"
    echo "Current kolla tag: $CURRENTKOLLATAG"

    git clone https://github.com/stackhpc/kolla.git /tmp/kolla
    cd /tmp/kolla

    git diff --name-status $CURRENTKOLLATAG $LATESTKOLLATAG -- releasenotes/notes/

    cd $SCRIPTPATH/..
    rm -rf /tmp/kolla

elif [ "$1" = "--kollaansible" ];
then
    LATESTKA="$( cat $SCRIPTPATH/../etc/kayobe/stackhpc.yml | grep kolla_ansible_source_version )"
    LATESTKATAG="${LATESTKA##* }"
    echo "Latest kolla ansible tag: $LATESTKATAG"

    git checkout $LOCAL_BRANCH > /dev/null 2>&1
    git pull $LOCAL_BRANCH > /dev/null 2>&1

    CURRENTKA="$( cat $SCRIPTPATH/../etc/kayobe/stackhpc.yml | grep kolla_ansible_source_version )"
    CURRENTKATAG="${CURRENTKA##* }"
    echo "Current kolla ansible tag: $CURRENTKATAG"

    git clone https://github.com/stackhpc/kolla-ansible.git /tmp/kolla-ansible
    cd /tmp/kolla-ansible

    git diff --name-status $CURRENTKATAG $LATESTKATAG -- releasenotes/notes/

    cd $SCRIPTPATH/..
    rm -rf /tmp/kolla-ansible

else
    #git diff on SKC
    git diff $LOCAL_BRANCH $SKC_BRANCH -- releasenotes/notes/ | grep '^\+' | grep -v '\(+++\|---\)' | sed s/^+//g

fi;