#!/usr/bin/env python

def main():
    # tail -n +2 centos-container-images/container-images | \
    # awk '{ print $1 }' | \
    # grep -v bifrost-base$ | \
    # sed -e 's/ark\.stackhpc\.com\/stackhpc\-dev\/centos\-source\-//g' -e 's/-/_/g' -e 's/$/: ${{ needs.generate-tag.outputs.kolla_tag }}/'
    print("hello!")


if __name__ == "__main__":
