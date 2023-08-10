#!/bin/bash


/opt/netlogo/netlogo-headless.sh \
    --model /code/CHIME.nlogo \
    --experiment $1 \
    --table /srv/chime-output.csv \
    --threads 20

