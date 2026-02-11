# Semaphore UI - Ansible Automation Platform

## Overview

Semaphore UI is a modern, responsive web interface for Ansible, Terraform, OpenTofu, and Pulumi. It provides a centralized platform for managing and executing infrastructure automation tasks with features like:

- **Task Execution**: Run Ansible playbooks and Terraform plans through an intuitive web interface
- **Access Control**: Role-based access control (RBAC) for team collaboration
- **Task History**: Complete audit trail of all automation tasks
- **Notifications**: Integration with Slack, Telegram, email, and webhooks
- **Scheduling**: Schedule automated tasks with cron expressions
- **Real-time Logs**: Live task output and execution logs
- **Git Integration**: Sync playbooks and configurations from Git repositories

## Architecture Integration

Semaphore UI integrates with your existing infrastructure:

```
┌─────────────────────────────────────────────────────────────┐
│                        Traefik Proxy                         │
│                 (TLS/SSL + Load Balancing)                   │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ HTTPS
                       │
┌──────────────────────▼──────────────────────────────────────┐
│                     Semaphore UI                             │
│                                                               │
│  ┌───────────────┐    ┌──────────────┐   ┌───────────────┐ │
│  │   Web UI      │    │   API Server │   │  Task Runner  │ │
│  └───────────────┘    └──────────────┘   └───────────────┘ │
│                                                               │
│  ┌───────────────────────────────────────────────────────┐  │
│  │              BoltDB / PostgreSQL                       │  │
│  └───────────────────────────────────────────────────────┘  │
└───────────────────────┬───────────────────────────────────┘
                        │
                        │ Executes
                        │
┌───────────────────────▼───────────────────────────────────┐
│              Your Ansible Playbooks                        │
│              (/var/opt/manage/control-center/ansible/)    │
└────────────────────────────────────────────────────────────┘
```

## Installation

### Quick Start

Run the automated setup script:

```bash
cd /var/opt/manage/control-center/scripts
./setup-semaphore.sh
```

Select option **6** for full setup, which will:
1. Generate encryption keys
2. Configure admin credentials
3. Set up your domain
4. Verify networks
5. Deploy the stack

### Manual Setup

If you prefer manual setup:

#### 1. Generate Encryption Keys

```bash
# Generate three random keys
openssl rand -base64 32  # For SEMAPHORE_ACCESS_KEY_ENCRYPTION
openssl rand -base64 32  # For SEMAPHORE_COOKIE_HASH
openssl rand -base64 32  # For SEMAPHORE_COOKIE_ENCRYPTION
```

#### 2. Update .env File

Edit `/var/opt/manage/control-center/.env` and set:

```bash
SEMAPHORE_ADMIN=admin
SEMAPHORE_ADMIN_PASSWORD=your_secure_password
SEMAPHORE_ADMIN_NAME=Administrator
SEMAPHORE_ADMIN_EMAIL=admin@yourdomain.com
SEMAPHORE_ACCESS_KEY_ENCRYPTION=<generated_key_1>
SEMAPHORE_COOKIE_HASH=<generated_key_2>
SEMAPHORE_COOKIE_ENCRYPTION=<generated_key_3>
```

#### 3. Update Domain

Edit `/var/opt/manage/control-center/docker-compose-examples/semaphore-stack.yml` and replace:
- `semaphore.yourdomain.com` with your actual domain

#### 4. Ensure Networks Exist

```bash
docker network create --driver=overlay --attachable management
docker network create --driver=overlay --attachable traefik-public
```

#### 5. Deploy Stack

```bash
cd /var/opt/manage/control-center
docker stack deploy -c docker-compose-examples/semaphore-stack.yml semaphore
```

## Configuration

### Database Options

#### BoltDB (Default - Embedded)
- **Pros**: No external database required, simple setup
- **Cons**: Single-file database, not suitable for high-load scenarios
- **Best for**: Small to medium deployments, testing

The default configuration uses BoltDB:
```yaml
SEMAPHORE_DB_DIALECT: bolt
SEMAPHORE_DB: /etc/semaphore/database.boltdb
```

#### PostgreSQL (Production)
- **Pros**: Better performance, scalability, concurrent access
- **Cons**: Requires separate database service
- **Best for**: Production environments, multiple users

To use PostgreSQL, uncomment the `semaphore-postgres` service in the compose file and update:
```yaml
SEMAPHORE_DB_DIALECT: postgres
SEMAPHORE_DB_HOST: semaphore-postgres
SEMAPHORE_DB_PORT: 5432
SEMAPHORE_DB_USER: semaphore
SEMAPHORE_DB_PASS: <password>
SEMAPHORE_DB_NAME: semaphore
```

### Notification Configuration

#### Email Notifications

