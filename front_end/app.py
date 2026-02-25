import os
import sys
import logging
import requests as req_lib

from flask import Flask, jsonify, render_template, send_from_directory
from flask_session import Session
from route_authentication import register_route_authentication
from route_user import register_route_user
from route_vm_management import register_route_vm_management
from route_scaling_management import register_route_scaling_management

# ===============================
# Logging Configuration

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ===============================
# Environment Variable Validation

REQUIRED_ENV_VARS = {
    "FLASK_KEY": "Secret key for Flask session signing",
    "CLIENT_ID": "Azure AD app registration client ID (frontend)",
    "TENANT_ID": "Azure AD tenant ID",
    "API_URL": "Base URL of the Linux Broker API (e.g. https://your-api.azurewebsites.net/api)",
    "API_CLIENT_ID": "Azure AD app registration client ID (API)",
    "MICROSOFT_PROVIDER_AUTHENTICATION_SECRET": "Azure AD client secret for authentication",
}

def validate_environment():
    missing = [key for key in REQUIRED_ENV_VARS if not os.environ.get(key)]
    if missing:
        logger.error("=" * 60)
        logger.error("FATAL: Missing required environment variables!")
        logger.error("=" * 60)
        for var in missing:
            logger.error("  %s — %s", var, REQUIRED_ENV_VARS[var])
        logger.error("")
        logger.error("Set these variables in App Service Configuration or in a .env file.")
        logger.error("See .env.template for descriptions and example values.")
        logger.error("=" * 60)
        sys.exit(1)

validate_environment()

# ===============================
# Flask App

app = Flask(__name__)
app.config['SECRET_KEY'] = os.environ.get('FLASK_KEY') 
app.config['SESSION_TYPE'] = 'filesystem'
app.config['VERSION'] = '0.111'
Session(app)

logger.info("Service Management Portal v%s started successfully.", app.config['VERSION'])

# ===============================
# General Routes

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/favicon.ico')
def favicon():
    return send_from_directory(os.path.join(app.root_path, 'static'), 'favicon.ico', mimetype='image/vnd.microsoft.icon')

# ===============================
# Authentication

register_route_authentication(app)

# ===============================
# User

register_route_user(app)

# ===============================
# VM Management

register_route_vm_management(app)

# ===============================
# Scaling and Scaling Rules

register_route_scaling_management(app)

# ===============================
# Health Check

@app.route('/health')
def health():
    api_url = os.environ.get('API_URL', '')
    api_reachable = False
    try:
        resp = req_lib.get(f"{api_url}/health", timeout=5)
        api_reachable = resp.status_code < 500
    except Exception:
        api_reachable = False

    return jsonify({
        "status": "healthy",
        "version": app.config['VERSION'],
        "api_reachable": api_reachable,
    }), 200

# ===============================
# Main

if __name__ == '__main__':
    app.run(debug=True)
