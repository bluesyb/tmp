#!/bin/bash

# =============================================================================
# INPUT - 환경에 맞게 수정
# =============================================================================
BASE_URL="http://localhost:8085"
API_KEY="your-api-key"

PROJECT_KEY="NBSSCM"
ISSUE_KEY="NBSSCM-1234"
VERSION_NAME="R1.3.d260301"
OLD_VERSION="R1.3.d260220"
DATE_FROM="2026-05-01"
DATE_TO=$(date +%Y-%m-%d)
REPO_NAME="NBSS-CDMAP-PO"
COMPONENT="NBSS-CDMAP-PO"
ISSUE_KEY_1="NBSSCM-524262"
ISSUE_KEY_2="NBSSCM-524263"
SVN_TAG_URL_OLD="http://svn.server/svn/NBSS-CDMAP-PO/tags/R1.3.d260220_20260220_1530"
SVN_TAG_URL_NEW="http://svn.server/svn/NBSS-CDMAP-PO/tags/R1.3.d260301_20260317_1748"
CP_ISSUE_KEY="NBSSCM-524262"
SVN_REPO_URL="http://svn.server/svn/NBSS-CDMAP-PO/trunk"
SVN_REVISION=12345
# =============================================================================

H_API="X-API-Key: $API_KEY"
H_JSON="Content-Type: application/json"
PASS=0
FAIL=0

run() {
  local label="$1"
  local status
  shift
  echo ""
  echo "▶ $label"
  status=$(eval "$@" -o /dev/null -w "%{http_code}" -s)
  if [[ "$status" =~ ^2 ]]; then
    echo "  ✔ HTTP $status"
    PASS=$((PASS+1))
  else
    echo "  ✘ HTTP $status"
    FAIL=$((FAIL+1))
  fi
}

run_body() {
  local label="$1"
  local tmpfile code body
  shift
  echo ""
  echo "▶ $label"
  tmpfile=$(mktemp)
  code=$(eval "$@" -s -o "$tmpfile" -w "%{http_code}")
  body=$(cat "$tmpfile")
  rm -f "$tmpfile"
  if [[ "$code" =~ ^2 ]]; then
    echo "  ✔ HTTP $code"
    echo "$body" | python3 -m json.tool 2>/dev/null | head -30
    PASS=$((PASS+1))
  else
    echo "  ✘ HTTP $code"
    echo "$body" | head -5
    FAIL=$((FAIL+1))
  fi
}

echo "=============================="
echo " cmagent API 테스트"
echo " BASE_URL : $BASE_URL"
echo "=============================="

# ------------------------------------------------------------------------------
# Health (인증 불필요)
# ------------------------------------------------------------------------------
echo ""
echo "[ Health ]"
run_body "GET /health" \
  "curl '$BASE_URL/health'"

# ------------------------------------------------------------------------------
# Issue
# ------------------------------------------------------------------------------
echo ""
echo "[ Issue ]"

run_body "GET /parsed/issue/{issueKey}/summary" \
  "curl -H '$H_API' '$BASE_URL/parsed/issue/$ISSUE_KEY/summary'"

run_body "GET /parsed/issue/{issueKey}" \
  "curl -H '$H_API' '$BASE_URL/parsed/issue/$ISSUE_KEY'"

run_body "GET /parsed/issue/{issueKey}/comment" \
  "curl -H '$H_API' '$BASE_URL/parsed/issue/$ISSUE_KEY/comment'"

run_body "POST /parsed/search" \
  "curl -X POST -H '$H_API' -H '$H_JSON' '$BASE_URL/parsed/search' \
    -d '{\"jql\":\"project = $PROJECT_KEY ORDER BY created DESC\",\"maxResults\":3}'"

# ------------------------------------------------------------------------------
# Version
# ------------------------------------------------------------------------------
echo ""
echo "[ Version ]"

run_body "GET /parsed/project/{projectKey}/versions (전체)" \
  "curl -H '$H_API' '$BASE_URL/parsed/project/$PROJECT_KEY/versions'"

