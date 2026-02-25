import os
import sys
import logging

logger = logging.getLogger(__name__)

TENANT_ID = os.environ.get("TENANT_ID")
AUTHORITY = f"https://login.microsoftonline.com/{TENANT_ID}"
VM_SUBSCRIPTION_ID = os.environ.get("VM_SUBSCRIPTION_ID")
VM_RESOURCE_GROUP = os.environ.get("VM_RESOURCE_GROUP")
CLIENT_ID = os.environ.get("CLIENT_ID")
MICROSOFT_PROVIDER_AUTHENTICATION_SECRET = os.environ.get("MICROSOFT_PROVIDER_AUTHENTICATION_SECRET")
APP_URI = f"api://{CLIENT_ID}"
AVD_HOST_GROUP_ID = os.environ.get('AVD_HOST_GROUP_ID')
LINUX_HOST_GROUP_ID = os.environ.get('LINUX_HOST_GROUP_ID')
LINUX_HOST_ADMIN_LOGIN_NAME = os.environ.get('LINUX_HOST_ADMIN_LOGIN_NAME')
GRAPH_API_ENDPOINT = os.environ.get('GRAPH_API_ENDPOINT')
DOMAIN_NAME = os.environ.get('DOMAIN_NAME')
VAULT_URL = os.environ.get('VAULT_URL')
KEY_NAME = os.environ.get('KEY_NAME')
DB_SERVER = os.environ.get('DB_SERVER')
DB_DATABASE = os.environ.get('DB_DATABASE')
DB_USERNAME = os.environ.get('DB_USERNAME')
DB_PASSWORD_NAME = os.environ.get('DB_PASSWORD_NAME')
NFS_SHARE = os.environ.get("NFS_SHARE")

db_password = None

# ---------------------------------------------------------------------------
# Startup validation — fail early with clear error messages
# ---------------------------------------------------------------------------

REQUIRED_ENV_VARS = {
    "TENANT_ID": "Azure AD Tenant ID",
    "CLIENT_ID": "API App Registration Client ID",
    "MICROSOFT_PROVIDER_AUTHENTICATION_SECRET": "App Registration secret for auth provider",
    "VM_SUBSCRIPTION_ID": "Azure Subscription ID for Linux VMs",
    "VM_RESOURCE_GROUP": "Resource Group containing Linux VMs",
    "AVD_HOST_GROUP_ID": "Azure AD Security Group ID for AVD hosts",
    "LINUX_HOST_GROUP_ID": "Azure AD Security Group ID for Linux hosts",
    "LINUX_HOST_ADMIN_LOGIN_NAME": "Admin login name on Linux VMs",
    "GRAPH_API_ENDPOINT": "Microsoft Graph API scope",
    "DOMAIN_NAME": "Azure AD domain name",
    "VAULT_URL": "Azure Key Vault URI",
    "KEY_NAME": "Key Vault secret name for SSH PEM key",
    "DB_SERVER": "Azure SQL Server hostname",
    "DB_DATABASE": "SQL database name",
    "DB_USERNAME": "SQL admin username",
    "DB_PASSWORD_NAME": "Key Vault secret name for DB password",
}


def validate_environment():
    """Check that all required environment variables are set.
    Logs missing variables and exits if any are absent.
    """
    missing = [
        f"  - {var} ({desc})"
        for var, desc in REQUIRED_ENV_VARS.items()
        if not os.environ.get(var)
    ]

    if missing:
        msg = (
            "\n========================================\n"
            " STARTUP ERROR: Missing environment variables\n"
            "========================================\n"
            "The following required environment variables are not set:\n\n"
            + "\n".join(missing)
            + "\n\nSet these in App Service > Configuration > Application Settings,\n"
            "or see .env.template at the repository root for descriptions.\n"
            "========================================\n"
        )
        logger.error(msg)
        print(msg, file=sys.stderr)
        sys.exit(1)

    logger.info("All required environment variables are present.")


validate_environment()