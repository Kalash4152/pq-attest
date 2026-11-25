# TITAN S2 monitor event export

The bound checker is active in the I-T2 monitor-bound XSim jobs via titan_mon_bind.sv. Selecting those compiled benches enables event output. The simulation-only monitor writes one TITAN_EVENT line per observed counter event. No extra define or plusarg is required. This allows the normal XSim log, which remains the evidence source, to carry the same event information as the CSV.

Strip the exact TITAN_EVENT prefix plus one space and prepend the CSV header:

```text
cycle,event,src,tag,epoch
```

| Column | Meaning and type |
|---|---|
| cycle | Unsigned decimal clock count since reset. |
| event | Enum P1, P2, P3, P4, M3, SD. |
| src | Decimal requester tile index, 0–5. |
| tag | Decimal NI transaction tag, 0 or 1. |
| epoch | Decimal six-bit shadow epoch, sampled by the monitor at the event. |

P1 is an invalid write commit (authorization/epoch/request tracking). P2 is invalid read-data delivery. P3 is a request/response tracking mismatch. P4 is a repeated definitive response. M3 is a commit after bridge timeout. SD is NI slot expiry after the request reached the front end and before a definitive response. P6 has no event row. Its summary value X records that full credit conservation was unobserved.

The file samples/s2_bound_events.csv has the header and zero data rows. It was extracted from the accepted bound secure workload, which reported zero events. samples/s2_unit_events.csv has events from the scripted unit sequences. Its cycle counter restarts at each case reset, so rows are in test order and cycle counts can repeat across cases.
