# vi: tabstop=2 shiftwidth=2 expandtab autoindent

# Library for Linux & macOS users holding useful aliases
[[ -z $DATA_HOME ]] && DATA_HOME="/data/dbs"
[[ -z $LOGS_HOME ]] && LOGS_HOME="/data/logs"

function in_interactive_shell() {
  if [[ -z "$PS1" ]]; then
    # This shell is not interactive
    return 1
  else
    # This shell is interactive
    return 0
  fi
}

function log2stderr() {
  if in_interactive_shell; then
    echo "${*}" 1>&2
  else
    echo "[$(date +%Y-%m-%d-%H:%M:%S)] ${*}" 1>&2
  fi
}

function log_error_internal() {
  local stack_depth=$1
  shift
  if in_interactive_shell; then
    log2stderr "$@"
  else
    log2stderr "[ERROR] [${BASH_SOURCE[(( stack_depth + 1 ))]##*/}:${BASH_LINENO[$stack_depth]}] $@"
  fi
}

function log_error() {
  log_error_internal 1 "$*"
}

function log_error_lib() {
  log_error_internal 2 "$*"
}

function log_debug() {
  if [[ -n $DEBUG ]]; then
    if in_interactive_shell; then
      log2stderr "$@"
    else
      log2stderr "[DEBUG] $@"
    fi
  fi
}

function die() {
  log_error_lib "$*"
  if in_interactive_shell; then
    return 1
  else
    local i
    local stack_size=${#FUNCNAME[@]}
    for (( i=1; i<$stack_size ; i++ )); do
      local func="${FUNCNAME[$i]}"
      [ x$func = x ] && func=MAIN
      local linen="${BASH_LINENO[(( i - 1 ))]}"
      local src="${BASH_SOURCE[$i]}"
      [ x"$src" = x ] && src=non_file_source
      log2stderr "[TRACE]    ${func} (${src}:${linen})"
    done
    exit 1
  fi
}

# Joins array elements using first parameter as delimiter and return as string
function join { local IFS="$1"; shift; echo "$*"; }

function whoison_tcp_port() {
  local pn="${1?Specify port}"
  local tool=''
  if [[ "$OSTYPE" =~ ^darwin ]]; then
    if tool=$(which lsof); then
      "$tool" -i ":$pn" -a '-sTCP:LISTEN' -F p | egrep '^p' | cut -c 2-
    else
      die "Can't find lsof in \$PATH"
      return 1
    fi
  elif [[ "$OSTYPE" =~ ^linux-gnu ]]; then
    if tool=$(which ss); then
      "$tool" -tpln sport eq ":$pn" | egrep ^LISTEN | sed 's/^.*users:(\(.*\))/\1/; s/([^,]\+,\([0-9]\+\),[0-9]\+)/\1/g; s/,/\n/g'
    else
      die "Can't find ss in \$PATH"
      return 1
    fi
  else
    die "Platform $OSTYPE isn't support yet"
    return 1
  fi
}

function whatports_pid_listening_on() {
  local pn="${1?Specify PID}"
  local tool=''
  if [[ "$OSTYPE" =~ ^darwin ]]; then
    if tool=$(which lsof); then
      "$tool" -p "$pn" -a -iTCP -a -sTCP:LISTEN
    else
      die "Can't find lsof in \$PATH"
      return 1
    fi
  elif [[ "$OSTYPE" =~ ^linux-gnu ]]; then
    if tool=$(which ss); then
      "$tool" -tpln sport eq ":$pn" | egrep ^LISTEN | sed 's/^.*users:(\(.*\))/\1/; s/([^,]\+,\([0-9]\+\),[0-9]\+)/\1/g; s/,/\n/g'
    else
      die "Can't find ss in \$PATH"
      return 1
    fi
  else
    die "Platform $OSTYPE isn't support yet"
    return 1
  fi
}

function list_all_mongos() {
  local pids=$(pgrep 'mongo(s|d)')
  [[ $? -ne 0 ]] && { die "No mongo(s|d) processes were found by pgrep"; return 1; }
  local -a pids_array=($pids)
  [[ ${#pids_array[@]} -eq 0 ]] && { die "No mongo(s|d) processes were found by pgrep"; return 1; }
  ps -p "$( join , "${pids_array[@]}" )" -o pid,command
}

function start_mongox_on_port() {
  local name="${1?Specify binary: mongod or mongos}"
  shift
  local pn="${1?Specify port}"
  shift
  if nc -z localhost "$pn" >/dev/null 2>&1; then
    die "port $pn is busy by PIDs: $(whoison_tcp_port $pn)"
    return 1
  fi
  local my_logs="$LOGS_HOME/$pn"
  [[ -d $my_logs ]] || mkdir -p "$my_logs" || die "Can't create logs directory $my_logs"
  [[ -n $DEBUG ]] && set -x
  $name --port $pn --logpath "$my_logs/$pn.log" --fork "$@"
  [[ -n $DEBUG ]] && set +x
  if in_interactive_shell; then
    sleep 1
    tail -n 3 "$my_logs/$pn.log"
  fi
}

function start_mongod_on_port() {
  local pn="${1?Specify port}"
  shift
  local my_data="$DATA_HOME/$pn"
  [[ -d $my_data ]] || mkdir -p "$my_data" || die "Can't create data directory $my_data"
  start_mongox_on_port mongod $pn --dbpath "$my_data" "$@"
}

function start_mongos_on_port() {
  start_mongox_on_port mongos "$@"
}

function kill_mongo_on_port() {
  local pn="${1?Specify port}"
  if ! nc -z localhost "$pn" >/dev/null 2>&1; then
    die "There is no MongoD process which is listening on port $pn"
  fi
  for pid in $(whoison_tcp_port $pn); do
    log_debug "Killing PID $pid"
    kill $pid
  done
}

function kill_all_mongos() {
  local pids=$(pgrep 'mongo(s|d)')
  [[ -n $pids ]] || { echo "No MongoDB processes are currently running"; return 1; }
  for pid in "${pids[@]}"; do
    log_debug "Killing PID $pid"
    kill $pid
  done
}
