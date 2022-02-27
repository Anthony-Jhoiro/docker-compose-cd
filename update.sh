#!/bin/bash
REMOTE_NAME=origin
REMOTE_BRANCH=master
LOCAL_BRANCH=master

SLACK_WEBHOOK=YOUR_SLACK_WEBHOOK
SLACK_TITLE="Docker Deployment"

notify() {
  message="$1"
  echo "=> $message"
  docker run --rm -e SLACK_WEBHOOK=$SLACK_WEBHOOK -e SLACK_TITLE="$SLACK_TITLE" -e SLACK_MESSAGE="$message"  technosophos/slack-notify
}

function checkResult() {
  status=$?
  message=$1
  if [ "$status" == "0" ]; then
    echo "[SUCCESS] $message"
  else
    echo "[ ERROR ] $message"
    notify "[ ERROR ] $message"
    exit 1
  fi
}

function filterDockerComposeFiles() {
  arr=()
  for changedFile in $1; do
    if [[ $changedFile =~ docker-compose\.ya?ml$ ]]; then
      arr+=("$changedFile")
    fi
  done
  echo arr
}

getStatus() {
    echo "$1" | cut -f 1
}

getFileName() {
    echo "$1" | cut -f 2
}



git remote update
checkResult "Update Remote"

if [ "$(git rev-parse HEAD)" == "$(git rev-parse @{u})" ]; then
  echo "No changes"
  exit 0
fi

echo "Changes detected"

changedFiles=$(git diff --name-status $LOCAL_BRANCH $REMOTE_NAME/$REMOTE_BRANCH)
checkResult "Update Remote"

delettedFiles=()
updatedFiles=()

while IFS= read -r changedFile; do
  # Check if docker-compose file
  status=$(getStatus "$changedFile")
  fileName=$(getFileName "$changedFile")

  if [[ $fileName =~ docker-compose\.ya?ml$ ]]; then

    if [ "$status" == "D" ]; then
      # File must be deleted
      delettedFiles+=("$fileName")
    else
      updatedFiles+=("$fileName")
    fi
  fi
done <<< "$changedFiles"

echo "Deleted files"
echo "${delettedFiles[@]}"

echo "Updated files"
echo "${updatedFiles[@]}"


# Docker compose down files
for delettedFile in "${delettedFiles[@]}"; do
    docker-compose -f "$delettedFile" down
    checkResult "DOWN $delettedFile"
    notify "Successfully deletted $delettedFile !"
done

git pull
checkResult "Pull repository"

# Docker compose up files
for updatedFile in "${updatedFiles[@]}"; do
    docker-compose -f "$updatedFile" up -d
    checkResult "UP $updatedFile"
    notify "Successfully deploy $updatedFile !"
done


