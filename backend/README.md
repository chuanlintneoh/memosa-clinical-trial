# Backend Module (`/backend`)

This service is the central orchestration layer of the MeMoSA Clinical Trial. It enforces role-based access, stores encrypted case records, coordinates AI inference, and generates export bundles for trial analysis.

## API Documentation

Base app: FastAPI (`app/main.py`)

- Root health route: `GET /`
- OpenAPI docs: `/docs`

### Authentication Routes (`/auth`)

| Method | Endpoint         | Access                        | Purpose                                                                |
| ------ | ---------------- | ----------------------------- | ---------------------------------------------------------------------- |
| `POST` | `/auth/register` | Public (invite code required) | Register a new user and assign role claim in Firebase Auth.            |
| `GET`  | `/auth/login`    | Authenticated                 | Return user profile (uid, email, role, name) after token verification. |

### Case and Diagnosis Routes (`/dbmanager`)

| Method  | Endpoint                                      | Access            | Purpose                                                              |
| ------- | --------------------------------------------- | ----------------- | -------------------------------------------------------------------- |
| `POST`  | `/dbmanager/case/create?case_id=...`          | Study Coordinator | Create a new case and enqueue background AI inference job.           |
| `GET`   | `/dbmanager/case/get/{case_id}`               | Study Coordinator | Retrieve case by case ID.                                            |
| `PATCH` | `/dbmanager/case/edit?case_id=...`            | Study Coordinator | Update existing case fields (including ground-truth related fields). |
| `GET`   | `/dbmanager/cases/list`                       | Study Coordinator | Paginated case list with date and ownership filters.                 |
| `GET`   | `/dbmanager/cases/undiagnosed/{clinician_id}` | Clinician         | Fetch recent cases missing this clinician's diagnosis entries.       |
| `PATCH` | `/dbmanager/case/diagnose?case_id=...`        | Clinician         | Submit clinician diagnosis payload for one case.                     |
| `POST`  | `/dbmanager/bundle/export?include_all=...`    | Admin             | Generate encrypted export bundle and return signed download URL.     |

### Invite Code Routes (`/invite-manager`)

| Method   | Endpoint                   | Access | Purpose                                                     |
| -------- | -------------------------- | ------ | ----------------------------------------------------------- |
| `POST`   | `/invite-manager/generate` | Admin  | Generate invite code with optional role/email restrictions. |
| `POST`   | `/invite-manager/validate` | Public | Validate invite code during registration flow.              |
| `GET`    | `/invite-manager/list`     | Admin  | List invite codes created by current admin.                 |
| `GET`    | `/invite-manager/list/all` | Admin  | List all invite codes in system.                            |
| `DELETE` | `/invite-manager/revoke`   | Admin  | Revoke (deactivate) invite code.                            |
| `GET`    | `/invite-manager/{code}`   | Admin  | View invite code details.                                   |

### User Management Routes (`/user-manager`)

| Method   | Endpoint                                | Access | Purpose                                              |
| -------- | --------------------------------------- | ------ | ---------------------------------------------------- |
| `GET`    | `/user-manager/users/list`              | Admin  | Paginated user list with optional role/name filters. |
| `GET`    | `/user-manager/user/get/{user_id}`      | Admin  | Retrieve user profile.                               |
| `PATCH`  | `/user-manager/user/edit?user_id=...`   | Admin  | Edit allowed fields (`email`, `name`).               |
| `DELETE` | `/user-manager/user/delete?user_id=...` | Admin  | Disable or hard-delete user.                         |
| `PATCH`  | `/user-manager/user/reactivate`         | Admin  | Reactivate disabled user.                            |

## Database Schema (High-Level)

Primary data store: Firestore.

### `cases` Collection

Each document is keyed by `case_id` and includes:

