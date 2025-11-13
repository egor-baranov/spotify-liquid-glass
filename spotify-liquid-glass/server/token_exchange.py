import base64
import os
from dataclasses import dataclass

from flask import Flask, request, jsonify
import requests
from dotenv import load_dotenv

load_dotenv()

@dataclass
class Config:
    client_id: str
    client_secret: str
    redirect_uri: str
    port: int = 5001

    @staticmethod
    def from_env() -> "Config":
        missing = []
        client_id = os.getenv("SPOTIFY_CLIENT_ID")
        if not client_id:
            missing.append("SPOTIFY_CLIENT_ID")
        client_secret = os.getenv("SPOTIFY_CLIENT_SECRET")
        if not client_secret:
            missing.append("SPOTIFY_CLIENT_SECRET")
        redirect_uri = os.getenv("REDIRECT_URI", "spotify-liquid-glass://auth")
        if missing:
            raise RuntimeError(f"Missing environment variables: {', '.join(missing)}")
        port = int(os.getenv("PORT", "5001"))
        return Config(client_id, client_secret, redirect_uri, port)

config = Config.from_env()
app = Flask(__name__)

SPOTIFY_TOKEN_URL = "https://accounts.spotify.com/api/token"

def _basic_auth_header() -> str:
    raw = f"{config.client_id}:{config.client_secret}".encode("utf-8")
    return "Basic " + base64.b64encode(raw).decode("utf-8")

@app.post("/exchange")
def exchange_code():
    payload = request.get_json(silent=True) or {}
    code = payload.get("code")
    if not code:
        return jsonify({"error": "missing `code`"}), 400

    data = {
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": config.redirect_uri,
    }
    headers = {
        "Content-Type": "application/x-www-form-urlencoded",
        "Authorization": _basic_auth_header(),
    }
    response = requests.post(SPOTIFY_TOKEN_URL, data=data, headers=headers, timeout=10)
    return jsonify(response.json()), response.status_code

@app.post("/refresh")
def refresh_token():
    payload = request.get_json(silent=True) or {}
    refresh_token = payload.get("refresh_token")
    if not refresh_token:
        return jsonify({"error": "missing `refresh_token`"}), 400

    data = {
        "grant_type": "refresh_token",
        "refresh_token": refresh_token,
    }
    headers = {
        "Content-Type": "application/x-www-form-urlencoded",
        "Authorization": _basic_auth_header(),
    }
    response = requests.post(SPOTIFY_TOKEN_URL, data=data, headers=headers, timeout=10)
    return jsonify(response.json()), response.status_code

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=config.port, debug=True)
