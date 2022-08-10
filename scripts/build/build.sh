#!/bin/bash

set -e

###
### Timing: Functions
###
log_time_file="/opt/frsr-build/build-timing.log"
touch "$log_time_file"
cleanup () {
  echo "Durations:"
  cat "$log_time_file"

  echo "cleaning up..."
  rm -f "$log_time_file"
}
trap "{ cleanup; }" EXIT

log_time () {
  local label=$1
  local start=$2
  local end=$3

  local runtime=$((end-start))
  local hours=$((runtime / 3600))
  local minutes=$(( (runtime % 3600) / 60 ))
  local seconds=$(( (runtime % 3600) % 60 ))
  echo "${label}='${hours}h ${minutes}m ${seconds}s'" >> "$log_time_file"
}



###
### Timing: script
###
starttime_script=`date +%s`

# validation
if [ -z "$APP_VERSION" ]; then
  echo "Missing required env variable: APP_VERSION"
  exit 1
fi

if [ -z "$APP_SUBPATH" ]; then
  export APP_SUBPATH="react"
fi


# Where to unzip the contents to do the build
BUILD_CONTENTS_DIRECTORY="/buildcontents"
mkdir -p "$BUILD_CONTENTS_DIRECTORY"

# Generate Next Bulid ID if using build-manager mode
if [ -n "${BUILD_MANAGER_MODE}" ] ; then
  export NEXT_BUILD_ID=$(< /proc/sys/kernel/random/uuid)
  echo "Next Build ID is ${NEXT_BUILD_ID}"
  # Base build only (no pages) if manager mode
  export PAGE_DATA='{"pages":[]}'
fi

###
### Pull the contents from s3
###
ZIP_CONTENTS_PATH="$BUILD_CONTENTS_DIRECTORY/contents.zip"
if [ -n "$S3_BUCKET_CONTENTS" ]; then
  starttime_s3_pull=`date +%s`
  S3_PATH_PREFIX_CONTENTS="${APP_SUBPATH}/${APP_VERSION}"
  S3_FULL_PATH_CONTENTS="$S3_BUCKET_CONTENTS/${S3_PATH_PREFIX_CONTENTS}/contents.zip"

  echo "pull contents from s3"
  echo "S3_BUCKET_CONTENTS: $S3_BUCKET_CONTENTS"
  echo "S3_PATH_PREFIX_CONTENTS: $S3_PATH_PREFIX_CONTENTS"
  echo "S3_FULL_PATH_CONTENTS: $S3_FULL_PATH_CONTENTS"
  aws s3 cp s3://$S3_FULL_PATH_CONTENTS "$ZIP_CONTENTS_PATH"
  endtime_s3_pull=`date +%s`
  log_time "s3_pull" $starttime_s3_pull $endtime_s3_pull
fi

if [ -f "$ZIP_CONTENTS_PATH" ]; then
  ###
  ### Unzip the contents
  ###
  starttime_unzip=`date +%s`
  echo "extract the contents of contents.zip..."
  unzip -q "$ZIP_CONTENTS_PATH" -d "$BUILD_CONTENTS_DIRECTORY"
  echo "extract the contents of contents.zip...Done"
  if [ -z "$SKIP_REMOVE_CONTENTS_ZIP" ]; then
    rm "$ZIP_CONTENTS_PATH"
  fi
  endtime_unzip=`date +%s`
  log_time "unzip" $starttime_unzip $endtime_unzip
fi

###
### Run the build
###
starttime_build=`date +%s`
echo "run the build"
if [ -n "$PAGE_DATA" ]; then
  echo "==="
  echo "PAGE_DATA provided:"
  echo "$PAGE_DATA"
  echo "==="
elif [ -n "$S3_FULL_PATH_SLUG_SLICE_FILE" ]; then
  echo "S3_FULL_PATH_SLUG_SLICE_FILE provided. Fetching PAGE_DATA from s3"
  echo "$S3_FULL_PATH_SLUG_SLICE_FILE"

  SLUG_SLICE_FILE="page-slugs.json"
  aws s3 cp s3://$S3_FULL_PATH_SLUG_SLICE_FILE "$SLUG_SLICE_FILE"
  export PAGE_DATA=$(cat "$SLUG_SLICE_FILE")
  echo "==="
  echo "PAGE_DATA:"
  echo "$PAGE_DATA"
  echo "==="
fi

cd "$BUILD_CONTENTS_DIRECTORY"

if [ -f "$BUILD_CONTENTS_DIRECTORY/scripts/build.sh" ]; then
  echo "scripts/build.sh found."

  PAGE_DATA="$PAGE_DATA" \
  BUILD_CONTENTS_DIRECTORY="$BUILD_CONTENTS_DIRECTORY" \
  bash +x "$BUILD_CONTENTS_DIRECTORY/scripts/build.sh"
else
  echo "scripts/build.sh not found. Running 'npm run build'"
  npm run build
fi
endtime_build=`date +%s`
log_time "build" $starttime_build $endtime_build

