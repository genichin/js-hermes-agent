#!/command/with-contenv sh
# shellcheck shell=sh
# 컨테이너 CMD 라우팅 — 공식 이미지의 main-wrapper.sh 시맨틱을 재현:
#   인자 없음                  → hermes (대화형 CLI)
#   첫 인자가 실행파일          → 그대로 실행 (sleep, bash, sh, …)
#   그 외                      → hermes <args> (예: `gateway run`)
#
# /init 이 CMD 를 실행하기 전에 env 를 비우므로 with-contenv 로 컨테이너
# ENV(PATH, HERMES_HOME 등)를 복원한다. root 로 시작한 경우 s6-setuidgid 로
# hermes 유저로 강등 후 실행.
set -e

drop() { [ "$(id -u)" = 0 ] && set -- s6-setuidgid hermes "$@"; exec "$@"; }

cd "${HERMES_HOME:-/opt/data}" 2>/dev/null || cd /

[ $# -eq 0 ] && drop hermes

if command -v "$1" >/dev/null 2>&1; then
    drop "$@"
fi

drop hermes "$@"
