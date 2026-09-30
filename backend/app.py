import os
import json
import subprocess
import requests
from flask import Flask, request, jsonify
import firebase_admin
from firebase_admin import credentials, firestore, messaging

# Strict Firebase Configuration
class FirebaseConfig:
    def __init__(self, credential_path: str, server_response_timeout_ms: int = 10000):
        self.credential = credentials.Certificate(credential_path)
        # Timeout configured strictly using timeout.serverResponse in milliseconds
        self.timeout = {"serverResponse": server_response_timeout_ms}

fb_config = FirebaseConfig(
    credential_path=os.getenv("FIREBASE_CREDENTIALS_PATH", "firebase-service-account.json"),
    server_response_timeout_ms=15000
)

firebase_app = firebase_admin.initialize_app(
    fb_config.credential,
    {"httpTimeout": fb_config.timeout["serverResponse"] / 1000.0}
)
db = firestore.client()

app = Flask(__name__)

GITHUB_TOKEN = os.getenv("GITHUB_TOKEN", "")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")
TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")
FCM_TARGET_DEVICE_TOKEN = os.getenv("FCM_TARGET_DEVICE_TOKEN", "")

# ---------------------------------------------------------
# AI Processing Service
# ---------------------------------------------------------
def call_ai_service(system_prompt: str, user_content: str) -> str:
    url = "https://api.openai.com/v1/chat/completions"
    headers = {
        "Authorization": f"Bearer {OPENAI_API_KEY}",
        "Content-Type": "application/json"
    }
    payload = {
        "model": "gpt-4o",
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_content}
        ],
        "temperature": 0.2
    }
    resp = requests.post(url, headers=headers, json=payload, timeout=20)
    data = resp.json()
    return data["choices"][0]["message"]["content"]

# ---------------------------------------------------------
# FCM Notification Dispatcher (Actionable)
# ---------------------------------------------------------
def send_actionable_fcm(title: str, body: str, data_payload: dict):
    if not FCM_TARGET_DEVICE_TOKEN:
        return
    message = messaging.Message(
        notification=messaging.Notification(title=title, body=body),
        data=data_payload,
        android=messaging.AndroidConfig(
            priority="high",
            notification=messaging.AndroidNotification(
                channel_id="devops_action_channel",
                priority="max",
                default_vibrate_timings=True,
                default_sound=True,
                click_action="FLUTTER_NOTIFICATION_CLICK"
            )
        ),
        token=FCM_TARGET_DEVICE_TOKEN
    )
    messaging.send(message)

