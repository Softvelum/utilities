#!/usr/bin/env python3

import re, requests, subprocess, argparse
from datetime import datetime

def GetTrimSaveReqestedFile(url, path):
    time_length_req = re.findall(r'playlist_dvr_range-\d+-\d+\.m3u8', url)
    if len(time_length_req) != 1:
        print(f'incorrect DVR playlist URL: {url}')
        return

    master_playlist_request = requests.get(url, verify=False)
    master_playlist = master_playlist_request.content.decode('utf-8')
    chunklist_name = []
    for content in re.split(r'[\n\r]+', master_playlist):
        chunklist_name = re.findall(r'chunks_dvr_range.*$', content)
        if len(chunklist_name) > 0:
            break

    if len(chunklist_name) == 0:
        print(f"chunklist URL not found in master playlist:\n===\n{master_playlist}\n===")
        return

    chunklist_url = url[0:url.rfind('/') + 1] + ''.join(chunklist_name)
    chunklist_request = requests.get(chunklist_url, verify=False)
    chunklist_content = chunklist_request.content.decode('utf-8')
    chunks_start_time = re.findall(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}', chunklist_content)
    if len(chunks_start_time) == 0:
        print(f"failed to find PROGRAM-DATE-TIME in chunklist:\n===\n{chunklist_content}\n===")
        return

    first_chunk_start_time = datetime.strptime(''.join(chunks_start_time[0]), '%Y-%m-%dT%H:%M:%S').timestamp()
    time_length_req = re.findall(r'\d+', time_length_req[0])
    length_total_sec = int(time_length_req[1])
    length_h = length_total_sec // 3600
    length_m = (length_total_sec - length_h * 3600) // 60
    length_s = length_total_sec -  length_h * 3600 - length_m * 60
    time_length = f"{length_h:02d}:{length_m:02d}:{length_s:02d}"
    cut_from_first_chunk_sec = f"{(int(time_length_req[0]) - int(first_chunk_start_time)) % 3600:02d}" # -UTC

    ffmpeg_cmd = 'ffmpeg -hide_banner -i ' + url + ' -ss 00:00:' + cut_from_first_chunk_sec + ' -t ' + time_length + ' -codec copy ' + path
    print('+ ' + ffmpeg_cmd + '\n')

    subprocess.run(ffmpeg_cmd, shell = True)

parser = argparse.ArgumentParser()
parser.add_argument('url', nargs=1)
parser.add_argument('--path', type=str, default='/tmp/tmp.ts')
args = parser.parse_args()
GetTrimSaveReqestedFile(args.url[0], args.path)