| Field Group                          | Example Fields                                                         | Description                                                            |
| ------------------------------------ | ---------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| Metadata                             | `created_at`, `created_by`, `submitted_at`                             | Case lifecycle and ownership metadata.                                 |
| Public clinical fields               | habit/clinical fields, comments envelope                               | Coordinator-submitted non-blob metadata.                               |
| Encrypted private payload references | `encrypted_blob { url, iv }`, `encrypted_aes { ciphertext, iv, salt }` | Storage pointer and key-wrapping envelope for private data decryption. |
| Diagnoses array                      | `diagnoses[]`                                                          | Per-image objects that store AI and clinician/ground-truth values.     |
| Ground truth / reports               | biopsy / COE fields, `biopsy_report` refs                              | Curated reference outcomes and report attachments.                     |

Diagnosis entries include AI and human dimensions:

- `ai_lesion_type`
- clinician-specific nested diagnosis objects keyed by clinician UID
- coordinator-added `biopsy_*` / `coe_*` details for ground truth comparison

### `users` Collection

Document key is Firebase UID, typically containing:

- `email`, `name`, `role`
- `created_at`
- optional status fields (`disabled`, `reactivated`) and timestamps
- invite code traceability (`invite_code_used`)

### Supporting Collections

- Invite code storage used by `/invite-manager` flows.

## Auth Logic and RBAC

Authentication and authorization are implemented via Firebase ID tokens:

1. Client sends `Authorization: Bearer <id_token>`.
2. Backend verifies token via Firebase Admin (`auth.verify_id_token`).
3. Role claims (`role`) are compared against endpoint-required role.
4. Unauthorized/role mismatch requests return `403`; invalid tokens return `401`.

Role model:

- **Study Coordinator**: case create/edit/read/list
- **Clinician**: retrieve undiagnosed cases + submit diagnoses
- **Admin**: invite code management, user management, export bundle generation

## Export Logic (Human vs AI Reports)

Admin-triggered export flow (`/dbmanager/bundle/export`) performs:

1. Read all cases from Firestore.
2. Decrypt encrypted case payloads using passphrase-derived AES keys.
3. Materialize trial artifacts:
   - lesion images,
   - biopsy reports,
   - consent forms (if `include_all=true`),
   - mastersheet Excel rows with AI + clinician + biopsy/COE fields.
4. Produce a clinician UID mapping sheet (de-identification helper).
5. Zip all artifacts.
6. Encrypt the ZIP with AES ZIP encryption and generated password.
7. Upload encrypted bundle to Cloud Storage and return signed URL + password.

This output is designed for downstream Human-vs-AI analytics and auditability.

## Tech Stack

| Area            | Technology                           | Role                                                 |
| --------------- | ------------------------------------ | ---------------------------------------------------- |
| API             | FastAPI, Uvicorn                     | REST endpoints and OpenAPI docs.                     |
| Auth            | Firebase Admin SDK                   | Token verification and role claim checks.            |
| Database        | Firestore                            | Case, user, and invite code persistence.             |
| File Storage    | Firebase/Cloud Storage               | Encrypted blobs, reports, export bundles.            |
| Data Processing | pandas, openpyxl                     | Mastersheet generation for export.                   |
| Security        | AES encryption utilities, `pyzipper` | Data-at-rest handling and encrypted bundle delivery. |
| HTTP Clients    | `httpx`, `requests`                  | Internal/external service communication.             |

## Local Setup

```bash
cd backend
python -m venv venv-backend
source venv-backend/Scripts/activate   # Git Bash on Windows
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

Docs URL: `http://127.0.0.1:8000/docs`

## Environment Variables

Create `backend/.env` from `backend/.env.example`.

| Variable                | Required          | Purpose                                      |
| ----------------------- | ----------------- | -------------------------------------------- |
| `PASSWORD`              | Yes               | Passphrase used to unwrap per-case AES keys. |
| `AI_URL`                | Yes               | Base URL for AI inference service.           |
| `FIREBASE_BUCKET_NAME`  | Yes               | Storage bucket used for files/bundles.       |
| `SENDGRID_API_KEY`      | Optional (future) | Planned email delivery support for bundles.  |
| `SENDGRID_SENDER_EMAIL` | Optional (future) | Sender identity for bundle notifications.    |

