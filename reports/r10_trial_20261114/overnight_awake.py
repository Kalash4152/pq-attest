"""Temporary SYSTEM_REQUIRED request; allows display idle and leaves power settings unchanged."""
import ctypes,datetime,json,os,time
from pathlib import Path
R=Path(__file__).resolve().parent
zone=datetime.timezone(datetime.timedelta(hours=5,minutes=30))
now=datetime.datetime.now(zone)
until=now.replace(hour=11,minute=30,second=0,microsecond=0)
if until<=now:until+=datetime.timedelta(days=1)
state=R/'overnight_awake_status.json'
request=ctypes.windll.kernel32.SetThreadExecutionState
accepted=bool(request(0x80000001))
info=dict(pid=os.getpid(),started=now.isoformat(),until=until.isoformat(),
    state='ACTIVE' if accepted else 'FAILED',system_request_accepted=accepted,
    display_required=False,power_settings_changed=False)
state.write_text(json.dumps(info,indent=2)+'\n')
if not accepted:raise RuntimeError('Windows refused the idle-sleep prevention request')
try:
    while datetime.datetime.now(zone)<until and not (R/'overnight_awake.stop').exists():
        time.sleep(10)
finally:
    request(0x80000000)
    info.update(state='ENDED',ended=datetime.datetime.now(zone).isoformat())
    state.write_text(json.dumps(info,indent=2)+'\n')
