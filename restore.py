
import json, io, os

log_file = r'G:\AntigravityPortable\.gemini\antigravity\brain\2fd077d6-054d-4206-bd54-d501a71d60e9\.system_generated\logs\transcript_full.jsonl'
with io.open(log_file, 'r', encoding='utf-8') as f:
    for line in f:
        try:
            data = json.loads(line)
            if data.get('type') == 'PLANNER_RESPONSE' and 'tool_calls' in data:
                for call in data['tool_calls']:
                    if call['name'] in ('write_to_file', 'replace_file_content'):
                        args = call['args']
                        target = args.get('TargetFile', '')
                        if 're-V' in target and 'lib' in target:
                            idx = target.find('lib')
                            rel_path = target[idx:]
                            content = args.get('CodeContent', args.get('ReplacementContent', ''))
                            if not os.path.exists(os.path.dirname(rel_path)):
                                os.makedirs(os.path.dirname(rel_path))
                            with io.open(rel_path, 'w', encoding='utf-8') as out:
                                out.write(content)
                            print('Restored ' + rel_path)
        except Exception as e:
            pass

