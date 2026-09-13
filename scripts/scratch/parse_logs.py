import json

log_file_path = r"C:\Users\manav\.gemini\antigravity\brain\dff86fcf-7606-49ac-a9dd-c8711f2122c3\.system_generated\steps\12157\output.txt"

with open(log_file_path, "r", encoding="utf-8") as f:
    data = json.load(f)

# Extract items in results
logs = data.get("result", {}).get("result", [])
print(f"Total log entries: {len(logs)}")

for log in logs[:20]:
    # Check if there is details or other fields containing stack traces
    print(f"Timestamp: {log.get('timestamp')}, Message: {log.get('event_message')}, Status: {log.get('status_code')}")
    # print keys
    for k, v in log.items():
        if k not in ["timestamp", "event_message", "status_code", "id", "function_id", "deployment_id"]:
            print(f"  {k}: {v}")