## Cloud Setup (Firebase + GCP)

### Firebase Integration

This backend depends on three Firebase services:

| Firebase Service | Usage in Backend                                                  |
| ---------------- | ----------------------------------------------------------------- |
| Authentication   | Verifies client ID tokens and role claims for RBAC.               |
| Firestore        | Stores user profiles, case data, diagnoses, and invite code data. |
| Storage          | Stores encrypted blobs/reports and generated export bundles.      |

Migration checklist when moving to a new Firebase project:

1. Enable **Authentication**, **Firestore**, and **Storage** in the target project.
2. Copy Firestore collection structure used by this platform (users, cases, invite-related collections).
3. Recreate Firestore indexes required by paginated/filtered queries.
4. Confirm Storage bucket name and permissions align with runtime configuration.
5. Run smoke tests for register/login, case CRUD, diagnosis submission, and bundle export.

### GCP Secret Manager Configuration

Store backend runtime variables as secrets and attach them to Cloud Run revisions.

Required secrets:

| Secret Name (suggested) | Maps to variable        | Required |
| ----------------------- | ----------------------- | -------- |
| `PASSWORD`              | `PASSWORD`              | Yes      |
| `AI_URL`                | `AI_URL`                | Yes      |
| `FIREBASE_BUCKET_NAME`  | `FIREBASE_BUCKET_NAME`  | Yes      |
| `SENDGRID_API_KEY`      | `SENDGRID_API_KEY`      | Optional |
| `SENDGRID_SENDER_EMAIL` | `SENDGRID_SENDER_EMAIL` | Optional |

Create a secret:

```bash
echo -n "<VALUE>" | gcloud secrets create <SECRET_NAME> --data-file=-
```

Attach secret to Cloud Run revision:

1. Cloud Run -> select backend service -> **Edit & deploy new revision**
2. Container -> **Variables & Secrets**
3. Add secret reference (latest or pinned version)
4. Deploy revision

### Service Account and IAM Roles

The Cloud Run runtime service account needs at least:

| IAM Role                         | Why It Is Needed                                           |
| -------------------------------- | ---------------------------------------------------------- |
| `Secret Manager Secret Accessor` | Read runtime secrets during startup/runtime.               |
| `Cloud Datastore User`           | Access Firestore data APIs.                                |
| `Storage Object Admin`           | Read/write objects for encrypted blobs and export bundles. |

Apply roles to the service account assigned to the backend Cloud Run service.

### Firebase Admin Key Mounting

The backend expects Firebase Admin credentials to be available as a mounted secret file.

Steps:

1. In Firebase Console -> **Project settings -> Service accounts**, generate private key JSON.
2. Save as `firebase-admin-key.json`.
3. Upload this JSON into Secret Manager (recommended) or secure secret storage.
4. Mount the secret file into Cloud Run as a volume so it resolves at:
   - `/backend/secrets/firebase-admin-key.json`

For local Docker testing, mount from host:

```bash
docker run --rm -it -p 8000:8080 \
  -v "$(pwd)/backend/secrets:/backend/secrets" \
  --env-file backend/.env \
  --name backend-service \
  memosa-ct-backend
```

Ensure the mounted file path matches what backend Firebase initialization expects.

## Docker Deployment

From repository root:

```bash
docker build -t memosa-ct-backend backend/
docker run --rm -it -p 8000:8080 \
  -v "$(pwd)/backend/secrets:/backend/secrets" \
  --env-file backend/.env \
  --name backend-service \
  memosa-ct-backend
```

## Directory Overview

```text
backend/
├── app/main.py                  # FastAPI entrypoint
├── app/api/routes/              # Route groups: auth, dbmanager, invite, user
├── app/api/*.py                 # Business logic services
├── app/core/                    # Firebase init, config, crypto helpers
├── app/models/                  # Pydantic/domain models
├── requirements.txt
├── Dockerfile
└── README.md
```
