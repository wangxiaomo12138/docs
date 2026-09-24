#!/usr/bin/env python3
import sys
import json

def main():
    # 关闭python输出缓冲
    sys.stdout.reconfigure(line_buffering=False)
    while True:
        chunk = sys.stdin.read(1)
        if not chunk:
            # 数据流结束，输出结束标记
            end_item = {"type": "end", "reason": "complete"}
            sys.stdout.write(json.dumps(end_item, ensure_ascii=False)+"\n")
            sys.stdout.flush()
            break
        out = {
            "type": "content",
            "text": chunk
        }
        sys.stdout.write(json.dumps(out, ensure_ascii=False)+"\n")
        sys.stdout.flush()

if __name__ == "__main__":
    main()