###
### PUBLISH to s3
###
if [ -n "$PUBLISH_S3_BUCKET" ]; then
  starttime_s3_publish=`date +%s`
  BUILD_DIRECTORY="$BUILD_CONTENTS_DIRECTORY/$BUILD_OUTPUT_SUBDIRECTORY"
  mkdir -p "$BUILD_DIRECTORY"
  if [ -n "APP_SUBPATH_PUBLISH_SUFFIX" ]; then
    APP_SUBPATH="${APP_SUBPATH}${APP_SUBPATH_PUBLISH_SUFFIX}"
  fi
  S3_PATH_PREFIX="${APP_SUBPATH}/${APP_VERSION}"
  S3_FULL_PATH="$PUBLISH_S3_BUCKET/${S3_PATH_PREFIX}"

  echo "push to s3:"
  echo "BUILD_DIRECTORY: $BUILD_DIRECTORY"
  echo "PUBLISH_S3_BUCKET: $PUBLISH_S3_BUCKET"
  echo "S3_PATH_PREFIX: $S3_PATH_PREFIX"
  echo "S3_FULL_PATH: $S3_FULL_PATH"
  echo "S3_SYNC_EXTRA_FLAGS_BUILD_MANAGER: $S3_SYNC_EXTRA_FLAGS_BUILD_MANAGER"
  echo "S3_SYNC_EXTRA_FLAGS_CHILD_CONTAINERS: $S3_SYNC_EXTRA_FLAGS_CHILD_CONTAINERS"
  
  # ONLY Build manager mode should use --delete to clear our previous builds
  if [ -n "${BUILD_MANAGER_MODE}" ] ; then
    echo "Manager Mode: Removing old content and syncing with cloud"
    if [ -n "${BUILD_MANAGER_MODE_VERBOSE_S3_SYNC}" ]; then
      aws s3 sync $BUILD_DIRECTORY s3://$S3_FULL_PATH --delete $S3_SYNC_EXTRA_FLAGS_BUILD_MANAGER
    else
      aws s3 sync $BUILD_DIRECTORY s3://$S3_FULL_PATH --delete --quiet $S3_SYNC_EXTRA_FLAGS_BUILD_MANAGER
    fi
  else
    aws s3 sync $BUILD_DIRECTORY s3://$S3_FULL_PATH $S3_SYNC_EXTRA_FLAGS_CHILD_CONTAINERS
  fi

  endtime_s3_publish=`date +%s`
  log_time "s3_publish" $starttime_s3_publish $endtime_s3_publish
fi

###
### Run build manager
###
if [ -n "${BUILD_MANAGER_MODE}" ] && [ -f "/opt/frsr-build/scripts/build/manager-build.sh" ]; then
  starttime_buildmanager=`date +%s`
  echo "scripts/manager-build.sh found and build manager mode enabled."
  APP_SUBPATH="$APP_SUBPATH" \
  BUILD_CONTENTS_DIRECTORY="$BUILD_CONTENTS_DIRECTORY" \
  bash +x "/opt/frsr-build/scripts/build/manager-build.sh"
  echo "Build mode done exiting."
  endtime_buildmanager=`date +%s`
  log_time "buildmanager" $starttime_buildmanager $endtime_buildmanager
else
  echo "Skip build manager. Running build."
fi


###
### Clear CloudFront cache (if distro ID provided & build-manager succeeded )
###
if [ -n "$CLOUDFRONT_DISTRIBUTION_ID" ] && [ -n "${BUILD_MANAGER_MODE}" ]; then
  starttime_invalidate_cloudfront_cache=`date +%s`
  echo "Invalidate Cloudfront Cache (distribution-id=$CLOUDFRONT_DISTRIBUTION_ID)"

  if [ -z "$CLOUDFRONT_DISTRIBUTION_INVALIDATION_PATHS" ]; then
    CLOUDFRONT_DISTRIBUTION_INVALIDATION_PATHS="/*"
  fi

  CLOUDFRONT_INVALIDATION_RESPONSE="$(aws cloudfront create-invalidation --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" --paths "${CLOUDFRONT_DISTRIBUTION_INVALIDATION_PATHS}")"
  echo "$CLOUDFRONT_INVALIDATION_RESPONSE"
  endtime_invalidate_cloudfront_cache=`date +%s`
  log_time "invalidate_cloudfront" $starttime_invalidate_cloudfront_cache $endtime_invalidate_cloudfront_cache

  starttime_invalidate_cloudfront_wait=`date +%s`
  CLOUDFRONT_INVALIDATION_ID="$(echo "$CLOUDFRONT_INVALIDATION_RESPONSE" | jq -r ".Invalidation.Id" )"
  # https://docs.aws.amazon.com/cli/latest/reference/cloudfront/wait/invalidation-completed.html
  # wait for cloudfront invalidation to complete
  echo "Wait for invalidation to complete (invalidation-id="$CLOUDFRONT_INVALIDATION_ID")"
  aws cloudfront wait invalidation-completed \
  --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
  --id "$CLOUDFRONT_INVALIDATION_ID"
  endtime_invalidate_cloudfront_wait=`date +%s`
  log_time "invalidate_cloudfront_wait" $starttime_invalidate_cloudfront_wait $endtime_invalidate_cloudfront_wait

fi



###
### Timing: script
###
endtime_script=`date +%s`
log_time "script" $starttime_script $endtime_script


echo "Done"
