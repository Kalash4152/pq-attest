"""One frozen 100-seed range, determined by its registered job ID."""
import argparse
from pathlib import Path
import re
from seed_campaign import execute_campaign,system_awake

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args()
    match=re.fullmatch(r'i24_seed_shard_(\d\d)',a.out.name)
    if not match or not 0<=int(match[1])<10:raise ValueError('unknown registered shard ID')
    with system_awake():execute_campaign(a.out,100*int(match[1]),100)
