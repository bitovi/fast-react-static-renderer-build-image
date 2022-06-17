#!/bin/bash

set -e


###
### PUBLISH - environment setup
###

#Defining the Default branch variable
if [ -z "$DEFAULT_BRANCH" ]; then
    DEFAULT_BRANCH="main"
fi


REPO_NAME=$(echo $GITHUB_REPOSITORY | sed 's/^.*\///')
ORG_NAME=$(echo $GITHUB_REPOSITORY | sed 's/\/.*//')
TAG_OR_HEAD="$(echo $GITHUB_REF | cut -d / -f2)"
BRANCH_OR_TAG_NAME=$(echo $GITHUB_REF | cut -d / -f3)
echo "REPO_NAME: $REPO_NAME"
echo "ORG_NAME: $ORG_NAME"
echo "TAG_OR_HEAD: $TAG_OR_HEAD"
echo "BRANCH_OR_TAG_NAME: $BRANCH_OR_TAG_NAME"


# if tag, use tag
# if default branch, use `latest`
# if otherwise, use branch name
if [ -z "$IMAGE_TAG" ]; then
  if [ -n "$USE_COMMIT_HASH_FOR_ARTIFACTS" ]; then
    IMAGE_TAG="$GITHUB_SHA"
  else
    if [ "$TAG_OR_HEAD" == "tags" ]; then
      IMAGE_TAG="$BRANCH_OR_TAG_NAME"
    elif [ "$TAG_OR_HEAD" == "heads" ] && [ "$BRANCH_OR_TAG_NAME" == "$DEFAULT_BRANCH" ]; then
      IMAGE_TAG="latest"
    elif [ "$TAG_OR_HEAD" == "pull" ]; then
      IMAGE_TAG="pr-${BRANCH_OR_TAG_NAME}"
    else
      IMAGE_TAG="$BRANCH_OR_TAG_NAME"
    fi
  fi
fi


###
### PUBLISH DOCKER
###
echo "###"
echo "### PUBLISH DOCKER"
echo "###"

#Defining the Image name variable
IMAGE_NAME="$REPO_NAME"

#Defining the Registry url variable
DEFAULT_ECR_REGISTRY_ID="fast-react-static-renderer-build-image"
if [ -z "$ECR_REGISTRY_ID" ]; then
    ECR_REGISTRY_ID="$DEFAULT_ECR_REGISTRY_ID"
fi

REGISTRY_URL="${AWS_ACCOUNT_NO}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ECR_REGISTRY_ID}"

#Building the docker image...
echo "Building the docker image"
docker build -t ${IMAGE_NAME} .

#docker image deploy function
aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | docker login --username AWS --password-stdin ${REGISTRY_URL}
echo "docker tag ${IMAGE_NAME} ${REGISTRY_URL}:${IMAGE_TAG}"
docker tag ${IMAGE_NAME} ${REGISTRY_URL}:${IMAGE_TAG}

echo "Pushing the docker image to the ecr repository..."
docker push ${REGISTRY_URL}:${IMAGE_TAG}