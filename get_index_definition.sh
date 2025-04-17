#!/usr/bin/env bash

jq -r '
def get_query_filter_args:
    [
      if ((keys | length) == 1 and has("$and"))
      then
        ."$and" | reduce .[] as $item ({}; . * $item)
      else
        .
      end |
      paths |
      map(select( type!="number" and (. != "$and") )) |
      join("/")
    ] |
    map(
      if test("/(\\$gt|\\$gte|\\$lt|\\$lte)")
        then "R:" + (split("/")[0])
      elif test("/\\$regularExpression/")
        then "E_REGEX:" + (split("/")[0])
      elif test("/\\$in")
        then "E_IN:" + (split("/")[0])
      elif test("/\\$nin")
        then "E_NIN:" + (split("/")[0])
      elif test("/\\$ne")
        then "NE:" + (split("/")[0])
      elif test("/\\$date$")
        then "E:" + (split("/")[0])
      else
        "E:" + . end
    ) |
    unique |
    sort
;
def get_sort_condition:
    . // [] |
    to_entries |
    map("S:"+.key+"_"+(.value|tostring))
;
def parse_agg_pipeline:
if .[0]."$match" then
  (.[0]."$match" | get_query_filter_args)
  +
  (
    if any(.[]; has("$sort")) then
      .[] | select(has("$sort")) | ."$sort" | get_sort_condition
    else []
    end
  )
  +
  (
    if (
      (.[-1] | has("$group")) and
      (.[-1]."$group" | to_entries | map(select(.value=={"$sum":{"$const":1}})) | length) == 1
    ) then
      ["COUNT_ONLY"]
    else
      []
    end
  )
else
  ["FIXME:1"]
end
;
if .attr.command.find then
  (.attr.command.filter | get_query_filter_args)
  +
  ( .attr.command.sort | get_sort_condition)
elif .attr.command.getMore then
  if .attr.originatingCommand.find then
    ( .attr.originatingCommand.filter | get_query_filter_args )
    +
    ( .attr.originatingCommand.sort | get_sort_condition )
  elif .attr.originatingCommand.aggregate then
    ( .attr.originatingCommand.pipeline | parse_agg_pipeline)
  else
    ["FIXME:2"]
  end
elif .attr.command.findAndModify then
  (.attr.command.query | get_query_filter_args)
  +
  ( .attr.command.sort | get_sort_condition)
elif (.attr.command.aggregate and .attr.command.pipeline[0]."$match") then
  (.attr.command.pipeline | parse_agg_pipeline)
elif (.attr.type and .attr.type == "update") then
  (.attr.command.q | get_query_filter_args)
else
 ["FIXME:3"]
end
| join(",")
'
