###############################################
#           Swampup 2021 - SU 115
###############################################

#TODO : 
#- Check how to generate an $ADMIN_USER bearer token via API (only way to make it work is to get it from UI)
#- Create repository with JFrog CLI (bonus)
#- Create a repositories within a project (no project key available in the repo template) >> check with product. What about the configuration of projects with the YAML? Same for JFrog CLI apparently
#- Check if JFrog CLI can still rotate user tokens
#- Check how we can increment webservice version whenever we run a gradle build
#- How do we get the git commit with the JFrog CLI? We need to add it as a property

###############################################
#Prepare your local environment
###############################################
#keep your git directory in memory for latest command

# load environment variables
source .env

# Instanciate token
export token="Put your token here"

##############
## 1st Lab
##############

#create all with yaml configuration file
curl -u$ADMIN_USER:$ADMIN_PASSWORD -X PATCH https://$JFROG_PLATFORM/artifactory/api/system/configuration -T $SCRIPT_DIR/lab-1/repo-conf-creation-main.yaml

# Create project
curl -XPOST -H "Authorization: Bearer ${token}" -H 'Content-Type:application/json' https://$JFROG_PLATFORM/access/api/v1/projects -T ./lab-1/su115-project.json

# Sharing repositories in a project
# !! Pre-requisite : install yq and jq !!
$SCRIPT_DIR/lab-1/sharing-repositories.sh

# Adding builds to the Xray indexing process
curl -u$ADMIN_USER:$ADMIN_PASSWORD -X POST -H "content-type: application/json"  https://$JFROG_PLATFORM/xray/api/v1/binMgr/builds -T $SCRIPT_DIR/xray/indexed-builds.json

##############
## 2nd Lab
##############

# Configure CLI
jfrog config add swampup115 --artifactory-url=https://$JFROG_PLATFORM/artifactory --dist-url=https://$JFROG_PLATFORM/distribution --user=$ADMIN_USER --password=$ADMIN_PASSWORD --interactive=false

# Make it default
jfrog config use swampup115

# CD into the java src code folder 
cd $SCRIPT_DIR/back/src

# Configure cli for gradle
# Todo disable ivy descriptors
jfrog rt gradlec --repo-resolve=app-gradle-virtual --server-id-resolve=swampup115 --repo-deploy=app-gradle-virtual --deploy-ivy-desc=false --server-id-deploy=swampup115

jfrog rt gradlec --repo-resolve=app-gradle-virtual --server-id-resolve=swampup115 --repo-deploy=app-gradle-virtual --server-id-deploy=swampup115

# Changing permissions on the gradle-wrapper
gradle wrapper --gradle-version 6.8.3 --distribution-type all

# run build
# during the build, explain why it is important to refresh dependencies and more globally to avoid dependency caching on the client side 
jfrog rt gradle "clean artifactoryPublish -b build.gradle --info --refresh-dependencies" --build-name=gradle-su-115 --build-number=$BUILD_NUMBER

# build info
jfrog rt bp gradle-su-115 $BUILD_NUMBER

jfrog rt bs gradle-su-115 $BUILD_NUMBER

# Searching build artifacts
jfrog rt s "app-gradle-virtual/" --build=gradle-su-115/$BUILD_NUMBER

# Find the build artifacts from the latest build
jfrog rt s "app-gradle-virtual/" --build=gradle-su-115

# tagging the build with properties
jfrog rt sp "app-gradle-virtual/*" "maintainer=hza;stage=dev;appnmv=$APP_ID/$APP_VERSION" --build=gradle-su-115/$BUILD_NUMBER

# Find the webservice.war from the latest build (using filespec)
jfrog rt s --spec $SCRIPT_DIR/lab-2/latest-webservice.json

# Find the webservice.war from the latest build (using CLI search pattern)
jfrog rt s 'app-gradle-virtual/*/webservice*.war' --build=gradle-su-115

# Find the gradle build dependencies
jfrog rt s --spec="${SCRIPT_DIR}/lab-2/filespec-aql-dependency-search-gradle.json" --spec-vars="build-name=gradle-su-115;build-number=$BUILD_NUMBER"

