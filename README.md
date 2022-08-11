# Bitovi fast-react-static-renderer-build-image
Docker image to run fast-react-static-renderer builds

## Contents
- Python
- Node
- AWS CLI
- Chrome dependencies

## App expectations
Apps that are built with this image are expected to have the following:
- Zipped contents stored in S3
  - The files should exist in the following location: `$S3_BUCKET_CONTENTS/$APP_SUBPATH/$APP_VERSION/contents.zip`
  - The files should have `node_modules` built in (i.e. run `npm install` prior to zipping)
  - Zip the contents with symlinks (e.g. `zip --symlinks -r content.zip .`)
- Provide the following script: `scripts/catalog/fetch.sh`
  - This file should output files with the following format: `{ "pages": [] }`.  The output should be ONLY json (i.e. should not contain any other output)
  - The build manager will use this script to determine how to create child containers

  S3_PATH_PREFIX_CONTENTS="${APP_SUBPATH}/${APP_VERSION}"
  S3_FULL_PATH_CONTENTS="$S3_BUCKET_CONTENTS/${S3_PATH_PREFIX_CONTENTS}/contents.zip"

## App Build
The `scripts/build/build.sh` performs the following:
- Pull zip file from s3
- Unzip the zip contents
- Run the build
- Push the build results to a different s3 location
- invalidate the cloudfront cache if distribution id supplied

## Build Manager
The `scripts/build/manager-build.sh` performs the following.
- Determines how many ECS tasks to execute
- Executes build containers in ECS with paths for containers to build
- Monitors child containers

## Build Manager Diagram
![Build Manager Diagram](./DistributedStaticSiteGenerator.jpg?raw=true "Title")

### Running this container
To run the build, Start the container with the following environment variables:
- `AWS_ACCESS_KEY_ID`
  - Description: AWS access key id
- `AWS_SECRET_ACCESS_KEY`
  - Description: AWS secret access key
- `AWS_DEFAULT_REGION`
  - Description: AWS default region
- `APP_SUBPATH`
  - Description: Subpath in the s3 bucket (applies to both the contents zip and the final compiled files)
- `APP_SUBPATH_PUBLISH_SUFFIX`
  - Description: Used for testing. Adds a suffix to `APP_SUBPATH` 
- `APP_VERSION`
  - Description: Subpath under `APP_SUBPATH`. Generally applies to the version generated from the microservice (i.e. `latest`, `0.1.0`, branch-name, etc)
- `S3_BUCKET_CONTENTS`
  - Description: The s3 bucket that has the contents.zip
- `S3_SYNC_EXTRA_FLAGS_BUILD_MANAGER`
  - Description: additional flags to pass to the s3 sync command for the build manager (e.g. `--include='foo'`)
- `S3_SYNC_EXTRA_FLAGS_CHILD_CONTAINERS`
  - Description: additional flags to pass to the s3 sync command for the child containers (e.g. `--include='foo'`)
- `PUBLISH_S3_BUCKET`
  - Description: The s3 bucket to push the final compiled files to
- `BUILD_OUTPUT_SUBDIRECTORY`
  - Description: The subdirectory under the files directory (i.e. where the contents are unzipped to) to find the compiled files within this container.  For example, if the `npm run build` produces a directory next to the `package.json` called `out`, then this env var should be `out`
- `BUILD_USE_PAGE_DATA_FILE`
  - Description: If set, the `PAGE_DATA_FILE` file will contain the contents of the page data for child containers
- `CLOUDFRONT_DISTRIBUTION_ID`
  - Description: ID of a CloudFront distribution. If specified, the distribution will be invalidated after the contents have been published.
- `CLOUDFRONT_DISTRIBUTION_INVALIDATION_PATHS`
  - Description: Paths to invalidate in the given distribution id
  - Default: `/*`
- `BUILD_MANAGER_MODE`
  - Description: If set `scripts/build/manager-build.sh` will be executed to create child ECS tasks
  - Default: `1`
