#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import json
import os
import sys
from collections import Counter, defaultdict


def parse_input_field(inp):
    """Parse the 'input' field and return the greeting value (or None)."""
    if isinstance(inp, str):
        try:
            data = json.loads(inp)
        except json.JSONDecodeError:
            return None
    else:
        data = inp

    if isinstance(data, list) and data:
        return data[0].get('greeting')
    if isinstance(data, dict):
        return data.get('greeting')
    return None


def parse_response_field(resp):
    """Parse the 'response' field and return the reply value (or None)."""
    if isinstance(resp, str):
        try:
            data = json.loads(resp)
        except json.JSONDecodeError:
            return None
    else:
        data = resp

    if isinstance(data, dict):
        return data.get('reply')
    return None


def main():
    # Get all .log files in logs directory, sorted by modification time (newest first)
    logs_dir = os.path.join(os.path.dirname(__file__), 'logs')
    log_files = [f for f in os.listdir(logs_dir) if f.endswith('.log')]
    log_files = sorted(log_files, key=lambda x: os.path.getmtime(os.path.join(logs_dir, x)), reverse=True)
    if not log_files:
        print('No log files found.')
        return
    print('Please select a log file to analyze:')
    for idx, fname in enumerate(log_files, 1):
        print(f'{idx}. {fname}')
    while True:
        try:
            choice = int(input('Enter number: '))
            if 1 <= choice <= len(log_files):
                break
            else:
                print('Invalid selection, please try again.')
        except ValueError:
            print('Please enter a number.')
    logfile_path = os.path.join(logs_dir, log_files[choice - 1])
    with open(logfile_path, 'r', encoding='utf-8') as logfile:
        make_req_count = 0

        # Count code occurrences in Received RPC Stats, and error occurrences under each code
        stats_code_counter = Counter()
        stats_error_counter = defaultdict(Counter)

        # Count Received response
        resp_total = 0
        resp_error = 0
        resp_error_examples = []

        for lineno, line in enumerate(logfile, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                # Skip lines that cannot be parsed as JSON
                continue

            msg = rec.get('msg', '')
            if msg == 'Making request':
                make_req_count += 1

            elif msg == 'Received RPC Stats':
                code = rec.get('code')
                error = rec.get('error')
                stats_code_counter[code] += 1
                stats_error_counter[code][error] += 1

            elif msg == 'Received response':
                resp_total += 1

                # Parse fields
                greeting = parse_input_field(rec.get('input'))
                api_key = rec.get('metadata', {}).get('x-api-key')
                reply = parse_response_field(rec.get('response'))

                # Validation
                if greeting != 'Hey' or api_key != ['demo-api-key-2025'] or reply != 'hello Hey':
                    resp_error += 1
                    if len(resp_error_examples) < 5:
                        resp_error_examples.append({
                            'line': lineno,
                            'greeting': greeting,
                            'x-api-key': api_key,
                            'reply': reply
                        })

        # Output results
        print(f'Total Making request: {make_req_count}\n')

        print('=== Received RPC Stats TOP 5 codes ===')
        for code, cnt in stats_code_counter.most_common(5):
            print(f'Code="{code}"  Total: {cnt}')
            print('  Top Errors:')
            error_items = [(err, ecnt) for err, ecnt in stats_error_counter[code].most_common() if err not in (None, '', 'None')]
            if error_items:
                for err, ecnt in error_items[:5]:
                    print(f'    Error={err!r}  Count={ecnt}')
            else:
                print('    (No errors)')
            print()

        print(f'Total Received response: {resp_total}')
        print(f'Response Validation Failures: {resp_error}\n')

        if resp_error_examples:
            print('---- Response Validation Failure examples (up to 5) ----')
            for ex in resp_error_examples:
                print(f'  Line {ex["line"]}: greeting={ex["greeting"]!r}, '
                      f'x-api-key={ex["x-api-key"]!r}, reply={ex["reply"]!r}')


if __name__ == '__main__':
    main()
