#!/bin/bash
REMOTE_NAME=origin
REMOTE_BRANCH=$(git rev-parse --abbrev-ref HEAD)
LOCAL_BRANCH=$(git rev-parse --abbrev-ref HEAD)

SLACK_WEBHOOK=YOUR_SLACK_WEBHOOK
SLACK_TITLE="Docker Deployment"

# Set the slack alert level be DEBUG | SUCCESS | ERROR | NONE
SLACK_ALERT_LEVEL="SUCCESS"


#############################################
# LOGGER
#############################################


LOG_LEVEL_DECIMAL=0
case "$SLACK_ALERT_LEVEL" in
  DEBUG)
    LOG_LEVEL_DECIMAL=3
  ;;
  SUCCESS)
    LOG_LEVEL_DECIMAL=2
  ;;
  ERROR)
    LOG_LEVEL_DECIMAL=1
  ;;
esac
   
_log() {
  local date_time msg level slack_color
  date_time=$(date +"%Y/%m/%d %H:%M:%S")
  msg="$1"
  level="${2-${FUNCNAME[1]}}"
  echo "[$date_time][$level] $msg"
}
_log_and_notify() {
  local date_time msg level slack_color
  date_time=$(date +"%Y/%m/%d %H:%M:%S")
  msg="$1"
  level="${2-${FUNCNAME[1]}}"
  case "$level" in
    SUCCESS)
      slack_color="#84cc16"
      ;;
    DEBUG)
      slack_color="#0ea5e9"
      ;;
    *)
      slack_color="#ef4444"
    ;;
  esac
  echo "[$date_time][$level] $msg"
  PAYLOAD="{ \"attachments\": [{ \"color\": \"$slack_color\", \"fields\": [{ \"title\": \"$SLACK_TITLE\", \"value\": \"$msg\" }]}] }"
  curl -X POST --silent \
    -H 'Content-type: application/json; charset=utf-8' \
    --data "$PAYLOAD" \
    "$SLACK_WEBHOOK" 1>/dev/null
}

function DEBUG() {
	if [[ "$LOG_LEVEL_DECIMAL" -ge "3" ]]
	then
    _log_and_notify "$1"
  else
    _log "$1"
	fi
}

function SUCCESS() {
	if [[ "$LOG_LEVEL_DECIMAL" -ge "2" ]]
	then
    _log_and_notify "$1"
  else
    _log "$1"
	fi
}


function ERROR() {
	if [[ "$LOG_LEVEL_DECIMAL" -ge "1" ]]
	then
    _log_and_notify "$1"
  else
    _log "$1"
	fi
}

function checkResult() {
  status=$?
  message=$1
  if [ "$status" == "0" ]; then
    DEBUG "$message"
  else
    ERROR "$message"
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

git remote update > /dev/null
checkResult "Update Remote"

if [ "$(git rev-parse HEAD)" == "$(git rev-parse @{u})" ]; then
  DEBUG "No changes"
  exit 0
fi

DEBUG "Changes detected"

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

DEBUG "Deleted files"
DEBUG "${delettedFiles[@]}"

DEBUG "Updated files"
DEBUG "${updatedFiles[@]}"


# Docker compose down files
for delettedFile in "${delettedFiles[@]}"; do
    docker-compose -f "$delettedFile" down
    checkResult "DOWN $delettedFile"
    SUCCESS "Successfully deletted $delettedFile !"
done

git pull
checkResult "Pull repository"

# Docker compose up files
for updatedFile in "${updatedFiles[@]}"; do
    docker-compose -f "$updatedFile" up -d
    checkResult "UP $updatedFile"
    SUCCESS "Successfully deploy $updatedFile !"
done