#Test run and promote ?
jfrog rt bpr gradle-su-115 $BUILD_NUMBER app-gradle-rc-local --status='release candidate' --comment='webservice is now release candidate' --copy=true --props="maintainer=hza;stage=staging"

# Find all files from that build that were promoted to staging
jfrog rt s "app-gradle-virtual/*" --props="stage=staging" --build=gradle-su-115/$BUILD_NUMBER

# Docker App Build
# Updating dockerfile with JFrog Platform URL
cd $SCRIPT_DIR/back/CI/Docker

# TODO (Windows compliant)
sed "s/registry/${JFROG_PLATFORM}\/app-docker-virtual/g" jfrog-Dockerfile > Dockerfile

# Reading the docker file and identifying the base image
# TODO

# Pull fhe base image >> TO DO Change the base image in the CLI command
# temporary workaround : the base image is statically pulled via the JFrog CLI
jfrog rt dpl ${JFROG_PLATFORM}/app-docker-virtual/bitnami/tomcat:latest app-docker-virtual --build-name=docker-su-115 --build-number=$BUILD_NUMBER --module=app

# Download war file dependency
jfrog rt dl "app-gradle-virtual/*/webservice*.war" war/ --props="stage=staging" --build=gradle-su-115/$BUILD_NUMBER --build-name=docker-su-115 --build-number=$BUILD_NUMBER --module=java-app --flat=true

# Run docker build
docker build . -t $JFROG_PLATFORM/app-docker-virtual/jfrog-docker-app:$BUILD_NUMBER  -f Dockerfile --build-arg REGISTRY=$JFROG_PLATFORM/app-docker-virtual --build-arg BASE_TAG=$BUILD_NUMBER

# Push the image
# Present a slideck during the docker push (this can take several minutes)
jfrog rt dp $JFROG_PLATFORM/app-docker-virtual/jfrog-docker-app:$BUILD_NUMBER app-docker-virtual --build-name=docker-su-115 --build-number=$BUILD_NUMBER --module=app

# Publish the docker build
jfrog rt bp docker-su-115 $BUILD_NUMBER

#Searching for the base image of my docker build
## what base image has been used
# TODO Check if we can ouput the docker images name + tag
jfrog rt s --spec="${SCRIPT_DIR}/lab-2/filespec-aql-dependency-search.json" --spec-vars="build-name=docker-su-115;build-number=$BUILD_NUMBER"

#Promote the docker build to release candidate
jfrog rt bpr docker-su-115 $BUILD_NUMBER app-docker-rc-local --status="release candidate" --copy=true --props="maintainer=hza;stage=staging;appnmv=$APP_ID/$APP_VERSION"


#helm
# cd into helm chart repo
cp -r $SCRIPT_DIR/docker-app-chart-template $SCRIPT_DIR/docker-app-chart
cd $SCRIPT_DIR/docker-app-chart

sed -ie 's/0.1.1/0.1.'"$BUILD_NUMBER"'/' ./Chart.yaml
sed -ie 's/latest/'"$IMAGE_TAG"'/g' ./values.yaml

jfrog rt bce helm-su-115 $BUILD_NUMBER

# Reference the docker image as helm build dependency
# Important: to do > fetch from virtual, filter based on application name and version
jfrog rt dl app-docker-virtual/jfrog-docker-app/$IMAGE_TAG/manifest.json --build-name=helm-su-115 --build-number=$BUILD_NUMBER --module=app

# package the helm chart 
helm package .

# upload the helm chart
jfrog rt u 'docker-app-chart-*.tgz' app-helm-virtual --build-name=helm-su-115 --build-number=$BUILD_NUMBER --module=app

# publish the helm build
jfrog rt bp helm-su-115 $BUILD_NUMBER

# promoting the helm build 
jfrog rt bpr helm-su-115 $BUILD_NUMBER app-helm-rc-local --status="release candidate" --copy=true --props="maintainer=hza;stage=staging;appnmv=$APP_ID/$APP_VERSION"

## Promoting the docker build
# Assign a property 
    # maintainer
    # stage (Prod)
    # app/version (will be used to attach the right image to the helm build info)