# ---------------------------------------------------------
# 1. GitHub Webhook Listener
# ---------------------------------------------------------
@app.route("/webhooks/github", methods=["POST"])
def github_webhook():
    event = request.headers.get("X-GitHub-Event")
    payload = request.json

    if event == "pull_request":
        action = payload.get("action")
        pr = payload.get("pull_request", {})
        repo = payload.get("repository", {}).get("full_name")
        pr_number = pr.get("number")

        if action in ["opened", "synchronize"]:
            diff_url = pr.get("diff_url")
            diff_resp = requests.get(
                diff_url,
                headers={"Authorization": f"token {GITHUB_TOKEN}"}
            )
            diff_text = diff_resp.text[:6000]

            review_prompt = (
                "You are an automated DevOps security and architecture reviewer. "
                "Review the following PR diff specifically targeting Vite frontend and Python Flask backend stacks. "
                "Detect bottlenecks, syntax errors, and return: "
                "1. Summary of defects. 2. Proposed unified patch."
            )
            ai_analysis = call_ai_service(review_prompt, diff_text)

            pr_doc = {
                "repo": repo,
                "pr_number": pr_number,
                "title": pr.get("title"),
                "author": pr.get("user", {}).get("login"),
                "analysis": ai_analysis,
                "status": "pending_review",
                "timestamp": firestore.SERVER_TIMESTAMP
            }
            db.collection("github_prs").document(f"{repo.replace('/', '_')}_{pr_number}").set(pr_doc)

            send_actionable_fcm(
                title=f"PR Review: #{pr_number} in {repo}",
                body=f"AI detected potential issues. Review proposed patch.",
                data_payload={
                    "type": "github_pr_action",
                    "repo": repo,
                    "pr_number": str(pr_number),
                    "action_category": "pr_approval",
                    "summary": ai_analysis[:200]
                }
            )

    elif event == "workflow_run":
        run = payload.get("workflow_run", {})
        if run.get("conclusion") == "failure":
            repo = payload.get("repository", {}).get("full_name")
            run_id = run.get("id")
            logs_url = run.get("jobs_url")

            jobs_resp = requests.get(logs_url, headers={"Authorization": f"token {GITHUB_TOKEN}"}).json()
            failed_job = next((j for j in jobs_resp.get("jobs", []) if j.get("conclusion") == "failure"), {})
            job_name = failed_job.get("name", "Unknown Job")

            root_cause = call_ai_service(
                "You are a CI/CD debugger. Extract root causes and suggest auto-fixes for failed workflow logs.",
                f"Repo: {repo}, Run ID: {run_id}, Job: {job_name}, Payload: {json.dumps(failed_job)[:3000]}"
            )

            db.collection("pipeline_failures").document(str(run_id)).set({
                "repo": repo,
                "run_id": run_id,
                "job_name": job_name,
                "analysis": root_cause,
                "timestamp": firestore.SERVER_TIMESTAMP,
                "auto_fixable": True
            })

            send_actionable_fcm(
                title=f"CI/CD Build Failure: {repo}",
                body=f"Job '{job_name}' failed. Tap to inspect and auto-fix.",
                data_payload={
                    "type": "workflow_failure",
                    "repo": repo,
                    "run_id": str(run_id)
                }
            )

    elif event == "issues" and payload.get("action") == "opened":
        issue = payload.get("issue", {})
        repo = payload.get("repository", {}).get("full_name")
        issue_body = f"Title: {issue.get('title')}\nBody: {issue.get('body')}"

        triage_prompt = (
            "Categorize this GitHub issue into (Bug, Feature, Chore), estimate resolution time in hours, "
            "and assign priority (P0, P1, P2, P3). Return JSON format: "
            "{\"category\": \"...\", \"estimated_hours\": 0, \"priority\": \"...\"}"
        )
        triage_result_raw = call_ai_service(triage_prompt, issue_body)
        try:
            triage_data = json.loads(triage_result_raw)
        except Exception:
            triage_data = {"category": "Bug", "estimated_hours": 2, "priority": "P1"}

        db.collection("task_queue").document(f"issue_{issue.get('id')}").set({
            "task_name": f"[{triage_data.get('priority')}] {issue.get('title')}",
            "source": "github_issue",
            "repo": repo,
            "category": triage_data.get("category"),
            "estimated_hours": triage_data.get("estimated_hours"),
            "status": "queued",
            "deadline": "End of Day",
            "created_at": firestore.SERVER_TIMESTAMP
        })

    return jsonify({"status": "received"}), 200

# ---------------------------------------------------------
# GitHub Action Execution API (Called by Flutter Notification Actions)
# ---------------------------------------------------------
@app.route("/api/github/pr-action", methods=["POST"])
def pr_action():
    data = request.json
    repo = data.get("repo")
    pr_number = data.get("pr_number")
    decision = data.get("decision")  # "approve_merge" or "deny_close"

    url = f"https://api.github.com/repos/{repo}/pulls/{pr_number}"
    headers = {"Authorization": f"token {GITHUB_TOKEN}", "Accept": "application/vnd.github.v3+json"}

    if decision == "approve_merge":
        merge_url = f"{url}/merge"
        resp = requests.put(merge_url, headers=headers, json={"commit_title": f"Merged PR #{pr_number} via Mobile App"})
        status = "merged" if resp.status_code == 200 else "failed"
    else:
        resp = requests.patch(url, headers=headers, json={"state": "closed"})
        status = "closed" if resp.status_code == 200 else "failed"

    db.collection("github_prs").document(f"{repo.replace('/', '_')}_{pr_number}").update({
        "status": status,
        "resolved_at": firestore.SERVER_TIMESTAMP
    })

    return jsonify({"status": status}), 200