run_body "GET /parsed/project/{projectKey}/versions (날짜 필터)" \
  "curl -H '$H_API' '$BASE_URL/parsed/project/$PROJECT_KEY/versions?from=$DATE_FROM&to=$DATE_TO'"

run_body "GET /parsed/project/{projectKey}/version/{versionName}/issues" \
  "curl -H '$H_API' '$BASE_URL/parsed/project/$PROJECT_KEY/version/$VERSION_NAME/issues?component=$COMPONENT'"

run_body "GET /parsed/project/{projectKey}/version/{versionName}/issues/ci" \
  "curl -H '$H_API' '$BASE_URL/parsed/project/$PROJECT_KEY/version/$VERSION_NAME/issues/ci'"

run_body "GET /parsed/project/{projectKey}/version/{versionName}/issues/deploy" \
  "curl -H '$H_API' '$BASE_URL/parsed/project/$PROJECT_KEY/version/$VERSION_NAME/issues/deploy'"

# ------------------------------------------------------------------------------
# Change Program
# ------------------------------------------------------------------------------
echo ""
echo "[ Change Program ]"

run_body "GET /parsed/project/{projectKey}/issues/change-program" \
  "curl -H '$H_API' '$BASE_URL/parsed/project/$PROJECT_KEY/issues/change-program?versionName=$VERSION_NAME'"

run "GET /parsed/project/{projectKey}/issues/change-program/csv" \
  "curl -H '$H_API' '$BASE_URL/parsed/project/$PROJECT_KEY/issues/change-program/csv?versionName=$VERSION_NAME' \
    -o change-program-$VERSION_NAME.csv"
echo "  → change-program-$VERSION_NAME.csv 저장됨"

run_body "POST /parsed/change-program/source-changes" \
  "curl -X POST -H '$H_API' -H '$H_JSON' '$BASE_URL/parsed/change-program/source-changes' \
    -d '{\"issue_keys\":[\"$ISSUE_KEY_1\",\"$ISSUE_KEY_2\"]}'"

run "POST /parsed/change-program/source-changes/csv" \
  "curl -X POST -H '$H_API' -H '$H_JSON' '$BASE_URL/parsed/change-program/source-changes/csv' \
    -d '{\"issue_keys\":[\"$ISSUE_KEY_1\",\"$ISSUE_KEY_2\"]}' \
    -o source-changes.csv"
echo "  → source-changes.csv 저장됨"

run_body "GET /parsed/change-program/issues (전체 검색, q 없음)" \
  "curl -H '$H_API' '$BASE_URL/parsed/change-program/issues?offset=0&limit=5'"

run_body "GET /parsed/change-program/issues (이슈키 검색)" \
  "curl -H '$H_API' '$BASE_URL/parsed/change-program/issues?q=$CP_ISSUE_KEY&limit=5'"

run_body "GET /parsed/change-program/issues (제목 검색)" \
  "curl -G -H '$H_API' --data-urlencode 'q=수정' '$BASE_URL/parsed/change-program/issues?limit=5'"