jfrog rt bpr docker-su-115 $BUILD_NUMBER app-docker-prod-local --status=released --comment='prod ready aplication' --copy=true --props="maintainer=hza;stage=prod;appnmv=$APP_ID/$APP_VERSION"

#Test run and promote ?
jfrog rt bpr gradle-su-115 $BUILD_NUMBER app-gradle-prod-local --status=released --comment='prod ready aplication' --copy=true --props="maintainer=hza;stage=prod;appnmv=$APP_ID/$APP_VERSION"

# promoting the helm build 
jfrog rt bpr helm-su-115 $BUILD_NUMBER app-helm-prod-local --status=released --comment='prod ready aplication' --copy=true --props="maintainer=hza;stage=prod;appnmv=$APP_ID/$APP_VERSION"

#Security
# Trigger an Xray scan of your docker build
jfrog rt bs docker-su-115 $BUILD_NUMBER

# What did you get as a result?
#[Info] Triggered Xray build scan... The scan may take a few minutes.
#[Info] Xray scan completed.
# {
  #"summary": {
    #"total_alerts": 0,
    #"fail_build": false,
    #"message": "No Xray “Fail build in case of a violation” policy rule has been defined on this build. The Xray scan will run in parallel to the deployment of the build and will not obstruct the build. To review the Xray scan results, see the Xray Violations tab in the UI.",
    #"more_details_url": ""
  #},
  #"alerts": [],
  #"licenses": []
#}

# it's the right time to create your security policies and watches
curl -u$ADMIN_USER:$ADMIN_PASSWORD -X POST -H "content-type: application/json"  https://$JFROG_PLATFORM/xray/api/v1/policies -T $SCRIPT_DIR/xray/security-policy.json
curl -u$ADMIN_USER:$ADMIN_PASSWORD -X POST -H "content-type: application/json"  https://$JFROG_PLATFORM/xray/api/v1/policies -T $SCRIPT_DIR/xray/license-policy.json
curl -u$ADMIN_USER:$ADMIN_PASSWORD -X POST -H "content-type: application/json"  https://$JFROG_PLATFORM/xray/api/v2/watches -T $SCRIPT_DIR/xray/watch.json

# Let's run the build scan again
jfrog rt bs docker-su-115 $BUILD_NUMBER

# Let's run it once again without enforcement
jfrog rt bs docker-su-115 $BUILD_NUMBER --fail=false

# Distribution 

# Before creating the release bundle, ask the attendees to think about the appropriate AQL query
# test the AQL
jfrog rt s --spec=$SCRIPT_DIR/distribution/rb-spec-prop-prom-based.json --spec-vars="app-id=$APP_ID;app-version=$APP_VERSION"

# Release bundle creation
jfrog rt rbc $APP_ID $APP_VERSION --spec=$SCRIPT_DIR/distribution/rb-spec-prop-prom-based.json --spec-vars="app-id=$APP_ID;app-version=$APP_VERSION"

# Release bundle signing 
jfrog rt rbs $APP_ID $APP_VERSION

# Add release bundle to Xray indexing
# DO IT manually (no API for that)

# Add release bundle to Project
# DO IT manually (no API for that)

#need to create target repositories for distribution on edge
#create all with yaml configuration file
curl -u$ADMIN_USER:$ADMIN_PASSWORD -X PATCH https://$JFROG_EDGE/artifactory/api/system/configuration -T $SCRIPT_DIR/lab-1/repo-conf-creation-edge.yaml

# Edit $SCRIPT_DIR/distribution/dist-rules.json and specify the edge site name

# Release bundle Distribution
jfrog rt rbd $APP_ID $APP_VERSION --dist-rules=$SCRIPT_DIR/distribution/dist-rules.json

# Release bundle Distribution relying on a site pattern
jfrog rt rbd $APP_ID $APP_VERSION --site="*edge*"

# How can we track the progress?
curl -u$ADMIN_USER:$ADMIN_PASSWORD -X GET https://$JFROG_PLATFORM/distribution/api/v1/release_bundle/$APP_ID/$APP_VERSION/distribution | jq
