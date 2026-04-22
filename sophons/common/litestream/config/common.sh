set -xeuo pipefail

replica_url() {
  local db="${1:-}"

  if test -n "${LITESTREAM_BUCKET:-}"; then
    printf "s3://$LITESTREAM_BUCKET/$LITESTREAM_REPLICA_PATH/$db?endpoint=$LITESTREAM_ENDPOINT&region=${LITESTREAM_REGION:-}&force-path-style=true"
  else
    printf "file://$LITESTREAM_REPLICA_PATH/$db"
  fi
}

restored_flag_for() {
  local db_path="${1:?}"

  printf "$(dirname "$db_path")/.$(basename "$db_path").restored"
}

restore() {
  local db_path="${1:?}"
  local db_uri="${2:?}"
  local restored_flag="$(restored_flag_for "$db_path")"

  if test -z "${LITESTREAM_NO_RESTORE:-}"; then
    rm -f "$restored_flag"
    LITESTREAM_LOGGING_LEVEL=debug LITESTREAM_DB_PATH="$db_path" LITESTREAM_REPLICA_URL="$db_uri" \
      litestream restore -config=/etc/litestream/litestream.yaml \
      -if-replica-exists -if-db-not-exists "$db_path"

    touch "$restored_flag"
  fi

  if test -z "${LITESTREAM_NO_WALINIT:-}"; then
    # initialize db as litestream user if it doesn't exist
    # also try to validate that the db isn't corrupt
    sqlite3 "$db_path" "PRAGMA journal_mode=WAL; PRAGMA integrity_check;"
  fi
}

is_restore_complete() {
  local db_path="${1:?}"
  local restored_flag="$(restored_flag_for "$db_path")"

  if test -z "${LITESTREAM_NO_RESTORE:-}"; then
    [ -f "$restored_flag" ]
  fi
}

clear_restored_flag() {
  local db_path="${1:?}"
  local restored_flag="$(restored_flag_for "$db_path")"

  rm -f "$restored_flag"
}
