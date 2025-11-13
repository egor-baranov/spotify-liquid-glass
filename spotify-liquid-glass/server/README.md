# Spotify Token Exchange (Local Dev)

A minimal Flask service for exchanging Spotify authorization codes and refreshing tokens.

## Setup

```bash
cd server
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

Edit `.env` with your real credentials.

## Run

```bash
source .venv/bin/activate
python token_exchange.py
```

The service runs on `http://127.0.0.1:5001` by default.

## Endpoints

* `POST /exchange` `{ "code": "<auth_code>" }`
* `POST /refresh` `{ "refresh_token": "<refresh_token>" }`
