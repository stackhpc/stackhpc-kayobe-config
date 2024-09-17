#!/usr/bin/python3

DESCRIPTION = """
This script merges one release branch of SKC into another.

Example 1: Merge stackhpc/yoga into stackhpc/zed:

    merge.py yoga zed

Example 2: Merge the branch created in example 1 into stackhpc/2023.1:

    merge.py zed 2023.1 zed-yoga-merge

Example 3: Continue after manually resolving merge conflicts seen in example 2:

    merge.py zed 2023.1 zed-yoga-merge --continue

"""

import argparse
import os
from subprocess import check_call, check_output
import sys


def command(cmd):
    print("Running:", cmd)
    check_call(cmd)


def parse_args():
    parser = argparse.ArgumentParser(description=DESCRIPTION, formatter_class=argparse.RawDescriptionHelpFormatter)
    #"Merge one branch of SKC into the next")
    parser.add_argument("previous", type=str, help="The previous version")
    parser.add_argument("current", type=str, help="The current version")
    parser.add_argument("previous_branch", type=str, nargs="?", default=None, help="Optional branch to use as the previous release. Allows merging multiple branches in parallel.")
    parser.add_argument("--continue", dest="cont", action="store_true", help="Continue after merge conflicts have been resolved.")
    parser.add_argument("--remote", type=str, default="origin", help="Git remote")
    return parser.parse_args()


def fetch(args):
    command(["git", "fetch", args.remote])


def checkout(args):
    merge_branch = f"{args.current}-{args.previous}-merge"
    current_branch = f"{args.remote}/stackhpc/{args.current}"
    command(["git", "checkout", "-B", merge_branch, current_branch])


def update_submodules():
    command(["git", "submodule", "update"])


def merge_in_progress():
    repo_root = check_output(["git", "rev-parse", "--show-toplevel"])
    repo_root = repo_root.decode().strip()
    return os.path.isfile(os.path.join(repo_root, ".git", "MERGE_HEAD"))


def uncommitted_changes():
    unstaged = check_output(["git", "diff"])
    staged = check_output(["git", "diff", "--cached"])
    return unstaged or staged


def continue_merge():
    if merge_in_progress():
        command(["git", "merge", "--continue"])
    else:
        print("No merge in progress")


def merge(args):
    if args.previous_branch:
        previous_branch = args.previous_branch
    else:
        previous_branch = f"{args.remote}/stackhpc/{args.previous}"
    commit_message = f"Merge stackhpc/{args.previous} into stackhpc/{args.current}"
    command(["git", "merge", previous_branch, "-m", commit_message])


def show_diff(args):
    print("Proposed changes:")
    current_branch = f"{args.remote}/stackhpc/{args.current}"
    command(["git", "diff", current_branch])


def create_pr(args):
    current_branch = f"stackhpc/{args.current}"
    pr_title = f"{args.current}: {args.previous} merge"
    command(["gh", "pr", "create", "-f", "-a", "@me", "-B", current_branch, "-t", pr_title])


def main():
    args = parse_args()
    if args.cont:
        continue_merge()
    else:
        if merge_in_progress():
            print("Merge in progress - did you miss the --continue argument?")
            sys.exit(1)
        if uncommitted_changes():
            print("You have uncommitted changes - aborting")
            sys.exit(1)
        fetch(args)
        checkout(args)
        update_submodules()
        merge(args)
    show_diff(args)
    create_pr(args)


if __name__ == "__main__":
    main()