```bash
SEMAPHORE_EMAIL_SENDER=semaphore@yourdomain.com
SEMAPHORE_EMAIL_HOST=smtp.gmail.com
SEMAPHORE_EMAIL_PORT=587
SEMAPHORE_EMAIL_USERNAME=your-email@gmail.com
SEMAPHORE_EMAIL_PASSWORD=your-app-password
```

#### Slack Integration

```bash
SEMAPHORE_SLACK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

#### Telegram Integration

```bash
SEMAPHORE_TELEGRAM_TOKEN=your-bot-token
SEMAPHORE_TELEGRAM_CHAT=your-chat-id
```

### Volume Mounts

The stack mounts your existing Ansible directory as read-only:

```yaml
volumes:
  - /var/opt/manage/control-center/ansible:/ansible:ro
```

This allows Semaphore to access your playbooks without copying them.

## Usage Guide

### First Login

1. Navigate to `https://semaphore.yourdomain.com`
2. Login with the admin credentials you configured
3. You'll be greeted with the dashboard

### Setting Up Your First Project

#### 1. Create a Key Store

Keys are used for authentication (SSH keys, vault passwords, etc.):

1. Go to **Key Store** in the sidebar
2. Click **New Key**
3. Select type:
   - **SSH Key**: For connecting to remote servers
   - **Login Password**: For sudo passwords
   - **None**: For local execution
4. Save the key

#### 2. Create an Environment

Environments contain variables for your playbooks:

1. Go to **Environment** in the sidebar
2. Click **New Environment**
3. Add your variables in JSON format:
```json
{
  "ansible_user": "deploy",
  "ansible_become": true,
  "ansible_become_method": "sudo"
}
```

#### 3. Create a Repository

Repositories define where your Ansible code lives:

1. Go to **Repositories** in the sidebar
2. Click **New Repository**
3. Options:
   - **Local**: Use mounted volumes (e.g., `/ansible`)
   - **Git**: Clone from Git repository
   - **Git (SSH)**: Clone via SSH with key authentication

For your existing playbooks:
- **URL**: `/ansible` (local path)
- **Branch**: leave empty for local

#### 4. Create an Inventory

Inventories define target hosts:

1. Go to **Inventory** in the sidebar
2. Click **New Inventory**
3. Options:
   - **Static**: Paste inventory file content
   - **File**: Reference inventory file in repository

Example static inventory:
```ini
[managers]
manager-1 ansible_host=10.10.1.1
manager-2 ansible_host=10.10.1.2

[workers]
worker-1 ansible_host=10.10.2.1
worker-2 ansible_host=10.10.2.2
```

#### 5. Create a Template (Task)

Templates define what to run:

1. Go to **Task Templates** in the sidebar
2. Click **New Template**
3. Fill in:
   - **Name**: e.g., "Deploy WordPress"
   - **Playbook**: Path to playbook (e.g., `deploy.yml`)
   - **Inventory**: Select the inventory
   - **Repository**: Select the repository
   - **Environment**: Select the environment
   - **Vault Password**: If using Ansible Vault
4. **Optional**: Add survey variables for runtime input

### Running Tasks

#### Manual Execution

1. Go to **Task Templates**
2. Click the **Run** button on your template
3. Optionally add/override variables
4. Click **Run**
5. View real-time logs in the task view

#### Scheduled Execution

1. Edit a task template
2. Enable **Schedule**
3. Add cron expression (e.g., `0 2 * * *` for 2 AM daily)
4. Save

### Monitoring Tasks

- **Dashboard**: Overview of recent tasks and activity
- **Task History**: Complete history with logs and status
- **Real-time Logs**: Stream output as tasks execute
- **Notifications**: Receive alerts on task completion/failure

## Integration with Existing Ansible Setup

Your current Ansible setup is already mounted in Semaphore:

```
/var/opt/manage/control-center/ansible/ (host)
  ↓
/ansible/ (in Semaphore container)
```

### Using Your Existing Playbooks

When creating repositories in Semaphore:
- **URL/Path**: `/ansible`
- **Playbook paths**: 
  - `deploy.yml`
  - `backup.yml`
  - `dns.yml`
  - etc.

### Using Your Existing Inventory

Reference your static inventory:
- In the repository: `/ansible/inventory/static.yml`

### Using Your Existing Roles

Your roles directory is already available:
- Roles path: `/ansible/roles/`

## Security Best Practices

### 1. Strong Admin Password

Change the default admin password immediately:
```bash
# In .env file
SEMAPHORE_ADMIN_PASSWORD=<strong-random-password>
```

### 2. HTTPS Only

Traefik is configured to force HTTPS with Let's Encrypt certificates automatically.

### 3. Access Control

