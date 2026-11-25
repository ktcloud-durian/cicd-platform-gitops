#!/usr/bin/env bash
# 두리안뱅크 Secret 만들기 (값은 여기서 새로 만들고 저장소·채팅·노션에 남기지 않음, SEC-01)
# 사용: AWS_CTX=<AWS k3s kubectl 컨텍스트> ONPREM_CTX=<온프렘 k3s 컨텍스트> bash apps/durian-bank/make-secrets.sh
# - SERVICE_TOKEN은 web과 core-api가 같은 값을 써야 해서 한 번에 두 클러스터에 넣음
# - DB 비밀번호는 DB VM에서 만든 durian_app 비밀번호를 입력 (화면에 안 보임)
# - 시연 로그인 비밀번호(DEMO_PASSWORD)는 ~/.durian-bank-demo-password 에만 저장 (권한 600)
set -euo pipefail
: "${AWS_CTX:?AWS_CTX 가 필요해요}" "${ONPREM_CTX:?ONPREM_CTX 가 필요해요}"
umask 077
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
rand() { openssl rand -base64 64 | tr -d '\n/+=' | head -c 48; }

SERVICE_TOKEN=$(rand); JWT_SECRET=$(rand)
DEMO_PASSWORD=$(openssl rand -base64 18 | tr -d '\n/+=' | head -c 16)
read -rsp "durian_app DB 비밀번호: " DB_PASSWORD; echo
[[ ${#DB_PASSWORD} -ge 16 ]] || { echo "DB 비밀번호가 너무 짧아요 (16자 이상)"; exit 1; }

printf 'SERVICE_TOKEN=%s\nJWT_SECRET=%s\n' "$SERVICE_TOKEN" "$JWT_SECRET" > "$tmp/web.env"
printf 'SERVICE_TOKEN=%s\nDB_PASSWORD=%s\nDEMO_PASSWORD=%s\n' "$SERVICE_TOKEN" "$DB_PASSWORD" "$DEMO_PASSWORD" > "$tmp/core.env"

apply() { # 컨텍스트 이름 파일
  kubectl --context "$1" create namespace durian-bank --dry-run=client -o yaml | kubectl --context "$1" apply -f - >/dev/null
  kubectl --context "$1" -n durian-bank create secret generic "$2" --from-env-file="$3" --dry-run=client -o yaml \
    | kubectl --context "$1" apply -f - >/dev/null
  echo "OK: $1 / $2"
}
apply "$AWS_CTX" bank-web "$tmp/web.env"
apply "$ONPREM_CTX" bank-core-api "$tmp/core.env"

printf '%s\n' "$DEMO_PASSWORD" > ~/.durian-bank-demo-password
unset SERVICE_TOKEN JWT_SECRET DB_PASSWORD DEMO_PASSWORD
echo "시연 로그인 비밀번호: ~/.durian-bank-demo-password (아이디 kimfake). 다시 만들면 web·core-api 재시작: kubectl rollout restart deploy -n durian-bank"
