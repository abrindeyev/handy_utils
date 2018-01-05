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

function log_info() {
  log2stderr "[INFO] $@"
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

function list_all_mongox() {
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

function kill_all_mongox() {
  local pids=$(pgrep 'mongo(s|d)')
  [[ -n $pids ]] || { die "No MongoDB processes are currently running"; return 1; }
  for pid in "${pids[@]}"; do
    log_debug "Killing PID $pid"
    kill $pid
  done
}

function __get_last_active_ticket_directory() {
  local last_ticket=$(ls -1tr "${SFSC_DIR:-$HOME/SFSC}" | tail -n1)
  printf "${SFSC_DIR:-$HOME/SFSC}/${last_ticket}"
}

function lcd() {
  cd "$(__get_last_active_ticket_directory)"
}

function move_fresh_meat() {
  local dl_dir="$HOME/Downloads"
  local dest_dir="$HOME/SFSC"
  if   [[ $# -eq 0 ]]; then
    local mv_dir="${dest_dir}/$(ls -1tr "$dest_dir" | tail -n1)"
    local number_of_files_to_move=1
  elif [[ $# -eq 1 && ${#1} -lt 4 ]]; then
    # single argument and it looks like number of files rather then ticket number
    local mv_dir="${dest_dir}/$(ls -1tr "$dest_dir" | tail -n1)"
    local number_of_files_to_move="$1"
  elif [[ $# -eq 1 ]]; then
    # single argument and since it length is greater then X, it's probably a ticket number
    local mv_dir="$dest_dir/$1"
    local number_of_files_to_move=1
  elif [[ $# -eq 2 ]]; then
    if [[ ${#1} -lt 4 && ${#2} -gt 4 ]]; then
      # two arguments:
      # first one is looks like a number of files
      # second is looks like a ticket number
      local number_of_files_to_move="$1"
      local mv_dir="$dest_dir/$2"
    elif [[ ${#1} -gt 4 && ${#2} -lt 4 ]]; then
      # two arguments:
      # first one is looks like a ticket number
      # second is looks like a number of files
      local mv_dir="$dest_dir/$1"
      local number_of_files_to_move="$2"
    else
      log_error "Should never reach here! Check length of the arguments: ticket number_of_files OR number_of_files ticket"
      return 1
    fi
    [[ $number_of_files_to_move = *[^0-9]* ]] && { die "Number of files to move (2nd argument) must be a numeric value"; return 1; }
  else
    die "Unsupported number of arguments: $#"
    return 1
  fi
  [[ -d "$mv_dir" ]] || mkdir -p "$mv_dir" || { die "Can't create $mv_dir directory"; return 1; }
  for count in $(seq $number_of_files_to_move); do
    local file_to_move="$dl_dir/$(ls -1tr "$dl_dir" | tail -n1)"
    [[ -f "$file_to_move" ]] || { die "Can't locate file to move: $file_to_move"; return 1; }
    mv "$file_to_move" "$mv_dir" || { die "Failed to move $file_to_move to $mv_dir directory"; return 1; }
  done
  echo "Successfully moved $number_of_files_to_move recent files to $mv_dir directory"
  cd $mv_dir || { die "Can't cd into $mv_dir"; return 1; }
}

function runyara {
  yara -gfsem ~/src/support-tools/yara/mongodlog.yar "$1" | grep -E 'default|detected' | sed -e 's/^default/\'$'\ndefault/'
}

function mdiag_get_file {
  local mdiag="$1"
  local fn="$2"
  if [[ -f "$1" ]]; then
    if [[ -n $2 ]]; then
      jq -r '.[] | select(.subsection == "'$2'") | .content[]' "$1"
    else
      # get list of captured files inside
      jq -r '.[] | select(has("subsection")) | .subsection ' "$1" | egrep '^/' | sort
    fi
  else
    die "Usage:\nTo list all captured files inside: mdiag_get_file mdiag.json\nTo get file: mdiag_get_file mdiag.json /etc/nsswitch.conf"
  fi
}