# ---------------------------------------------------------
# 2. Telegram Bot Webhook & Task Injection
# ---------------------------------------------------------
@app.route("/webhooks/telegram", methods=["POST"])
def telegram_webhook():
    update = request.json
    message = update.get("message", {})
    callback_query = update.get("callback_query")

    if callback_query:
        chat_id = callback_query["message"]["chat"]["id"]
        command_code = callback_query["data"]
        handle_remote_script_trigger(chat_id, command_code)
        return jsonify({"status": "callback_handled"}), 200

    chat_id = message.get("chat", {}).get("id")
    text = message.get("text", "")
    voice = message.get("voice")

    if voice:
        file_id = voice.get("file_id")
        file_path_url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/getFile?file_id={file_id}"
        file_path = requests.get(file_path_url).json()["result"]["file_path"]
        voice_url = f"https://api.telegram.org/file/bot{TELEGRAM_BOT_TOKEN}/{file_path}"
        voice_data = requests.get(voice_url).content

        whisper_url = "https://api.openai.com/v1/audio/transcriptions"
        files = {"file": ("voice.oga", voice_data, "audio/ogg")}
        headers = {"Authorization": f"Bearer {OPENAI_API_KEY}"}
        whisper_resp = requests.post(whisper_url, headers=headers, files=files, data={"model": "whisper-1"})
        text = whisper_resp.json().get("text", "")

    if text:
        if text.startswith("/run"):
            keyboard = {
                "inline_keyboard": [
                    [{"text": "🔄 Restart Raspberry Pi Node", "callback_data": "restart_pi"}],
                    [{"text": "🚀 Deploy Vite Frontend", "callback_data": "deploy_vite"}],
                    [{"text": "🐍 Restart Flask Daemon", "callback_data": "restart_flask"}]
                ]
            }
            send_telegram_msg(chat_id, "Select execution pipeline target:", reply_markup=keyboard)
            return jsonify({"status": "command_prompted"}), 200

        task_nlp_prompt = (
            "Extract structured task from this message. "
            "Return valid JSON: {\"task_name\": \"...\", \"context\": \"...\", \"deadline\": \"...\"}"
        )
        task_info_raw = call_ai_service(task_nlp_prompt, text)
        try:
            task_obj = json.loads(task_info_raw)
        except Exception:
            task_obj = {"task_name": text, "context": "Telegram Quick Note", "deadline": "Flexible"}

        db.collection("task_queue").add({
            "task_name": task_obj.get("task_name"),
            "context": task_obj.get("context"),
            "deadline": task_obj.get("deadline"),
            "source": "telegram",
            "status": "pending",
            "created_at": firestore.SERVER_TIMESTAMP
        })
        send_telegram_msg(chat_id, f"✅ Task added to Unified Queue: {task_obj.get('task_name')}")

    return jsonify({"status": "ok"}), 200

def handle_remote_script_trigger(chat_id: int, command: str):
    scripts = {
        "restart_pi": "ssh -o StrictHostKeyChecking=no pi@raspberrypi.local 'sudo systemctl restart iot_daemon.service'",
        "deploy_vite": "npm --prefix /var/www/vite_frontend run build",
        "restart_flask": "sudo systemctl restart flask_devops.service"
    }
    cmd = scripts.get(command, "echo 'Unknown Command'")
    process = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    stdout, stderr = process.communicate()

    log_entry = {
        "command": command,
        "stdout": stdout,
        "stderr": stderr,
        "exit_code": process.returncode,
        "timestamp": firestore.SERVER_TIMESTAMP
    }
    db.collection("execution_logs").add(log_entry)
    send_telegram_msg(chat_id, f"Execution completed with code {process.returncode}.\nOutput:\n{stdout[:300]}")

def send_telegram_msg(chat_id: int, text: str, reply_markup=None):
    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
    payload = {"chat_id": chat_id, "text": text}
    if reply_markup:
        payload["reply_markup"] = reply_markup
    requests.post(url, json=payload)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", 8080)), debug=False)
