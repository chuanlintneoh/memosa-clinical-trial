```
# Create virtual env
python -m venv venv-backend

# Activate virtual env
# - Before running FastAPI server (uvicorn)
# - Before installing new packages
# - Before running scripts or testing features in the backend
# PowerShell
.\venv-backend\Scripts\Activate.ps1
# Git Bash
source venv-backend/Scripts/activate

# Deactivate virtual env
# - when done working on the backend
deactivate

# Install dependencies
pip install -r requirements.txt

# Start server
uvicorn app.main:app --reload --port 8000

# Stop server
Ctrl + C

# Test Python code
python -m app.path.code

# Create a new secret in Google Cloud Secret Manager
1. echo -n "<MY-SECRET>" | gcloud secrets create SECRET-NAME --data-file=-
2. (One time setup) IAM & Admin > IAM > <PROJECT_NUMBER>-compute@developer.gserviceaccount.com > Edit principal > Add another role > Secret Manager Secret Accessor > Save
3. Attach secret to service at Cloud Run > Select service > Edit & deploy new revision > Edit container > Variables & Secrets > Reference a secret > Fill in <SECRET-NAME> > Select created secret > Select latest version > Done > Deploy

# To resume the Google Cloud Run hosting
# 1. Enable trigger at Cloud Build > Triggers > Select trigger > Enable
# 2. Allow url public access at Cloud Run > Select service > Security > Authentication > Allow public access > Save

# Docker commands

# List all existing docker builds
docker images

# Clean up dangling docker images
docker image prune

# Delete docker image
docker rmi <image-name>

# Local offline testing (Build & run docker image)
1. cd .. (cd to project root)
2. docker build -t memosa-ct-backend backend/
3. docker run --rm -it -p 8000:8080 -v "/$(pwd)/backend/secrets:/backend/secrets" --env-file backend/.env --name backend-service memosa-ct-backend
4. Browse http://127.0.0.1:8000/docs
5. Ctrl + C (quit process)

```
