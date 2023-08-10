#!/bin/bash

BEHAVIOR_SPACE_EXPERIMENT=${1:-osg_experiment_short}


/opt/netlogo/netlogo-headless.sh \
    --model /code/CHIME.nlogo \
    --experiment ${BEHAVIOR_SPACE_EXPERIMENT} \
    --table /srv/chime-output.csv \
    --threads 20