Configure additional users with appropriate roles:
- **Admin**: Full access
- **Engineer**: Can run and modify tasks
- **Guest**: Read-only access

### 4. SSH Key Management

Store SSH keys securely in Semaphore's Key Store rather than embedding in playbooks.

### 5. Vault Passwords

Use Ansible Vault for sensitive variables and configure vault passwords in Semaphore.

### 6. Audit Logging

All task executions are logged with:
- Who ran the task
- When it was run
- What parameters were used
- Complete output logs

## Advanced Configuration

### Custom Ansible Configuration

Mount a custom `ansible.cfg`:

```yaml
volumes:
  - /var/opt/manage/control-center/ansible/ansible.cfg:/etc/ansible/ansible.cfg:ro
```

### Python Dependencies

If your playbooks require additional Python packages:

1. Create a custom Dockerfile:
```dockerfile
FROM semaphoreui/semaphore:latest

RUN apk add --no-cache \
    python3-dev \
    py3-pip \
    && pip3 install \
        boto3 \
        kubernetes \
        openshift
```

2. Build and use the custom image

### Multiple Ansible Versions

You can run different Ansible versions by mounting different virtual environments or using different container images.

## Troubleshooting

### Check Service Status

```bash
# View service status
docker service ps semaphore_semaphore

# View logs
docker service logs -f semaphore_semaphore

# Check if service is healthy
docker service inspect semaphore_semaphore --format='{{.Spec.TaskTemplate.ContainerSpec.Healthcheck}}'
```

### Common Issues

#### Cannot Connect to Database

Check volume mounts and permissions:
```bash
docker exec -it $(docker ps -q -f name=semaphore_semaphore) ls -la /etc/semaphore/
```

#### Ansible Playbook Not Found

Verify the mount:
```bash
docker exec -it $(docker ps -q -f name=semaphore_semaphore) ls -la /ansible/
```

#### SSH Connection Fails

- Verify SSH keys are correctly configured in Key Store
- Check network connectivity from Semaphore container to target hosts
- Ensure target hosts have the correct SSH keys authorized

#### Tasks Hang or Timeout

- Increase timeout in task template settings
- Check if playbook requires interactive input (not supported)
- Review task logs for errors

### Reset Admin Password

If you forget the admin password:

1. Stop the service:
```bash
docker service scale semaphore_semaphore=0
```

2. Update password in .env file

3. Remove the database volume to recreate:
```bash
docker volume rm semaphore_semaphore-data
```

4. Restart the service:
```bash
docker service scale semaphore_semaphore=1
```

## Maintenance

### Backup

#### BoltDB Backup

```bash
# The database is stored in the volume
docker run --rm \
  -v semaphore_semaphore-data:/data \
  -v /backup:/backup \
  alpine \
  tar czf /backup/semaphore-backup-$(date +%Y%m%d).tar.gz -C /data .
```

#### PostgreSQL Backup

```bash
docker exec $(docker ps -q -f name=semaphore-postgres) \
  pg_dump -U semaphore semaphore > semaphore-backup-$(date +%Y%m%d).sql
```

### Restore

#### BoltDB Restore

```bash
docker run --rm \
  -v semaphore_semaphore-data:/data \
  -v /backup:/backup \
  alpine \
  tar xzf /backup/semaphore-backup-YYYYMMDD.tar.gz -C /data
```

### Updates

Semaphore updates are handled by Shepherd or Watchtower:

```bash
# Manual update
docker service update --image semaphoreui/semaphore:latest semaphore_semaphore
```

## API Access

Semaphore provides a REST API for automation:

### Authentication

```bash
# Get API token from UI: User menu → API Tokens

# Use in requests
curl -H "Authorization: Bearer YOUR_TOKEN" \
  https://semaphore.yourdomain.com/api/projects
```

### Common Endpoints

```bash
# List projects
GET /api/projects

# Run a task
POST /api/project/{project_id}/tasks

# Get task status
GET /api/project/{project_id}/tasks/{task_id}

# Get task output
GET /api/project/{project_id}/tasks/{task_id}/output
```

Full API documentation: https://docs.ansible-semaphore.com/api-reference

## Resources

- **Official Documentation**: https://docs.ansible-semaphore.com/
- **GitHub Repository**: https://github.com/ansible-semaphore/semaphore
- **Docker Hub**: https://hub.docker.com/r/semaphoreui/semaphore
- **Community Forum**: https://github.com/ansible-semaphore/semaphore/discussions

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review logs: `docker service logs -f semaphore_semaphore`
3. Consult official documentation
4. Open an issue on GitHub

---

**Next Steps:**
1. Run the setup script: `./scripts/setup-semaphore.sh`
2. Access the web interface
3. Create your first project
4. Import your existing Ansible playbooks
5. Start automating!
