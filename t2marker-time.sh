#!/usr/bin/env bash

marker="${1:-A}"
t2_context="${2:-"Context 1"}"
t2_settings="${3:-$HOME/.t2}"

function error() {
  local msg="$1"
  printf "$msg\n"
  exit 1
}

function usage() {
  printf "Returns a UTC-formatted date from a specific t2 marker.\n"
  printf "Usage:\n${BASH_SOURCE[0]} A 'Context 1' \"$HOME/.t2\"\nAll parameters are optional, defaults are above.\n"
}

if [[ $1 == '-h' || $1 == '/h' || $1 == '/?' || $1 == 'help' || $1 == '-help' || $1 == '--help' ]]; then
  usage
  exit 0
fi

if [[ ${#1} -ne 1 ]]; then
  error "Please specify a single marker (like A, B, etc.). Here's what I found instead: $1"
fi

r="$(jq -r "any(.contexts[]; .ctxName==\"${t2_context}\")" "$t2_settings")"
if [[ $r == 'false' ]]; then
  error "Can't find the [$t2_context] context in the $t2_settings configuration file, please double-check the context name and the configuration file location."
fi

ascii="$(printf "%d" "'$marker")"
m=$(( ascii - 65 ))

r="$(jq -r ".contexts[] | select(.ctxName==\"${t2_context}\") | .markers | length" "$t2_settings")"
if [[ $r -le $m ]]; then
  error "There's no marker $marker from the [$t2_context] context in the $t2_settings configuration file"
fi

f=$(jq -r ".contexts[] | select(.ctxName==\"${t2_context}\") | .markers[$m]" "$t2_settings")
if [[ $f == "null" ]]; then
  error "The $marker marker from the [$t2_context] context in the $t2_settings configuration file has the NULL value"
fi

echo -n "$f"
