#!/usr/bin/env ruby

require 'date'
require 'json'
require 'time'

out_fmt = '%Y-%m-%dT%H:%M:%S.%L%z'

ARGF.each_line do |raw_log_line|
 log_line = raw_log_line.chars.select(&:valid_encoding?).join
 begin 
  if md = log_line.match(/^{"t":{"\$date":/)
    jl = JSON.parse(log_line)
    a = {}
    if jl.has_key?("attr") and jl["attr"].has_key?("durationMillis")
      event_started_dt = DateTime.parse(jl["t"]["$date"]) - Rational(jl["attr"]["durationMillis"], 24*60*60*1000)
      a["st"] = event_started_dt.strftime(out_fmt)
      a["t"]  = jl.delete("t")
      a["dms"] = jl["attr"]["durationMillis"]
    else
      a["st"] = jl["t"]["$date"]
      a["t"]  = jl.delete("t")
    end
    puts JSON.generate(a.merge(jl))
  end
  if md = log_line.match(/^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}.\d{3,6}(?:\+|-)[0-9:]{4,5}) (.*) (\d+)ms$/)
    event_completed_dt = DateTime.parse(md.captures[0])
    line_no_date_no_ms = md.captures[1]
    duration_str = md.captures[2]
    duration_ms = Rational(duration_str.to_i, 24*60*60*1000)
    event_started_dt = event_completed_dt - duration_ms
    next if log_line.match(/sleeping for \d+ms$/)
    next if log_line.match(/timeout was set to \d+ms$/)
    ll = sprintf("%28s => %28s %sms %s %sms", event_started_dt.strftime(out_fmt), event_completed_dt.strftime(out_fmt), duration_str, line_no_date_no_ms, duration_str)
    #next if log_line.match(/Finding the split vector for.*took \d+ms$/)
    #next if log_line.match(/task: UnusedLockCleaner took: \d+ms$/)
    #next if log_line.match(/WiredTiger record store oplog truncation finished in: \d+ms/)
    puts ll
  end
 rescue ArgumentError
  puts "Exception in log line:\n#{log_line}"
  exit 1
 end
end
