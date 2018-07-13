#!/bin/bash
time docker run \
  --privileged \
  --rm \
  -v $PWD/linux-binary-final:/linux-binary-final \
  -v $PWD/linux-binary-rc:/linux-binary \
  -v $PWD:/concourse \
  -v $PWD/fly-final:/fly-final \
  -v $PWD/fly-rc:/fly-rc concourse/bin-testflight-ci \
  bash -c "set -x &&\
    export QUICKSTART=true && \
    export WEB_IP=127.0.0.1 &&  \
    export WEB_USERNAME=test && \
    export WEB_PASSWORD=test && \
    export PIPELINE_NAME=test-pipeline && \
    source concourse/src/github.com/concourse/bin/ci/start-bin && \
    prep && \
    start && \
    concourse/ci/scripts/create-uber-pipeline && \
    stop_server && \
    concourse/ci/scripts/manual-downgrade && \
    export CONCOURSE=/linux-binary-final/concourse_linux_amd64 && \
    start && \
    concourse/ci/scripts/verify-uber-pipeline"
