# customize via `% make build OSG_USERNAME=<your-osg-username>` e.g., `% make build OSG_USERNAME=alee`
include config.mk

# user to connect to OSG as
OSG_USERNAME := ${OSG_USERNAME}
OSG_SUBMIT_NODE := osg
OSG_CONTAINER_FILEDIR := /ospool/PROTECTED
# name of this computational model, used as the namespace (for apptainer, Docker, and as a folder to keep things
# organized on the OSG filesystem login node). recommend that you use all lowercase alphanumeric with - or _ to
# separate words, e.g., chime-abm or spatial-rust-model
MODEL_NAME := chime-abm
# the directory (in the container) where the computational model source
# code or executable can be called, e.g., main.py | netlogo-headless.sh
MODEL_CODE_DIRECTORY := /code
# entrypoint script to be called by job-wrapper.sh
ENTRYPOINT_SCRIPT := run.sh
# the OSG output file to be transferred
OSG_OUTPUT_FILES :=
# OSG submit template
OSG_SUBMIT_TEMPLATE := scripts/submit.template
# the submit file to be executed on OSG via `condor_submit ${OSG_SUBMIT_FILE}`
OSG_SUBMIT_FILENAME := scripts/${MODEL_NAME}.sub

CONTAINER_DEF := container.def
CURRENT_VERSION := v1
APPTAINER_IMAGE_NAME = ${MODEL_NAME}-${CURRENT_VERSION}.sif

.PHONY: clean deploy docker-run apptainer-run docker-build apptainer-build all

all: build

$(APPTAINER_IMAGE_NAME):
	apptainer build --fakeroot ${APPTAINER_IMAGE_NAME} ${CONTAINER_DEF}

$(OSG_SUBMIT_FILENAME): $(OSG_SUBMIT_TEMPLATE)
	APPTAINER_IMAGE_NAME=${APPTAINER_IMAGE_NAME} \
	OSG_USERNAME=${OSG_USERNAME} \
	MODEL_CODE_DIRECTORY=${MODEL_CODE_DIRECTORY} \
	ENTRYPOINT_SCRIPT=${ENTRYPOINT_SCRIPT} \
	OUTPUT_FILES=${OSG_OUTPUT_FILES} \
	envsubst < ${OSG_SUBMIT_TEMPLATE} > ${OSG_SUBMIT_FILENAME}

docker-build: $(OSG_SUBMIT_FILENAME)
	docker build -t comses/${MODEL_NAME}:${CURRENT_VERSION} .

apptainer-build: $(CONTAINER_DEF) $(APPTAINER_IMAGE_NAME)

build: docker-build apptainer-build

clean:
	rm -f ${APPTAINER_IMAGE_NAME} ${OSG_SUBMIT_FILENAME} *~

deploy: build
	echo "IMPORTANT: This command assumes you have created an ssh alias in your ~/.ssh/config named '${OSG_SUBMIT_NODE}' that connects to your OSG connect node"
	echo "Copying apptainer image ${APPTAINER_IMAGE_NAME} to osg:${OSG_CONTAINER_FILEDIR}/${OSG_USERNAME}"
	rsync -avzP ${APPTAINER_IMAGE_NAME} ${OSG_SUBMIT_NODE}:${OSG_CONTAINER_FILEDIR}/${OSG_USERNAME}
	echo "Creating ${MODEL_NAME} folder in /home/${OSG_USERNAME}"
	ssh ${OSG_USERNAME}@${OSG_SUBMIT_NODE} "mkdir -p ${MODEL_NAME}"
	echo "Copying submit script, job script, and model-specific scripts in ./scripts/ to /home/${OSG_USERNAME}/${MODEL_NAME}"
	rsync -avzP scripts/ ${OSG_SUBMIT_NODE}:${MODEL_NAME}/

docker-run: docker-build
	docker run --rm comses/${MODEL_NAME}:${CURRENT_VERSION} /code/scripts/run.sh

apptainer-run: apptainer-build
	apptainer exec --bind ./apptainer-data:/srv --pwd /code ${APPTAINER_IMAGE_NAME} bash /code/scripts/run.sh
