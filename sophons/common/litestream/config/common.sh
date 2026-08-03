set -xeuo pipefail

TMPDIR="${TMPDIR:-/tmp}"
BASE_CONFIG_PATH="${LITESTREAM_BASE_CONFIG_PATH:-/etc/litestream/litestream.base.yaml}"
CONFIG_PATH="${LITESTREAM_CONFIG_PATH:-$TMPDIR/litestream.yaml}"

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

TEMPL_REGEX='\[\[replica_url( (.+))?\]\]'
render() {
  local line
  local arg
  local result
  while IFS= read -r line; do
    if grep -Eq "$TEMPL_REGEX" <<<"$line"; then
      arg="$(sed -E "s/.*$TEMPL_REGEX.*/\2/" <<<"$line")"
      result="$(replica_url "$arg")"
      result="$(sed 's/&/\\&/g' <<<"$result")"
      line=$(sed -E "s|$TEMPL_REGEX|$result|" <<<"$line")
    fi
    echo "$line"
  done
}

PATH_REGEX='\- path: "?(.+)"?'
restore_from_config() {
  local config_file="${1:?}"
  local db_path
  local restored_flag

  grep -E "$PATH_REGEX" "$config_file" | while IFS= read -r line; do
    db_path=$(sed -E "s/.*$PATH_REGEX.*/\1/" <<<"$line")
    # if watch: true, path will not contain an extension
    case "$(basename "$db_path")" in
    *.*) ;;
    *) continue ;;
    esac
    restored_flag="$(restored_flag_for "$db_path")"

    if test -z "${LITESTREAM_NO_RESTORE:-}"; then
      rm -f "$restored_flag"
      LITESTREAM_LOGGING_LEVEL=debug litestream restore -config="$config_file" \
        -if-replica-exists -if-db-not-exists -integrity-check=full "$db_path"
      touch "$restored_flag"
    fi

    if test -z "${LITESTREAM_NO_WALINIT:-}"; then
      # initialize db as litestream user if it doesn't exist
      sqlite3 "$db_path" "PRAGMA journal_mode=WAL;"
    fi
  done
}

is_restore_from_config_complete() {
  local config_file="${1:?}"
  local db_paths=$(grep -E "$PATH_REGEX" "$config_file")
  local db_path

  while IFS= read -r line; do
    db_path=$(sed -E "s/.*$PATH_REGEX.*/\1/" <<<"$line")
    is_restore_complete "$db_path"
  done <<<$db_paths
}

clear_restored_flags_from_config() {
  local config_file="${1:?}"
  local db_paths=$(grep -E "$PATH_REGEX" "$config_file")
  local db_path

  while IFS= read -r line; do
    db_path=$(sed -E "s/.*$PATH_REGEX.*/\1/" <<<"$line")
    clear_restored_flag "$db_path"
  done <<<$db_paths
}

restore() {
  local db_path="${1:?}"
  local db_uri="${2:?}"
  local restored_flag="$(restored_flag_for "$db_path")"

  if test -z "${LITESTREAM_NO_RESTORE:-}"; then
    rm -f "$restored_flag"
    LITESTREAM_LOGGING_LEVEL=debug LITESTREAM_DB_PATH="$db_path" LITESTREAM_REPLICA_URL="$db_uri" \
      litestream restore -config="/etc/litestream/litestream.yaml" \
      -if-replica-exists -if-db-not-exists -integrity-check=full "$db_path"

    touch "$restored_flag"
  fi

  if test -z "${LITESTREAM_NO_WALINIT:-}"; then
    # initialize db as litestream user if it doesn't exist
    sqlite3 "$db_path" "PRAGMA journal_mode=WAL;"
  fi
}

is_restore_complete() {
  local db_path="${1:?}"
  local restored_flag="$(restored_flag_for "$db_path")"

  if test -z "${LITESTREAM_NO_RESTORE:-}"; then
    [ -e "$restored_flag" ]
  fi
}

clear_restored_flag() {
  local db_path="${1:?}"
  local restored_flag="$(restored_flag_for "$db_path")"

  rm -f "$restored_flag"
}

do_startup_actions() {
  if test -n "${LITESTREAM_STARTUP_ENFORCE_RETENTION:-}" || test -n "${LITESTREAM_STARTUP_FORCE_SNAPSHOT:-}"; then
    LITESTREAM_LOGGING_LEVEL=debug litestream replicate -config="$CONFIG_PATH" -once \
      -enforce-retention="${LITESTREAM_STARTUP_ENFORCE_RETENTION:-false}" \
      -force-snapshot="${LITESTREAM_STARTUP_FORCE_SNAPSHOT:-false}"
  fi
}
