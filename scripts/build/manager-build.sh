#!/bin/bash

# Set defaults if not provided
[ -z "${RETRY_LIMIT}" ] && RETRY_LIMIT=3
[ -z "${RETRY_SLEEP}" ] && RETRY_SLEEP=5
[ -z "${SLUG_PER_CONTAINER}" ] && SLUG_PER_CONTAINER=3

if [ -f "$BUILD_CONTENTS_DIRECTORY/scripts/catalog/fetch.sh" ]; then
    echo "Calling the fetch the catalog script ($BUILD_CONTENTS_DIRECTORY/scripts/catalog/fetch.sh)..."
    bash +x $BUILD_CONTENTS_DIRECTORY/scripts/catalog/fetch.sh > slugs.json
else
    echo "Catalog fetch script not provided."
    echo "Provide a file in the app: scripts/catalog/fetch.sh"
    echo "the file should output JSON with the following format: { \"pages\": [] }"
    exit 1
fi

echo "Fetched the pages..."
cat slugs.json


# Decide container count & page per container
slug_count=`jq '[.pages[]] | length' slugs.json`
# slug_count=`jq length slugs.json`
if ! [[ ${slug_count} =~ ^[0-9]+$ ]] ; then
   echo "error: slug_count not a number" >&2
   exit 1
fi

# Contianer count needs to be rounded to ceiling, to ensure it includes all slugs
container_count=$(( (${slug_count} / ${SLUG_PER_CONTAINER}) + (${slug_count} % ${SLUG_PER_CONTAINER} > 0 ) ))

# Execute containers & provide container array of slugs to build
array_start=0
array_end=$(((${array_start} + ${SLUG_PER_CONTAINER})))

# Limit container | config container count limit
container_ids=()
container_data=()

for (( c=0; c<${container_count}; c++))
do
    slug_slice=""
    # echo "DEBUG: Contianer#: ${c}, start: ${array_start}, end ${array_end}";
    if [ -e slugs.json ]
        then
            # Output as text so json is not evaluated by the AWS CLI
            slug_slice=$(jq "{pages: .pages[${array_start}:${array_end}]} | @text" slugs.json)

            # TODO: test index out of range
            array_start="$((${array_end}))"
            array_end="$((${array_start} + ${SLUG_PER_CONTAINER}))"
        else
            echo "DEBUG: slugs.json not found"
            exit 1
    fi

    # Set run-task overrides for child tasks, i.e. env vars
    read -r -d '' task_overrides <<EOF
    {
        "containerOverrides": [{
            "name": "${CONTAINER_OVERRIDE_NAME}",
            "environment": [{
                "name": "APP_VERSION",
                "value": "${APP_VERSION}"
            },{
                "name": "PAGE_DATA",
                "value": ${slug_slice}
            },{
                "name": "CONTENTFUL_SPACE_ID",
                "value": "${CONTENTFUL_SPACE_ID}"
            },{
                "name": "CONTENTFUL_ACCESS_TOKEN",
                "value": "${CONTENTFUL_ACCESS_TOKEN}"
            },{
                "name": "APP_SUBPATH",
                "value": "${APP_SUBPATH}"
            },{
                "name": "S3_BUCKET_CONTENTS",
                "value": "${S3_BUCKET_CONTENTS}"
            },{
                "name": "APP_SUBPATH_PUBLISH_SUFFIX",
                "value": "${APP_SUBPATH_PUBLISH_SUFFIX}"
            },{
                "name": "PUBLISH_S3_BUCKET",
                "value": "${PUBLISH_S3_BUCKET}"
            },{
                "name": "BUILD_OUTPUT_SUBDIRECTORY",
                "value": "${BUILD_OUTPUT_SUBDIRECTORY}"
            },{
                "name": "CLOUDFRONT_DISTRIBUTION_ID",
                "value": "${CLOUDFRONT_DISTRIBUTION_ID}"
            },{
                "name": "BUILD_OUTPUT_SUBDIRECTORY",
                "value": "${BUILD_OUTPUT_SUBDIRECTORY}"
            },{
                "name": "NEXT_BUILD_ID",
                "value": "${NEXT_BUILD_ID}"
            }]
        }]
    }
