#!/bin/sh
# To avoid error:
#Flag --tojson has been deprecated, please use -o=json instead
#Error: parsing expression: Lexer error: could not match text starting at 1:1 failing at 1:1.
#        unmatched text: "r"
# Do steps from
# https://github.com/mikefarah/yq/issues/973
yq e $SCRIPT_DIR/lab-1/repo-conf-creation-main.yaml -o=j -I=0 |  jq -r '.[]|keys[]' |
while read -r repo_id; do
    curl -X PUT $JFROG_PLATFORM_HTTP_PROTOCOL://$JFROG_PLATFORM/access/api/v1/projects/_/share/repositories/$repo_id/su115 -H "accept: application/json" -H "Authorization: Bearer ${token}"
done