echo ""
echo "▶ GET /parsed/change-program/issues/{issueKey}/svn-commits"
COMMITS_JSON=$(curl -s -H "$H_API" "$BASE_URL/parsed/change-program/issues/$CP_ISSUE_KEY/svn-commits")
COMMITS_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "$H_API" "$BASE_URL/parsed/change-program/issues/$CP_ISSUE_KEY/svn-commits")
if [[ "$COMMITS_CODE" =~ ^2 ]]; then
  echo "  ✔ HTTP $COMMITS_CODE"
  echo "$COMMITS_JSON" | python3 -m json.tool 2>/dev/null | head -30
  PASS=$((PASS+1))
  # 첫 번째 커밋에서 revision과 svn_repo_url 자동 추출
  DYNAMIC_REVISION=$(echo "$COMMITS_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
commits = d.get('data', d).get('commits', [])
if commits: print(commits[0]['revision'])
" 2>/dev/null)
  DYNAMIC_REPO_URL=$(echo "$COMMITS_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
commits = d.get('data', d).get('commits', [])
if commits: print(commits[0]['svn_repo_url'])
" 2>/dev/null)
  if [[ -n "$DYNAMIC_REVISION" ]]; then
    SVN_REVISION=$DYNAMIC_REVISION
    echo "  → SVN_REVISION 자동 추출: $SVN_REVISION"
  fi
  if [[ -n "$DYNAMIC_REPO_URL" ]]; then
    SVN_REPO_URL=$DYNAMIC_REPO_URL
    echo "  → SVN_REPO_URL 자동 추출: $SVN_REPO_URL"
  fi
else
  echo "  ✘ HTTP $COMMITS_CODE"
  echo "$COMMITS_JSON" | head -5
  FAIL=$((FAIL+1))
fi

run_body "POST /parsed/change-program/svn-diff-revision (revision=$SVN_REVISION)" \
  "curl -X POST -H '$H_API' -H '$H_JSON' '$BASE_URL/parsed/change-program/svn-diff-revision' \
    -d '{\"revision\":$SVN_REVISION,\"svn_repo_url\":\"$SVN_REPO_URL\"}'"

# ------------------------------------------------------------------------------
# Release Diff
# ------------------------------------------------------------------------------
echo ""
echo "[ Release Diff ]"

run_body "GET /parsed/project/{projectKey}/version/{versionName}/job-tags" \
  "curl -H '$H_API' '$BASE_URL/parsed/project/$PROJECT_KEY/version/$VERSION_NAME/job-tags'"

run_body "GET /parsed/project/{projectKey}/version/{newVersion}/deploy-diff/{oldVersion}" \
  "curl -H '$H_API' '$BASE_URL/parsed/project/$PROJECT_KEY/version/$VERSION_NAME/deploy-diff/$OLD_VERSION'"

run_body "GET .../deploy-diff/{oldVersion}/repo/{repoName}?batch=false" \
  "curl -H '$H_API' '$BASE_URL/parsed/project/$PROJECT_KEY/version/$VERSION_NAME/deploy-diff/$OLD_VERSION/repo/$REPO_NAME?batch=false'"

run_body "POST /parsed/release/diff/preview" \
  "curl -X POST -H '$H_API' -H '$H_JSON' '$BASE_URL/parsed/release/diff/preview' \
    -d '{\"project_key\":\"$PROJECT_KEY\",\"prev_version\":\"$OLD_VERSION\",\"curr_version\":\"$VERSION_NAME\"}'"

run_body "POST /parsed/release/diff" \
  "curl -X POST -H '$H_API' -H '$H_JSON' '$BASE_URL/parsed/release/diff' \
    -d '{\"project_key\":\"$PROJECT_KEY\",\"prev_version\":\"$OLD_VERSION\",\"curr_version\":\"$VERSION_NAME\",\"component\":\"$COMPONENT\"}'"

run_body "POST /parsed/release/diff/stats" \
  "curl -X POST -H '$H_API' -H '$H_JSON' '$BASE_URL/parsed/release/diff/stats' \
    -d '{\"project_key\":\"$PROJECT_KEY\",\"prev_version\":\"$OLD_VERSION\",\"curr_version\":\"$VERSION_NAME\",\"component\":\"$COMPONENT\"}'"

# ------------------------------------------------------------------------------
# SVN
# ------------------------------------------------------------------------------
echo ""
echo "[ SVN ]"

run_body "POST /parsed/svn/diff" \
  "curl -X POST -H '$H_API' -H '$H_JSON' '$BASE_URL/parsed/svn/diff' \
    -d '{\"svnTagUrlOld\":\"$SVN_TAG_URL_OLD\",\"svnTagUrlNew\":\"$SVN_TAG_URL_NEW\"}'"

# ------------------------------------------------------------------------------
# 결과
# ------------------------------------------------------------------------------
echo ""
echo "=============================="
echo " 결과: ✔ $PASS 성공 / ✘ $FAIL 실패"
echo "=============================="
