
set -e
set -x
image_name=$1
tag_name=$2
docker login ${DOCKER_REGISTRY} -u ${JFROG_USERNAME} -p ${JFROG_TOKEN}
docker build -t ${image_name}:${tag_name} .
docker tag ${image_name}:${tag_name} ${DOCKER_REGISTRY}/build-images/${image_name}:${tag_name}
docker push ${DOCKER_REGISTRY}/build-images/${image_name}:${tag_name}
          
