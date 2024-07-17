#!/usr/bin/env ruby

require 'optparse'
require 'socket'

interface = '127.0.0.1'
port = 1234
file_to_stream = nil
target_bitrate = nil
udp_packet_size = 188 * 7

optparse = OptionParser.new do |opts|
  opts.banner = 'Usage: udp-sender.rb [options]'

  opts.on('-f FILE', 'file to stream')    { |v| file_to_stream = v }
  opts.on('-i INTERFACE', 'interface to stream to') { |v| interface = v }
  opts.on('-p PORT', 'port to stream to') { |v| port = v.to_i }
  opts.on('-b BITRATE', 'streaming bitrate in Kbps') { |v| target_bitrate = v.to_f }
end

optparse.parse!

if file_to_stream.nil? or file_to_stream.empty?
  puts "Please specify file name to stream."
  puts optparse
  exit(1)
elsif port <= 0
  puts "Please specify proper port to stream to."
  puts optparse
  exit(1)
end

if target_bitrate == nil
  # get bitrate of a file using ffprobe
  require 'open3'
  ffprobe_output, ffprobe_status = Open3.capture2e("ffprobe", "-hide_banner", file_to_stream)
  match_data = /  Duration: ([^, ]+).*bitrate: ([0-9]+) /.match(ffprobe_output)

  # ffprobe seem to report kbps divided to 1000 instead of 1024
  target_bitrate = match_data[2].to_f * 1000
else
  target_bitrate = target_bitrate.to_f * 1000
end

target_writes_per_second = target_bitrate / 8 / udp_packet_size
sleep_time = 1 / target_writes_per_second

u2 = UDPSocket.new

start_time = Time.now
writes_count = writes_count_total = 0

File.open(file_to_stream, 'rb') do |file|
  while(true) do
    buffer = file.read(udp_packet_size)
    if buffer.nil?
      target_send_time = sprintf("%.2f", File.size(file_to_stream) / (target_bitrate / 8))
      time_spent = sprintf("%.2f", Time.now - start_time)
      puts "finished sending #{file_to_stream} (#{target_bitrate / 1000} kbps | target #{target_send_time}s actual #{time_spent}s)"
      break
    end

    u2.send(buffer, 0, interface, port)
    sleep(sleep_time)

    writes_count += 1
    if writes_count >= target_writes_per_second
      time_spent = Time.now - start_time
      expected_writes_count = (time_spent * target_writes_per_second).to_i

      writes_count_total += writes_count
      writes_delta = expected_writes_count - writes_count_total

      if target_writes_per_second + writes_delta <= 0
        # reset sleep time if streaming too fast (does not normally happen)
        sleep_time = 1 / target_writes_per_second
      else
        # adjust sleep time based on current writes rate
        sleep_time = 1 / (target_writes_per_second + writes_delta)
      end

      writes_count = 0 # reset counter
    end
  end
end
