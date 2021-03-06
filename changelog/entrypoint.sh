#!/bin/bash

# validate parameters
if [ ! -d "$(pwd)/.git" ]; then
   echo "not a git repository (or any of the parent directories): .git"
   exit 1
fi

if [ -z "${RELEASE_FROM}" ]; then
   echo "\$RELEASE_FROM is empty"
   exit 1
fi

if [ -z "${RELEASE_TO}" ]; then
   echo "\$RELEASE_TO is empty"
   exit 1
fi

if [ -z "${APP_NAME}" ]; then
   echo "\$APP_NAME is empty"
   exit 1
fi

if [ -n "${ENABLE_PR}" -a -z "${REPO_NAME}" ]; then
   echo "\$REPO_NAME is empty"
   exit 1
fi

# set variables with defalt

OPT_TOKEN=""
if [ -n "${GITHUB_TOKEN}" ]; then
    OPT_TOKEN="--token=${GITHUB_TOKEN}"
fi

OPT_USER="sacloud-bot"
if [ -n "${USERNAME}" ]; then
    OPT_USER="${USERNAME}"
fi

OPT_EMAIL="<sacloud.users@gmail.com>"
if [ -n "${EMAIL}" ]; then
    OPT_EMAIL="<${EMAIL}>"
fi

# CHANGELOG.md
OPT_CHANGELOG_PATH="CHANGELOG.md"
if [ -n "${CHANGELOG_PATH}" ]; then
    OPT_CHANGELOG_PATH=${CHANGELOG_PATH}
fi

# RPM
OPT_RPM_SPEC_PATH="package/rpm/${APP_NAME}.spec"
if [ -n "${RPM_SPEC_PATH}" ]; then
    OPT_RPM_SPEC_PATH="${RPM_SPEC_PATH}"
fi

# deb
OPT_DEB_CHANGELOG_PATH="package/deb/debian/changelog"
if [ -n "${DEB_CHANGELOG_PATH}" ]; then
    OPT_DEB_CHANGELOG_PATH="${DEB_CHANGELOG_PATH}"
fi

# for changelog.md
ghch -f v${RELEASE_FROM} -N v${RELEASE_TO} -F markdown ${OPT_TOKEN} > /tmp/new.md
touch $OPT_CHANGELOG_PATH
cat $OPT_CHANGELOG_PATH | sed -E 's/# Changelog//' | sed -E '/^$/{N; /^\n$/D;}' > /tmp/old.md

cat /header.txt /tmp/new.md /tmp/old.md > $OPT_CHANGELOG_PATH

# for rpm/dep/body of pull-request
ghch -f v${RELEASE_FROM} -N v${RELEASE_TO} -F json ${OPT_TOKEN} > /tmp/new.json

# for rpm
if [ -n "${ENABLE_RPM}" ]; then
    echo "$(date '+%a %b %d %Y') ${OPT_EMAIL} - ${RELEASE_TO}-1" > /tmp/rpm_changelog
    cat /tmp/new.json | jq -r '.pull_requests[] | "- \(.title) (by \(.user.login))"' >> /tmp/rpm_changelog
    echo "" >> /tmp/rpm_changelog
    sed -i -e "/\%changelog$/r /tmp/rpm_changelog"  package/rpm/usacloud.spec
fi

# for deb
if [ -n "${ENABLE_DEB}" ]; then
    echo "${APP_NAME} (${RELEASE_TO}-1) stable; urgency=low" > /tmp/deb_changelog
    echo "" >> /tmp/deb_changelog
    cat /tmp/new.json | jq -r '.pull_requests[] | "  * \(.title) (by \(.user.login))\n    <\(.html_url)>"' >> /tmp/deb_changelog
    echo "" >> /tmp/deb_changelog
    echo " -- ${OPT_USER} ${OPT_EMAIL}  $(date '+%a, %d %b %Y %H:%M:%S %z')" >> /tmp/deb_changelog
    echo "" >> /tmp/deb_changelog
    touch ${OPT_DEB_CHANGELOG_PATH}
    cp ${OPT_DEB_CHANGELOG_PATH} /tmp/old_deb_changelog
    cat /tmp/deb_changelog /tmp/old_deb_changelog > ${OPT_DEB_CHANGELOG_PATH}
fi

if [ -n "${ENABLE_PR}" ]; then
    # check latest commit message
    LATEST_COMMIT_MSG=$(git log --oneline master..HEAD | cut -d ' ' -f2-)
    if [ "${LATEST_COMMIT_MSG}" = "update changelogs" ]; then
      echo "skip to update changelogs because the last commit is 'update changelogs'"
      exit
    fi

    echo "Release version ${RELEASE_TO}" > /tmp/pr_body
    echo "" >> /tmp/pr_body
    echo "" >> /tmp/pr_body
    cat /tmp/new.json | jq -r '.pull_requests[] | "- \(.title)([GH-\(.number)](\(.html_url)))"' >> /tmp/pr_body

    # commit changes and push to github
    git config --global user.name "${OPT_USER}" >/dev/null 2>&1
    git config --global user.email "${OPT_EMAIL}" >/dev/null 2>&1
    git commit -am "update changelogs" >/dev/null 2>&1
    git push -u "https://${GITHUB_TOKEN}@github.com/${REPO_NAME}.git" >/dev/null 2>&1

    # create pull request
    # TODO detect conflict
    PR_URL=$(hub pull-request -F /tmp/pr_body -b ${REPO_NAME}:master)
    if [ $? -eq 0 ]; then
        echo "Release pull-request has been created: ${PR_URL}"
    fi
fi

