"""Petite application Flask de démonstration pour le pipeline Jenkins."""
import os

from flask import Flask, jsonify

app = Flask(__name__)


def add(a, b):
    """Additionne deux nombres."""
    return a + b


def app_version():
    """Version injectée au build de l'image (ARG/ENV APP_VERSION)."""
    return os.environ.get("APP_VERSION", "dev")


@app.route("/")
def index():
    return jsonify(message="Hello Jenkins", status="ok", version=app_version())


@app.route("/health")
def health():
    return jsonify(status="up")


@app.route("/add/<int:a>/<int:b>")
def add_route(a, b):
    return jsonify(result=add(a, b))


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