- `BUILD_MANAGER_MODE_VERBOSE_S3_SYNC`
  - Description: If set, build manager will not add the `--quiet` flag to the s3 sync command
  - Default: ``
- `SLUG_PER_CONTAINER`
  - Description: Number of containers each ECS task will build
- `RETRY_LIMIT`
  - Description: Number of times to check status of running ECS tasks.
- `RETRY_SLEEP`
  - Description: Minutes to wait between checking that status of running ECS tasks.
- `ECS_NETWORK_CONFIG`
  - Description: ECS network configuration, documented [here](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_NetworkConfiguration.html)
- `CONTAINER_OVERRIDE_NAME`
  - Description: ECS task container name for container override, documented [here](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_ContainerOverride.html)
- `NEXT_BUILD_ID`
  - Description: ID used by Next.js to match accross multiple builds/containers, documented [here](https://nextjs.org/docs/api-reference/next.config.js/configuring-the-build-id).

### Alternative app builds
The default build behavior is `npm run build`. If a different build script is needed, provide a bash file called `scripts/build.sh`, and that will be used instead.


## Running Locally (mount)
To run the build locally against a local app, first build the image:
```
docker build -t ecom-build-image:local .
```

Run the image:
```
docker run --rm --name ecom-build-image \
-e CONTENTFUL_SPACE_ID="1111111" \
-e CONTENTFUL_ACCESS_TOKEN="0000000" \
-e BUILD_OUTPUT_SUBDIRECTORY="relative/path/to/output" \
-e INCLUDE_PUPPETEER_LAUNCH_OPTIONS="1" \
-v /path/to/app:/buildcontents \
ecom-build-image:local
```

> **Note:** We are mounting the full path to the app to the `/buildcontents` directory in the container.

> **Note:** Add any additional env variables that the app's build process will need (e.g. `CONTENTFUL_SPACE_ID`, `CONTENTFUL_ACCESS_TOKEN`, and `INCLUDE_PUPPETEER_LAUNCH_OPTIONS`).

## Running Locally (S3 - advanced)
To have this container pull from and push to S3, you'll need the following:
- An AWS account with access to S3 and Cloudfront (if provided)
- A bucket with the zipped contents of the app
  - The bucket should have the following format: `<bucket>/<app_subpath>/<app_version>`
  - The contents of the app repo should be zipped into a file called `contents.zip` and placed into the directory (i.e. `<bucket>/<app_subpath>/<app_version>/contents.zip`)
- A bucket to store the final built resources
  - The bucket should have the following format: `<bucket>/<app_subpath><app_subpath_publish_suffix>/<app_version>`
- A Cloudfront distribution id if a CloudFront distribution invalidation is needed



Build the image:
```
docker build -t ecom-build-image:local .
```

Set environment variables:
```
AWS_ACCESS_KEY_ID="<your-aws-access-key-id>"
AWS_SECRET_ACCESS_KEY="<your-aws-secret-access-key>"
AWS_DEFAULT_REGION="<your-aws-region>"
S3_BUCKET_CONTENTS="<bucket-with-zip-contents>"
APP_SUBPATH="<path-in-s3-bucket>"
APP_SUBPATH_PUBLISH_SUFFIX="<suffix-for-app_subpath>"
APP_VERSION="<directory-under-app_subpath>"
PUBLISH_S3_BUCKET="<bucket-to-publish-final-contents>"
BUILD_OUTPUT_SUBDIRECTORY="<directory-with-build-contents>"
CLOUDFRONT_DISTRIBUTION_ID="<cloudfront distribution id>"
```

Run the image:
```
docker run --rm --name ecom-build-image \
-e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
-e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
-e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION}" \
-e S3_BUCKET_CONTENTS="${S3_BUCKET_CONTENTS}" \
-e APP_SUBPATH="${APP_SUBPATH}" \
-e APP_SUBPATH_PUBLISH_SUFFIX="${APP_SUBPATH_PUBLISH_SUFFIX}" \
-e APP_VERSION="${APP_VERSION}" \
-e PUBLISH_S3_BUCKET="${PUBLISH_S3_BUCKET}" \
-e BUILD_OUTPUT_SUBDIRECTORY="${BUILD_OUTPUT_SUBDIRECTORY}" \
-e CONTENTFUL_SPACE_ID="1111111" \
-e CONTENTFUL_ACCESS_TOKEN="0000000" \
-e INCLUDE_PUPPETEER_LAUNCH_OPTIONS="1" \
ecom-build-image:local
```

> **Note:** Add any additional env variables that the app's build process will need (e.g. `CONTENTFUL_SPACE_ID`, `CONTENTFUL_ACCESS_TOKEN`, and `INCLUDE_PUPPETEER_LAUNCH_OPTIONS`).

## Running Locally (Build Manager Mode - advanced)
To have this container run in manager mode, you'll need the following:
- All same requirements as S3 above
- The AWS account also needs access to ECS run-task & describe-task
- An ECR image & ECS task definition

Build the image:
```
docker build -t ecom-build-image:local .
```

Set environment variables:
```
BUILD_MANAGER_MODE=1
CONTAINER_OVERRIDE_NAME="myContainerName"
TASK_DEFINITION="arn:aws:ecs:us-east-1:123456789012:task/MyCluster/d789e94343414c25b9f6bd59eEXAMPLE"
ECS_CLUSTER_NAME="MyCluster"
ECS_NETWORK_CONFIG="awsvpcConfiguration={subnets=[string,string],securityGroups=[string,string],assignPublicIp=string}"
AWS_ACCESS_KEY_ID="<your-aws-access-key-id>"
AWS_SECRET_ACCESS_KEY="<your-aws-secret-access-key>"
AWS_DEFAULT_REGION="<your-aws-region>"
S3_BUCKET_CONTENTS="<bucket-with-zip-contents>"
APP_SUBPATH="<path-in-s3-bucket>"
APP_SUBPATH_PUBLISH_SUFFIX="<suffix-for-app_subpath>"
APP_VERSION="<directory-under-app_subpath>"
PUBLISH_S3_BUCKET="<bucket-to-publish-final-contents>"
BUILD_OUTPUT_SUBDIRECTORY="<directory-with-build-contents>"
CLOUDFRONT_DISTRIBUTION_ID="<cloudfront distribution id>"
```

Run the image:
```
docker run --rm --name ecom-build-image \
-e BUILD_MANAGER_MODE="${BUILD_MANAGER_MODE}" \
-e CONTAINER_OVERRIDE_NAME="${CONTAINER_OVERRIDE_NAME}" \
-e TASK_DEFINITION="${TASK_DEFINITION}" \
-e ECS_CLUSTER_NAME="${ECS_CLUSTER_NAME}" \
-e ECS_NETWORK_CONFIG="${ECS_NETWORK_CONFIG}" \
-e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
-e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
-e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION}" \
-e S3_BUCKET_CONTENTS="${S3_BUCKET_CONTENTS}" \
-e APP_SUBPATH="${APP_SUBPATH}" \
-e APP_SUBPATH_PUBLISH_SUFFIX="${APP_SUBPATH_PUBLISH_SUFFIX}" \
-e APP_VERSION="${APP_VERSION}" \
-e PUBLISH_S3_BUCKET="${PUBLISH_S3_BUCKET}" \
-e BUILD_OUTPUT_SUBDIRECTORY="${BUILD_OUTPUT_SUBDIRECTORY}" \
-e CONTENTFUL_SPACE_ID="1111111" \
-e CONTENTFUL_ACCESS_TOKEN="0000000" \
-e INCLUDE_PUPPETEER_LAUNCH_OPTIONS="1" \
ecom-build-image:local
```