# MeMoSA Clinical Trial

MeMoSA Clinical Trial is a clinical-trial data platform for the CRMY MeMoSA team to validate an oral lesion AI diagnostic model using consented real-world patient data.

The product supports three operational roles:

- **Study Coordinator**: creates cases, submits complete datasets, and curates ground-truth evidence.
- **Clinician**: reviews undiagnosed lesions and records clinical diagnosis assessments.
- **Admin**: manages user access and exports Human-vs-AI comparison bundles for analysis.

## Project Overview

This monorepo combines a Flutter mobile app, a FastAPI backend, and a dedicated AI inference service.

Core mission:

1. Collect high-quality case data and lesion images in real clinical workflows.
2. Run AI predictions against the same cases.
3. Compare clinician, coordinator ground truth, and AI outputs in exportable datasets.

## System Architecture

At runtime, modules interact as follows:

1. The **mobile app** authenticates users with Firebase Authentication and sends role-based API requests to the backend.
2. For case submission, the app encrypts private payloads client-side, uploads encrypted blobs to Firebase Storage, and posts metadata + encryption envelopes to the backend.
3. The **backend** stores case records in Firestore and asynchronously queues AI inference jobs.
4. The backend decrypts the uploaded case image blob server-side, extracts 9 lesion images, and forwards them to the **AI service**.
5. The **AI service** returns per-image lesion predictions (`CANCER`, `OPMD`, `OTHER`), and the backend writes these into case diagnoses.
6. Admin users trigger export bundles containing structured mastersheets and supporting artifacts for Human-vs-AI evaluation.

## Monorepo Structure

| Path               | Purpose                                                                                                            |
| ------------------ | ------------------------------------------------------------------------------------------------------------------ |
| `ai/`              | FastAPI AI inference microservice (PyTorch model loading, image preprocessing, prediction API, Docker deployment). |
| `backend/`         | FastAPI backend for auth, role-based case workflows, invite/user management, and encrypted report exports.         |
| `mobile_app/`      | Flutter client used by Study Coordinators, Clinicians, and Admins.                                                 |
| `UAT-feedbacks.md` | User acceptance testing notes and feedback tracking.                                                               |

## Tech Stack

| Layer        | Primary Technologies                                                              | Notes                                                                 |
| ------------ | --------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| Mobile       | Flutter, Dart, Firebase SDKs, `http`, `shared_preferences`                        | Role-based UX, encrypted payload creation, API integrations.          |
| Backend API  | FastAPI, Uvicorn, Firebase Admin SDK, Firestore, Cloud Storage, `httpx`, `pandas` | RBAC, case lifecycle, export bundle generation.                       |
| AI Inference | FastAPI, PyTorch, torchvision, albumentations, PIL                                | DenseNet/EfficientNet checkpoint inference for lesion classification. |
| Data/Storage | Firebase Authentication, Firestore, Firebase Storage                              | User identity, case documents, encrypted blob storage.                |
| Security     | AES encryption + passphrase-wrapped AES key flow                                  | Sensitive case data encrypted before storage/transit.                 |
| Deployment   | Docker, Google Cloud Run (documented workflows)                                   | Separate deployable containers for backend and AI.                    |

## Infrastructure and DevOps (GCP + Firebase)

The production stack is hosted on **Google Cloud Platform** and **Firebase**, with containerized backend/AI services on **Cloud Run** and source control in GitHub.

### CI/CD Pipeline (GitHub -> Cloud Build -> Cloud Run)

Deployment flow:

1. A change is merged/pushed to the `master` branch.
2. The GitHub-connected Cloud Build trigger starts automatically.
3. Cloud Build builds the target container image.
4. Cloud Build deploys a new Cloud Run revision for the service (backend or AI).
5. Cloud Run serves traffic to the latest healthy revision.

Operational notes:

- Keep trigger enabled in Cloud Build (`Triggers` page).
- Confirm each service allows intended access mode (public/internal) under Cloud Run `Security`.
- Store runtime secrets in Secret Manager and reference them in Cloud Run revisions (details in `backend/README.md`).

### Maintenance and Monitoring

#### Budgeting and Cost Alerts

Set up budget alerts in GCP:

1. Go to **Billing -> Budgets & alerts**.
2. Create a budget scoped to the MeMoSA billing account/project.
3. Add threshold rules (recommended: `50%`, `75%`, `90%`, `100%`).
4. Add notification recipients (engineering + project stakeholders).
5. Review monthly and adjust budget baseline as trial volume grows.

#### Uptime and Incident Alerting (AI Inference Service Down)

Create a log-based alert policy in Cloud Monitoring for AI service downtime:

1. Open **Logging -> Logs Explorer**.
2. Select the AI Cloud Run service resource.
3. Build a query for failure indicators (for example, startup failures, repeated 5xx, crash loops, or health check failures).
4. Save as a **log-based metric** or directly create an **alert policy** from query.
5. Configure condition and notification channel (email/Slack/PagerDuty).
6. Name the policy clearly, e.g. `AI Inference Service Down`.

Recommended signal coverage:

- Cloud Run revision not serving traffic
- sustained 5xx response spikes
- model load/download failures at startup

### App Migration and Handover Summary

Handover phases for CRMY ownership:

1. **Codebase Handover**
   - Transfer repositories, branch protections, and deployment trigger ownership.
   - Validate local runbooks for mobile, backend, and AI services.
2. **Firebase Foundation**
   - Provision CRMY Firebase project.
   - Recreate Auth/Firestore/Storage configuration and security rules.
   - Update client/server Firebase credentials and verify end-to-end auth/data access.
3. **GCP Setup**
   - Provision Cloud Run services, Cloud Build triggers, and Secret Manager entries.
   - Configure IAM/service accounts and operational monitoring (budget + uptime alerts).
   - Execute smoke tests for login, case submission, AI inference, and export bundle generation.

## Global Setup

These steps run the full environment locally.

### 1) Prerequisites

- Python `3.10+`
- Flutter SDK (stable channel)
- Docker Desktop
- Firebase project credentials/configuration for this trial

### 2) Clone and prepare

```bash
git clone <repository-url>
cd memosa-clinical-platform
```

### 3) Configure environment variables

Create local `.env` files from examples:

- `backend/.env` from `backend/.env.example`
- `ai/.env` from `ai/.env.example`
- `mobile_app/.env` (set backend base URL and other app values used by your environment)

Important shared values:

- `PASSWORD` (backend + mobile encryption/decryption compatibility)
- `GOOGLE_CLOUD_PROJECT` (AI model download on Cloud Run)
- backend AI endpoint value (`AI_URL`) when backend calls deployed AI service

### 4) Start backend container

```bash
docker build -t memosa-ct-backend backend/
docker run --rm -it -p 8000:8080 \
  -v "$(pwd)/backend/secrets:/backend/secrets" \
  --env-file backend/.env \
  --name backend-service \
  memosa-ct-backend
```

### 5) Start AI container

```bash
docker build -t memosa-ct-ai ai/
docker run --rm -it -p 8001:8080 \
  -v "$(pwd)/ai/models:/ai/models" \
  --env-file ai/.env \
  --name ai-service \
  memosa-ct-ai
```

### 6) Start Flutter mobile app

```bash
cd mobile_app
flutter pub get
flutter run
```

### 7) Verify services

- Backend docs: `http://127.0.0.1:8000/docs`
- AI docs: `http://127.0.0.1:8001/docs`
- Mobile app: launch on emulator/device and authenticate using configured roles.

## Additional Module Documentation

- `ai/README.md` for model and inference pipeline details
- `backend/README.md` for API/RBAC/export details
- `mobile_app/README.md` for app setup, persona flows, and release build steps
