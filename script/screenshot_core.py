#!/usr/bin/env python3
"""Read-only, fictional Core for README screenshots (Python standard library).

JSON shapes follow Tests/CoreAPIContractTests/main.swift. No Telegram access,
credentials, files from a real Core, or proxying. Run via screenshot_app.sh.
"""

import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit


DAY = "2026-10-14"
NOW = DAY + "T09:30:00+09:00"
STATE = dict(ok=True, database_id="community-archive", schema_version=2,
             last_event_seq=24816, message_count=18452, operation_error_count=0,
             server_time=NOW)
GROUPS = [
    ("Design Collective", "design,community", True),
    ("城市漫步 · City Walks", "weekend,photography", True),
    ("开源读书会", "learning,opensource", True),
    ("Weekend Kitchen", "food,community", False),
    ("Craft & Code", "design,engineering", True),
    ("自然观察笔记", "nature,photography", False),
]
MESSAGES = [
    (0, "Maya", "The updated icon set is ready. I kept the rounded corners and simplified the small sizes."),
    (1, "林晓", "周六沿河边散步吧，九点在咖啡馆集合。天气合适的话可以带上相机。"),
    (2, "陈墨", "这周一起读项目的架构文档，先从数据流和模块边界开始。"),
    (3, "Oliver", "Sunday lunch idea: roasted pumpkin soup, fresh bread, and a shared salad."),
    (4, "Nora", "Keyboard navigation feels much better now. The focus order follows the reading order."),
    (5, "小禾", "今天在公园看到了几只白鹭，下次可以试试清晨的光线。"),
]
ORIGINS = [dict(source="telegram", account_id="community", origin_id=-2001-i,
                topic_id=0, origin_type="group", title=title, is_forum=False,
                important=important, backup_policy=dict(
                    source="telegram", account_id="community", origin_id=-2001-i,
                    topic_id=0, enabled=True, capture_text=True,
                    capture_media_metadata=True, download_media=False, tags=tags))
           for i, (title, tags, important) in enumerate(GROUPS)]
MESSAGE_ROWS = [dict(event_seq=24816-i, source="telegram", account_id="community",
                     chat_id=-2001-group, message_id=306-i,
                     chat_title=GROUPS[group][0], origin_title=GROUPS[group][0],
                     sender_name=sender, text=body, has_media=False, version=1,
                     sent_at=f"{DAY}T09:{24-i*3:02d}:00+09:00")
                for i, (group, sender, body) in enumerate(MESSAGES)]
REPORTS = [
    ("Community highlights", "important_daily", "design,community", """# Community highlights

## Design & craft
The new icon set is ready for review. Rounded corners keep the visual language consistent, while simpler shapes improve readability at small sizes.

- Review the toolbar icons at both standard and Retina sizes.
- Keep keyboard focus in the same order as the visible controls.

## 城市漫步
周六的城市散步计划已经确定：上午九点从咖啡馆出发，沿河步道慢行，记录秋天的街景。

## Learning together
The open-source reading group will begin with architecture notes, tracing the data flow before discussing individual modules.

## Next steps
- Share icon feedback before Friday.
- Bring a camera for the weekend walk.
- Read the architecture overview before the next discussion.
"""),
    ("城市漫步与自然观察", "tag_group", "weekend,photography", """# 城市漫步与自然观察

## 本日话题
沿河散步、秋日街景和公园观鸟成为今天的主要话题。

## 周末计划
- 周六上午九点在咖啡馆集合。
- 带上相机，尝试记录清晨的自然光。
- 散步结束后分享照片和路线笔记。
"""),
]
RECORDS = [dict(summary_id=f"daily-{i+1}", run_id="morning-digest",
                package_run_id="morning-archive", date=DAY, timezone="Asia/Tokyo",
                title=title, record_type=kind, content_preview=body.split("\n\n")[1],
                content_md=body, tags=tags.split(","), tags_csv=tags,
                important=i == 0, provider="codex-cli", origin_count=6,
                group_count=3, image_count=0, deleted=False,
                created_at=NOW, updated_at=NOW)
           for i, (title, kind, tags, body) in enumerate(REPORTS)]
RUN = dict(status="completed", date=DAY, timezone="Asia/Tokyo",
           progress_current=6, progress_total=6, progress_label="Analysis complete",
           started_at=DAY + "T09:00:00+09:00", finished_at=DAY + "T09:02:00+09:00")
ROUTES = {
    "/healthz": STATE,
    "/sync/state": STATE,
    "/manage/capabilities": dict(mode="single_user", sync=["messages", "media_files"],
                                 management=["accounts", "origins", "daily_summary"],
                                 api_contract={"contract_version": "2026-07-03.1"}),
    "/sync/messages": dict(items=MESSAGE_ROWS, next_cursor=24816, has_more=False),
    "/manage/origins": dict(items=ORIGINS),
    "/manage/operation-events": dict(items=[]),
    "/manage/daily-summary-records": dict(items=RECORDS),
    "/manage/daily-package-runs": dict(items=[dict(RUN, run_id="morning-archive", message_count=128, media_count=0)]),
    "/manage/daily-summary-runs": dict(items=[dict(RUN, run_id="morning-digest", provider="codex-cli", origin_count=6)]),
    "/manage/daily-summary-jobs": dict(items=[dict(RUN, job_id="morning-analysis", provider="codex-cli")]),
    "/manage/accounts": dict(items=[]),
    "/manage/daily-message-points": dict(items=[]),
    "/sync/media-files": dict(items=[]),
}
ROUTES["/manage/api-manifest"] = dict(
    name="tele-mess-core API", contract_version="2026-07-03.1",
    contract_hash="7c29a4e1", endpoints=[dict(path=path) for path in ROUTES])


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        url = urlsplit(self.path)
        if url.path == "/manage/daily-summary-records/item":
            record_id = parse_qs(url.query)["summary_id"][0]
            payload = dict(item=next(row for row in RECORDS if row["summary_id"] == record_id))
        elif url.path in ROUTES:
            payload = ROUTES[url.path]
        else:
            self.send_error(404)
            return
        body = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    # Port zero lets macOS allocate a free loopback port; the launcher reads it.
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    with open(sys.argv[1], "w") as port_file:
        port_file.write(str(server.server_port))
    server.serve_forever()