EOF

    echo "Executing container build."
    echo " NEXT_BUILD_ID: ${NEXT_BUILD_ID}"
    echo " APP_VERSION: ${APP_VERSION}"
    echo " slug_slice: ${slug_slice}"

    # TODO: Call multiple containers at the same time

    ## RUN TASK & EXTRACT ID
    run_task_result=$(aws ecs run-task \
    --cluster="${ECS_CLUSTER_NAME}" \
    --task-definition="${TASK_DEFINITION}" \
    --launch-type="FARGATE" \
    --network-configuration="${ECS_NETWORK_CONFIG}" \
    --overrides="${task_overrides}" \
    --tags='key=Name,value=frsr-build-ecs-td')

    task_id=$(jq -r '.tasks[0].containers[0].taskArn' <<< ${run_task_result} | cut -d"/" -f 3)

    # IF NOT TASK ID ERROR | maybe additional checks needed
    if ! [[ ${task_id} =~ ^[a-zA-Z0-9]+$ ]] || [[ ${task_id} == "undefined" ]] ; then
        echo "debug: Task ID: ${task_id}"
        echo "error: task_id not valid" >&2
        exit 1
    fi

    echo "Task ID: ${task_id}"

    container_ids+=("${task_id}")
    container_data+=("${slug_slice}")

done

echo "Allowing 1 minute for the tasks to execute"
sleep 60

echo "Sleep ${RETRY_SLEEP} minutes, Retry ${RETRY_LIMIT} times, MaxTimeOut $((${RETRY_LIMIT} * ${RETRY_SLEEP})) minutes"

# TODO: implement use to track successful tasks and failed tasks
success_array=()
fail_array=()

echo "Determining task statuses..."
# Determine task statuses
for (( r=1; r<$(( ${RETRY_LIMIT} + 1 )); r++ ))
do
    echo "DEBUG: Retry: ${r}, Limit: ${RETRY_LIMIT}, Sleep: ${RETRY_SLEEP}"

    # Wait for task to execute 
    sleep $((${RETRY_SLEEP} * 60))

    # Create json array of the container IDs
    task_arr=$(printf '%s\n' "${container_ids[@]}" | jq -R . | jq -s .)

    ecs_tasks_status=$(aws ecs describe-tasks \
    --cluster="${ECS_CLUSTER_NAME}" \
    --tasks="${task_arr}")

    ecs_tasks_status_parsed=$(jq -r '[.tasks[] | {lastStatus: .lastStatus, taskArn: .taskArn, exitCode: .containers[].exitCode}]' <<< ${ecs_tasks_status})

    container_done_count=0
    # TODO: retry failed tasks
    for task in $(jq -r '.[] | @text' <<< "${ecs_tasks_status_parsed}")
    do
        task_arn=$(jq -r '.taskArn' <<< ${task})
        task_last_status=$(jq -r '.lastStatus' <<< ${task})
        task_exit_code=$(jq -r '.exitCode' <<< ${task})

        echo "Task ${task_arn} state is ${task_last_status} with exit code ${task_exit_code}"

        # If task stopped increase counter & review container exit code.
        if [[ "${task_last_status}" == "STOPPED" ]] ; then
            ((container_done_count+=1))

            # Handle failed tasks
            if [[ "${task_exit_code}" -ne 0 ]] ; then
            fail_array+=(${task_arn})
            # TODO: track failed and succeded tasks (Array?)
                echo $"Task ${task_arn} exited with exit code ${task_exit_code}"
                exit 1
            fi
        fi
    done

    # Determine if all containers exited
    if [[ ${container_done_count} -eq ${container_count} ]] ; then
        echo "All tasks completed successfully."
        exit 0
    fi

done
