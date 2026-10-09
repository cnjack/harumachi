"""Use the already configured Hyper3D MCP connection without exposing credentials.

No login or account switch is performed. An expired OAuth token is refreshed with
the existing client and refresh token; server/tool errors are never resubmitted.
"""
import argparse
import json
import os
from pathlib import Path
import ssl
import time
import urllib.error
import urllib.parse
import urllib.request

SERVER = "https://api.hyper3d.com/api/mcp"
CA = "/opt/homebrew/etc/ca-certificates/cert.pem"


class RodinMCP:
    def __init__(self):
        self.context = ssl.create_default_context(cafile=CA)
        root = Path.home() / ".copilot/mcp-oauth-config"
        configs = []
        for path in root.glob("*.json"):
            if path.name.endswith(".tokens.json"):
                continue
            data = json.loads(path.read_text())
            if data.get("serverUrl") == SERVER:
                configs.append((path, data))
        if len(configs) != 1:
            raise RuntimeError("Expected exactly one existing Hyper3D OAuth connection")
        path, self.config = configs[0]
        self.token_path = path.with_name(path.stem + ".tokens.json")
        self.tokens = json.loads(self.token_path.read_text())
        self.session = None
        self.request_id = 0
        if self.tokens.get("expiresAt", 0) <= time.time() + 30:
            self.refresh()
        self.rpc("initialize", {
            "protocolVersion": "2025-03-26", "capabilities": {},
            "clientInfo": {"name": "harumachi-assets", "version": "1.0"},
        })

    def refresh(self):
        issuer = self.config["authorizationServerUrl"]
        metadata = self.http(issuer + "/.well-known/oauth-authorization-server")
        endpoint = metadata["token_endpoint"]
        if urllib.parse.urlparse(endpoint).netloc != urllib.parse.urlparse(SERVER).netloc:
            raise RuntimeError("OAuth endpoint does not match the configured Hyper3D host")
        payload = urllib.parse.urlencode({
            "grant_type": "refresh_token", "client_id": self.config["clientId"],
            "refresh_token": self.tokens["refreshToken"],
        }).encode()
        new = self.http(endpoint, payload, {"Content-Type": "application/x-www-form-urlencoded"})
        if "access_token" not in new:
            raise RuntimeError("Existing Hyper3D OAuth connection could not refresh")
        self.tokens["accessToken"] = new["access_token"]
        self.tokens["expiresAt"] = int(time.time()) + int(new.get("expires_in", 3600))
        if "refresh_token" in new:
            self.tokens["refreshToken"] = new["refresh_token"]
        if "scope" in new:
            self.tokens["scope"] = new["scope"]
        temp = self.token_path.with_suffix(".refresh.tmp")
        fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as stream:
            json.dump(self.tokens, stream)
        os.replace(temp, self.token_path)

    def http(self, url, data=None, headers=None):
        request = urllib.request.Request(url, data=data, headers=headers or {})
        try:
            with urllib.request.urlopen(request, context=self.context, timeout=90) as response:
                self.session = response.headers.get("Mcp-Session-Id", getattr(self, "session", None))
                raw = response.read().decode()
                if response.headers.get("Content-Type", "").startswith("text/event-stream"):
                    events = [json.loads(line[6:]) for line in raw.splitlines() if line.startswith("data: ")]
                    return next(item for item in reversed(events) if "result" in item or "error" in item)
                return json.loads(raw) if raw.strip() else {}
        except urllib.error.HTTPError as error:
            # Report only a standard error code; never echo authentication data.
            try:
                payload = json.loads(error.read())
                code = payload.get("error", "")
                code = code if isinstance(code, str) and len(code) < 80 else ""
            except (ValueError, TypeError):
                code = ""
            raise RuntimeError(f"Hyper3D HTTP {error.code} {code}; no automatic generation retry") from None

    def rpc(self, method, params):
        # Long generations may outlive the OAuth access token. Renew reads on
        # the existing principal; never resubmit a paid generation on failure.
        if method != 'initialize' and self.tokens.get('expiresAt', 0) <= time.time() + 30:
            stored = json.loads(self.token_path.read_text())
            if stored.get('expiresAt', 0) > self.tokens.get('expiresAt', 0):
                self.tokens = stored
            if self.tokens.get('expiresAt', 0) <= time.time() + 30:
                self.refresh()
        self.request_id += 1
        headers = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream",
                   "Authorization": "Bearer " + self.tokens["accessToken"]}
        if self.session:
            headers["Mcp-Session-Id"] = self.session
            headers["MCP-Protocol-Version"] = "2025-03-26"
        message = {"jsonrpc": "2.0", "id": self.request_id, "method": method, "params": params}
        response = self.http(SERVER, json.dumps(message).encode(), headers)
        if "error" in response:
            raise RuntimeError("Hyper3D RPC failed: " + json.dumps(response["error"]))
        return response["result"]

    def call(self, name, arguments):
        return self.rpc("tools/call", {"name": name, "arguments": arguments})


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["list", "call"])
    parser.add_argument("--name")
    parser.add_argument("--args", default="{}")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    client = RodinMCP()
    result = client.rpc("tools/list", {}) if args.action == "list" else client.call(args.name, json.loads(args.args))
    target = Path(args.out)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2))
    if args.action == "list":
        print(json.dumps([tool["name"] for tool in result["tools"]]))
    else:
        print(json.dumps({"saved": str(target), "isError": result.get("isError", False)}))
