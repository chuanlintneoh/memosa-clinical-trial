from datetime import datetime, timedelta
from google.cloud import firestore
from io import BytesIO
from nanoid import generate
from pathlib import Path
from PIL import Image
from typing import Any, Dict, List, Optional
import base64
import json
import pandas as pd
import pyzipper
import requests
import secrets
import string
import tempfile
import zipfile

from app.api.storage import Storage
from app.core.config import PASSWORD
from app.core.crypto import CryptoUtils
from app.core.firebase import bucket, db

class DbManager:
    def __init__(self, aiqueue):
        self.aiqueue = aiqueue
        self.pending_cases: Dict[str, Dict[str, Any]] = {}  # Data of cases that have already been sent to AIQueue

    def uniquify_id(self, case_id: str, max_trials: int = 5, size: int = 8) -> str:
        doc_ref = db.collection("cases").document(case_id)
        trial = 0

        while (doc_ref.get().exists or case_id in self.pending_cases) and trial < max_trials:
            print(f"[DbManager] Collision detected for {case_id}, generating a new one (trial {trial+1})")
            case_id = generate(size=size)
            print(f"[DbManager] Generated new case ID: {case_id}")
            doc_ref = db.collection("cases").document(case_id)
            trial += 1

        if trial == max_trials and (doc_ref.get().exists or case_id in self.pending_cases):
            print(f"[DbManager] Failed to generate unique case ID after {trial} trials")
            raise ValueError(f"Failed to generate unique case ID after {trial} trials")

        return case_id

    def enqueue_ai_job(self, case_id: str, case_data: Dict[str, Any]):
        # 1. download encrypted blob from Firebase Storage
        # 2. decrypt blob using aes key
        # 3. extract 9 images from decrypted blob in order
        # 4. send case_id: [9 images] to AIQueue for AI diagnosis
        encrypted_aes = case_data.get("encrypted_aes", {})
        ciphertext = encrypted_aes.get("ciphertext")
        iv = encrypted_aes.get("iv")
        salt = encrypted_aes.get("salt")
        aes_key = CryptoUtils.decrypt_aes_key_with_passphrase(
            encrypted_aes_key_b64=ciphertext,
            passphrase=PASSWORD,
            salt_b64=salt,
            iv_b64=iv
        )

        encrypted_blob = case_data.get("encrypted_blob", {})
        url = encrypted_blob.get("url", "NULL")
        iv = encrypted_blob.get("iv", "NULL")
        if url == "NULL" or iv == "NULL":
            print(f"[DbManager] Invalid encrypted blob for case {case_id}. Cannot enqueue AI job.")
            return
        print(f"[DbManager] Downloading blob from URL: {url}")
        try:
            response = requests.get(url)
            if response.status_code != 200:
                raise RuntimeError(f"Failed to download blob: {response.status_code}")
            encrypted_blob = base64.b64encode(response.content).decode('utf-8')
        except Exception as e:
            print(f"[DbManager] Error downloading blob for case {case_id}: {e}")
            return
        
        print(f"[DbManager] Decrypting blob...")
        decrypted_data = CryptoUtils.decrypt_string(
            encrypted_blob,
            iv,
            aes_key
        )
        image_b64_list = json.loads(decrypted_data).get("images", [])
        if len(image_b64_list) != 9:
            print(f"[DbManager] Invalid number of images for case {case_id}. Cannot enqueue AI job.")
            return

        images = []
        for b64_str in image_b64_list:
            img_bytes = base64.b64decode(b64_str)
            img = Image.open(BytesIO(img_bytes)).convert("RGB")
            images.append(img)

        self.aiqueue.receive_new_case(case_id, images)
        print(f"[DbManager] Enqueued AI job for case: {case_id}")

    def receive_AI_results(self, results: Dict[str, Any]):
        new_cases = {}
        for case_id, predictions in results.items():
            if case_id not in self.pending_cases:
                print(f"[DbManager] Warning: Received AI result for unknown case_id: {case_id}")
                continue
            case_data = self.pending_cases[case_id]

            diagnoses = case_data.get("diagnoses", [])
            if len(diagnoses) != len(predictions):
                print(f"[DbManager] Mismatch between diagnosis count and predictions for case {case_id}")
                continue

            for i in range(len(diagnoses)):
                diagnoses[i]["ai_lesion_type"] = predictions[i]

            case_data["diagnoses"] = diagnoses
            new_cases[case_id] = case_data
            del self.pending_cases[case_id]
        
        self._batch_write_new_cases(new_cases)

    def _batch_write_new_cases(self, new_cases: Dict[str, Dict[str, Any]]):
        print(f"[DbManager] Batch writing {len(new_cases)} cases to Firestore...")
        try:
            batch = db.batch()
            for case_id, case_data in new_cases.items():
                case_data["submitted_at"] = firestore.SERVER_TIMESTAMP
                doc_ref = db.collection("cases").document(case_id)
                batch.set(doc_ref, case_data)
            batch.commit()
            print(f"[DbManager] Batch wrote {len(new_cases)} cases to Firestore.")
        except Exception as e:
            print(f"[DbManager] Error batch writing cases: {str(e)}")

    def get_case_by_id(self, case_id: str) -> Optional[Dict]:
        doc = db.collection("cases").document(case_id).get()
        if doc.exists:
            print(f"[DbManager] Retrieved case {case_id} from Firestore.")
            return doc.to_dict()
        print(f"[DbManager] Case {case_id} not found in Firestore.")
        return None

    def get_cases_list(
        self,
        current_user_uid: str,
        date_range: Optional[str] = None,
        custom_start: Optional[str] = None,
        custom_end: Optional[str] = None,
        created_by_me: bool = False,
        limit: int = 5,
        start_after_id: Optional[str] = None
    ):
        """
        Get a paginated list of cases with filters.

        Args:
            current_user_uid: UID of the requesting user
            date_range: "today", "this_week", "this_month", or "custom"
            custom_start: ISO date string for custom range start (YYYY-MM-DD)
            custom_end: ISO date string for custom range end (YYYY-MM-DD)
            created_by_me: If True, filter to only cases created by current user
            limit: Number of cases to return
            start_after_id: Case ID to start after for pagination

        Returns:
            Dict with keys: cases (list), next_cursor (str or None), has_more (bool)
        """
        print(f"[DbManager] Getting cases list for user {current_user_uid}...")
        print(f"[DbManager] Filters: date_range={date_range}, created_by_me={created_by_me}, limit={limit}, start_after_id={start_after_id}")

        # Build base query
        query = db.collection("cases")

        # Filter by created_by if requested
        if created_by_me:
            query = query.where("created_by", "==", current_user_uid)
            print(f"[DbManager] Filtering cases created by {current_user_uid}")

        # Filter by date range if provided
        if date_range:
            now = datetime.now()
            start_date = None
            end_date = None

            if date_range == "today":
                start_date = datetime(now.year, now.month, now.day, 0, 0, 0)
                end_date = datetime(now.year, now.month, now.day, 23, 59, 59)
                print(f"[DbManager] Filtering for today: {start_date} to {end_date}")

            elif date_range == "this_week":
                # Get start of week (Monday)
                days_since_monday = now.weekday()
                start_date = datetime(now.year, now.month, now.day, 0, 0, 0) - timedelta(days=days_since_monday)
                end_date = start_date + timedelta(days=7) - timedelta(seconds=1)
                print(f"[DbManager] Filtering for this week: {start_date} to {end_date}")

            elif date_range == "this_month":
                start_date = datetime(now.year, now.month, 1, 0, 0, 0)
                # Get last day of month
                if now.month == 12:
                    end_date = datetime(now.year + 1, 1, 1, 0, 0, 0) - timedelta(seconds=1)
                else:
                    end_date = datetime(now.year, now.month + 1, 1, 0, 0, 0) - timedelta(seconds=1)
                print(f"[DbManager] Filtering for this month: {start_date} to {end_date}")

            elif date_range == "custom":
                if custom_start and custom_end:
                    try:
                        start_date = datetime.fromisoformat(custom_start.replace('Z', '+00:00'))
                        end_date = datetime.fromisoformat(custom_end.replace('Z', '+00:00'))
                        # Set time to end of day for end_date
                        end_date = datetime(end_date.year, end_date.month, end_date.day, 23, 59, 59)
                        print(f"[DbManager] Filtering for custom range: {start_date} to {end_date}")
                    except Exception as e:
                        print(f"[DbManager] Error parsing custom dates: {e}")
                        start_date = None
                        end_date = None

            # Apply date filters to query
            if start_date:
                query = query.where("submitted_at", ">=", start_date)
            if end_date:
                query = query.where("submitted_at", "<=", end_date)

        # Order by submitted_at descending (most recent first)
        query = query.order_by("submitted_at", direction=firestore.Query.DESCENDING)

        # Handle pagination cursor
        if start_after_id:
            # Get the document to start after
            start_after_doc = db.collection("cases").document(start_after_id).get()
            if start_after_doc.exists:
                query = query.start_after(start_after_doc)
                print(f"[DbManager] Starting after case {start_after_id}")

        # Apply limit (fetch limit + 1 to check if there are more)
        query = query.limit(limit + 1)

        # Execute query
        docs = query.stream()

        # Process results
        cases = []
        for doc in docs:
            case_data = doc.to_dict()
            case_data["case_id"] = doc.id

            # Convert Firestore timestamps to ISO strings for JSON serialization
            if "submitted_at" in case_data and case_data["submitted_at"]:
                case_data["submitted_at"] = case_data["submitted_at"].isoformat()
            if "created_at" in case_data and case_data["created_at"]:
                # Handle both datetime and string formats
                if hasattr(case_data["created_at"], "isoformat"):
                    case_data["created_at"] = case_data["created_at"].isoformat()

            cases.append(case_data)

        # Determine if there are more results
        has_more = len(cases) > limit
        if has_more:
            cases = cases[:limit]  # Remove the extra document

        # Get next cursor (ID of last case in current page)
        next_cursor = cases[-1]["case_id"] if cases and has_more else None

        print(f"[DbManager] Retrieved {len(cases)} cases. Has more: {has_more}, Next cursor: {next_cursor}")

        return {
            "cases": cases,
            "next_cursor": next_cursor,
            "has_more": has_more
        }

    def edit_case_by_id(self, case_id: str, updates: Dict[str, Any]):
        db.collection("cases").document(case_id).update(updates)
        print(f"[DbManager] Updated case {case_id}.")

    def get_undiagnosed_cases(
        self,
        clinician_id: str,
        limit: int = 100,
        days_back: int = 90
    ):
        """
        Retrieve undiagnosed cases for a clinician with pagination and date filtering.

        Args:
            clinician_id: The clinician's UID
            limit: Maximum number of cases to return (default: 100)
            days_back: Only check cases from the last N days (default: 90)

        Returns:
            List of undiagnosed cases
        """
        print(f"[DbManager] Retrieving undiagnosed cases for clinician {clinician_id} (limit={limit}, days_back={days_back})...")

        # Query recent cases first to reduce dataset
        cutoff_date = datetime.now() - timedelta(days=days_back)

        query = db.collection("cases")\
            .where("submitted_at", ">=", cutoff_date)\
            .order_by("submitted_at", direction=firestore.Query.DESCENDING)\
            .limit(limit * 2)  # Query more than limit to account for filtering

        cases = query.stream()
        undiagnosed_cases = []
        checked_count = 0

        for doc in cases:
            checked_count += 1
            case_data = doc.to_dict()
            diagnoses_list = case_data.get("diagnoses", [])

            # Check if this clinician hasn't diagnosed at least one lesion
            if any(clinician_id not in diag for diag in diagnoses_list):
                undiagnosed_cases.append({
                    "case_id": doc.id,
                    **case_data
                })

                # Stop if we've found enough undiagnosed cases
                if len(undiagnosed_cases) >= limit:
                    break

        print(f"[DbManager] Found {len(undiagnosed_cases)} undiagnosed cases for clinician {clinician_id} (checked {checked_count} recent cases).")
        return undiagnosed_cases

    def submit_case_diagnosis(self, case_id: str, diagnoses: List[Dict[str, Any]]):
        print(f"[DbManager] Submitting case diagnosis for case {case_id}...")
        doc_ref = db.collection("cases").document(case_id)
        doc_snapshot = doc_ref.get()

        if not doc_snapshot.exists:
            print(f"[DbManager] Case {case_id} not found")
            return False

        data = doc_snapshot.to_dict()
        existing_diagnoses = data.get("diagnoses", [])

        if len(existing_diagnoses) < len(diagnoses):
            existing_diagnoses.extend([{} for _ in range(len(diagnoses) - len(existing_diagnoses))])

        for idx, diag in enumerate(diagnoses):
            if not isinstance(diag, dict):
                continue

            for clinician_id, diag_data in diag.items():
                existing_diagnoses[idx][clinician_id] = {
                    "clinical_diagnosis": diag_data.get("clinical_diagnosis", "NULL"),
                    "lesion_type": diag_data.get("lesion_type", "NULL"),
                    "low_quality": diag_data.get("low_quality", False),
                    "low_quality_reason": diag_data.get("low_quality_reason", "NULL"),
                    # "timestamp": firestore.SERVER_TIMESTAMP, # Commented because of exception
                }

        doc_ref.update({"diagnoses": existing_diagnoses})
        print(f"[DbManager] Updated {case_id} with {len(diagnoses)} diagnoses")

    def get_all_cases(self):
        print(f"[DbManager] Retrieving all cases...")
        docs = db.collection("cases").stream()
        all_cases = []
        for doc in docs:
            case = doc.to_dict()
            case["case_id"] = doc.id
            all_cases.append(case)
        print(f"[DbManager] Retrieved {len(all_cases)} cases from Firestore.")
        return all_cases
    
    async def export_bundle(
        self,
        include_all: bool = False,
        signed_url: bool = False,
        expiry_seconds: int = 24 * 3600,
        # email: Optional[str] = None
    ):
        with tempfile.TemporaryDirectory() as tmpdir:
            base_dir = Path(tmpdir)

            timestamp, buf, zip_path = await self._process_bundle(
                base_dir=base_dir,
                include_all=include_all
            )

            if not signed_url:
                return buf, timestamp
            else:
                encrypted_path = zip_path.with_suffix('.encrypted.zip')
                password = self._encrypt_bundle(zip_path, encrypted_path)
                url = self._upload_bundle(encrypted_path, expiry_seconds)
                # if email:
                    # self._email_bundle(email, timestamp, zip_path)
                return url, password, timestamp
    
    async def _process_bundle(self, base_dir: Path, include_all: bool = False):
        print(f"[DbManager] Processing bundle (include_all={include_all})...")

        # Get all case IDs first (lightweight query)
        print(f"[DbManager] Fetching case IDs...")
        docs = db.collection("cases").stream()
        case_ids = [doc.id for doc in docs]
        total_cases = len(case_ids)
        print(f"[DbManager] Found {total_cases} cases to process.")

        images_dir = base_dir / "images"
        reports_dir = base_dir / "biopsy_reports"
        consent_dir = base_dir / "consent_forms"
        images_dir.mkdir(parents=True, exist_ok=True)
        reports_dir.mkdir(parents=True, exist_ok=True)
        if include_all:
            consent_dir.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%dT%H%M%S")
        mastersheet_path = base_dir / f"mastersheet_{timestamp}.xlsx"

        def _process_case(case: dict) -> dict:
            biopsy_lesion_type = case.get("biopsy_lesion_type")
            coe_lesion_type = case.get("coe_lesion_type")
            biopsy_clinical_diagnosis = case.get("biopsy_clinical_diagnosis")
            coe_clinical_diagnosis = case.get("coe_clinical_diagnosis")

            biopsy_agree_with_coe = "NULL"

            if biopsy_lesion_type and biopsy_lesion_type != "NULL" and coe_lesion_type and coe_lesion_type != "NULL":
                biopsy_agree_with_coe = "YES" if biopsy_lesion_type == coe_lesion_type else "NO"
                if biopsy_clinical_diagnosis and biopsy_clinical_diagnosis != "NULL" and coe_clinical_diagnosis and coe_clinical_diagnosis != "NULL":
                    biopsy_agree_with_coe = (
                        "YES"
                        if (biopsy_lesion_type == coe_lesion_type and biopsy_clinical_diagnosis == coe_clinical_diagnosis)
                        else "NO"
                    )
            case["biopsy_agree_with_coe"] = biopsy_agree_with_coe
            return case

        rows = []
        clinician_mapping = {}
        clinician_counter = 0

        # Process cases in batches to prevent memory overflow
        BATCH_SIZE = 10  # Process 10 cases at a time
        processed_count = 0

        # First pass: Build clinician mapping (lightweight - only metadata)
        print(f"[DbManager] Building clinician mapping...")
        for i in range(0, len(case_ids), BATCH_SIZE):
            batch_ids = case_ids[i:i + BATCH_SIZE]
            for case_id in batch_ids:
                doc = db.collection("cases").document(case_id).get()
                if not doc.exists:
                    continue
                case_data = doc.to_dict()
                for diagnose in case_data.get("diagnoses", []):
                    for key, val in diagnose.items():
                        if isinstance(val, dict) and all(k in val for k in ["lesion_type", "clinical_diagnosis", "low_quality", "low_quality_reason"]):
                            uid = key
                            if uid not in clinician_mapping:
                                clinician_counter += 1
                                clinician_mapping[uid] = f"clinician{clinician_counter:02d}"
        print(f"[DbManager] Mapped {len(clinician_mapping)} clinicians.")

        # Second pass: Process cases in batches with full data
        for batch_num, i in enumerate(range(0, len(case_ids), BATCH_SIZE), start=1):
            batch_ids = case_ids[i:i + BATCH_SIZE]
            print(f"[DbManager] Processing batch {batch_num}/{(len(case_ids) + BATCH_SIZE - 1) // BATCH_SIZE} ({len(batch_ids)} cases)...")

            for case_id in batch_ids:
                doc = db.collection("cases").document(case_id).get()
                if not doc.exists:
                    continue

                case = doc.to_dict()
                case["case_id"] = case_id
                processed_count += 1

                name = idtype = idnum = dob = age = gender = ethnicity = phonenum = address = attending_hospital = lesion_clinical_presentation = chief_complaint = presenting_complaint_history = medication_history = medical_history = additional_comments = "NULL"

                aes_key = None
                aes = case.get("encrypted_aes", {"salt": "NULL", "ciphertext": "NULL", "iv": "NULL"})
                if (aes.get("salt") != "NULL" and aes.get("ciphertext") != "NULL" and aes.get("iv") != "NULL"):
                    aes_key = CryptoUtils.decrypt_aes_key_with_passphrase(
                        encrypted_aes_key_b64=aes["ciphertext"],
                        passphrase=PASSWORD,
                        salt_b64=aes["salt"],
                        iv_b64=aes["iv"]
                    )

                encrypted_blob = case.get("encrypted_blob", {"url": "NULL", "iv": "NULL"})
                if (encrypted_blob.get("url") != "NULL" and encrypted_blob.get("iv") != "NULL" and aes_key):
                    encrypted_blob_data = await Storage.download(encrypted_blob.get("url"))
                    blob_data = CryptoUtils.decrypt_string(
                        encrypted_data_b64=encrypted_blob_data,
                        iv_b64=encrypted_blob["iv"],
                        aes_key=aes_key
                    )
                    blob_data = json.loads(blob_data)
                    age = blob_data.get("age", "NULL")
                    gender = blob_data.get("gender", "NULL")
                    ethnicity = blob_data.get("ethnicity", "NULL")
                    lesion_clinical_presentation = blob_data.get("lesion_clinical_presentation", "NULL")
                    chief_complaint = blob_data.get("chief_complaint", "NULL")
                    presenting_complaint_history = blob_data.get("presenting_complaint_history", "NULL")
                    medication_history = blob_data.get("medication_history", "NULL")
                    medical_history = blob_data.get("medical_history", "NULL")

                    for idx, img_b64 in enumerate(blob_data.get("images", [])):
                        img_bytes = base64.b64decode(img_b64)
                        img_path = images_dir / f"{case['case_id']}_{idx}.jpg"
                        with open(img_path, "wb") as f:
                            f.write(img_bytes)

                    if include_all:
                        name = blob_data.get("name", "NULL")
                        idtype = blob_data.get("idtype", "NULL")
                        idnum = blob_data.get("idnum", "NULL")
                        dob = blob_data.get("dob", "NULL")
                        phonenum = blob_data.get("phonenum", "NULL")
                        address = blob_data.get("address", "NULL")
                        attending_hospital = blob_data.get("attending_hospital", "NULL")
                        consent_form = blob_data.get("consent_form", {
                            "fileType": "NULL",
                            "fileBytes": "NULL"
                        })
                        if consent_form["fileBytes"] != "NULL":
                            file_bytes = consent_form["fileBytes"]
                            if isinstance(file_bytes, str):
                                decoded_bytes = base64.b64decode(file_bytes)
                            elif isinstance(file_bytes, list):
                                decoded_bytes = bytes(file_bytes)
                            else:
                                print(f"[DbManager] Skipped consent form of case {case['case_id']} with unknown fileBytes type: {type(file_bytes)}")
                                decoded_bytes = None
                            if decoded_bytes:
                                with open(consent_dir / f"{case['case_id']}.{str(consent_form['fileType']).lower()}", "wb") as f:
                                    f.write(decoded_bytes)

                additional_comments_obj = case.get("additional_comments", {"ciphertext": "NULL", "iv": "NULL"})
                if (additional_comments_obj.get("ciphertext") != "NULL" and additional_comments_obj.get("iv") != "NULL" and aes_key):
                    additional_comments = CryptoUtils.decrypt_string(
                        encrypted_data_b64=additional_comments_obj["ciphertext"],
                        iv_b64=additional_comments_obj["iv"],
                        aes_key=aes_key
                    )

                base = {
                    "case_id": case.get("case_id"),
                    "created_at": case.get("created_at"),
                    "created_by": case.get("created_by"),
                    "submitted_at": case.get("submitted_at"),
                    "name": name,
                    "idtype": idtype,
                    "idnum": idnum,
                    "dob": dob,
                    "age": age,
                    "gender": gender,
                    "ethnicity": ethnicity,
                    "phonenum": phonenum,
                    "address": address,
                    "attending_hospital": attending_hospital,
                    "alcohol": case.get("alcohol"),
                    "alcohol_duration": case.get("alcohol_duration"),
                    "betel_quid": case.get("betel_quid"),
                    "betel_quid_duration": case.get("betel_quid_duration"),
                    "smoking": case.get("smoking"),
                    "smoking_duration": case.get("smoking_duration"),
                    "lesion_clinical_presentation": lesion_clinical_presentation,
                    "chief_complaint": chief_complaint,
                    "presenting_complaint_history": presenting_complaint_history,
                    "medication_history": medication_history,
                    "medical_history": medical_history,
                    "oral_hygiene_products_used": case.get("oral_hygiene_products_used"),
                    "oral_hygiene_product_type_used": case.get("oral_hygiene_product_type_used"),
                    "sls_containing_toothpaste": case.get("sls_containing_toothpaste"),
                    "sls_containing_toothpaste_used": case.get("sls_containing_toothpaste_used"),
                    "additional_comments": additional_comments
                }
                if not include_all:
                    for col in ["name", "idtype", "idnum", "dob", "phonenum", "address", "attending_hospital"]:
                        base.pop(col, None)

                diagnoses = case.get("diagnoses", [])
                if not diagnoses:
                    row = base.copy()
                    for i in range(9):
                        row.update({
                            "image_index": i,
                            "ai_lesion_type": "NULL",
                            "biopsy_clinical_diagnosis": "NULL",
                            "biopsy_lesion_type": "NULL",
                            "coe_clinical_diagnosis": "NULL",
                            "coe_lesion_type": "NULL",
                            "biopsy_agree_with_coe": "NULL",
                        })
                        for clinician in clinician_mapping.values():
                            row[f"{clinician}_lesion_type"] = "NULL"
                            row[f"{clinician}_clinical_diagnosis"] = "NULL"
                            row[f"{clinician}_low_quality"] = "NULL"
                            row[f"{clinician}_low_quality_reason"] = "NULL"
                        rows.append(row)
                else:
                    for i, diagnose in enumerate(diagnoses):
                        row = base.copy()
                        processed = _process_case(diagnose)
                        row.update({
                            "image_index": i,
                            "ai_lesion_type": processed.get("ai_lesion_type", "NULL"),
                            "biopsy_clinical_diagnosis": processed.get("biopsy_clinical_diagnosis", "NULL"),
                            "biopsy_lesion_type": processed.get("biopsy_lesion_type", "NULL"),
                            "coe_clinical_diagnosis": processed.get("coe_clinical_diagnosis", "NULL"),
                            "coe_lesion_type": processed.get("coe_lesion_type", "NULL"),
                            "biopsy_agree_with_coe": processed.get("biopsy_agree_with_coe", "NULL")
                        })
                        for uid, clinician in clinician_mapping.items():
                            if uid in diagnose:
                                cdata = diagnose[uid]
                                row[f"{clinician}_lesion_type"] = cdata.get("lesion_type", "NULL")
                                row[f"{clinician}_clinical_diagnosis"] = cdata.get("clinical_diagnosis", "NULL")
                                row[f"{clinician}_low_quality"] = cdata.get("low_quality", "NULL")
                                row[f"{clinician}_low_quality_reason"] = cdata.get("low_quality_reason", "NULL")
                            else:
                                row[f"{clinician}_lesion_type"] = "NULL"
                                row[f"{clinician}_clinical_diagnosis"] = "NULL"
                                row[f"{clinician}_low_quality"] = "NULL"
                                row[f"{clinician}_low_quality_reason"] = "NULL"
                        rows.append(row)

                        biopsy_report_obj = diagnose.get("biopsy_report", {
                            "url": "NULL",
                            "iv": "NULL",
                            "fileType": "NULL"
                        })
                        if (biopsy_report_obj.get("url") != "NULL" and biopsy_report_obj.get("iv") != "NULL" and aes_key):
                            biopsy_report_data = await Storage.download(biopsy_report_obj.get("url"))
                            biopsy_report = CryptoUtils.decrypt_string(
                                encrypted_data_b64=biopsy_report_data,
                                iv_b64=biopsy_report_obj["iv"],
                                aes_key=aes_key
                            )
                            if isinstance(biopsy_report, str):
                                decoded_bytes = base64.b64decode(biopsy_report)
                            elif isinstance(biopsy_report, list):
                                decoded_bytes = bytes(biopsy_report)
                            else:
                                print(f"[DbManager] Skipped biopsy report of case {case['case_id']} image {i} with unknown fileBytes type: {type(biopsy_report)}")
                                decoded_bytes = None
                            if decoded_bytes:
                                with open(reports_dir / f"{case['case_id']}_{i}.{str(biopsy_report_obj['fileType']).lower()}", "wb") as f:
                                    f.write(decoded_bytes)

            # Clear processed batch from memory
            import gc
            gc.collect()
            print(f"[DbManager] Batch {batch_num} complete. Total processed: {processed_count}/{total_cases}")

        print(f"[DbManager] All {total_cases} cases processed.")

        mastersheet_df = pd.DataFrame(rows)
        print(f"[DbManager] Generated Sheet 1: Mastersheet with {len(mastersheet_df)} rows and {len(mastersheet_df.columns)} columns.")
        mapping_rows = [{"clinician": cname, "clinician_uid": uid} for uid, cname in clinician_mapping.items()]
        mapping_df = pd.DataFrame(mapping_rows)
        print(f"[DbManager] Generated Sheet 2: Clinicians with {len(mapping_df)} rows and {len(mapping_df.columns)} columns.")

        for col in mastersheet_df.select_dtypes(include=["datetimetz"]).columns:
            mastersheet_df[col] = mastersheet_df[col].dt.tz_localize(None)

        buf = BytesIO()
        with pd.ExcelWriter(buf, engine="openpyxl") as writer:
            mastersheet_df.to_excel(writer, index=True, sheet_name="mastersheet")
            mapping_df.to_excel(writer, index=True, sheet_name="clinicians")
        buf.seek(0)
        with open(mastersheet_path, "wb") as f:
            f.write(buf.getvalue())
        
        zip_path = base_dir / f"bundle_{timestamp}.zip"
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zipf:
            for file_path in base_dir.rglob("*"):
                if file_path == zip_path:
                    continue
                zipf.write(file_path, file_path.relative_to(base_dir))
        print(f"[DbManager] Bundle processed at {base_dir}, Excel at {mastersheet_path}")

        return timestamp, buf, zip_path
    
    def _encrypt_bundle(self, input_zip: Path, output_zip: Path, password_length: int = 12):
        alphabet = string.ascii_letters + string.digits + string.punctuation
        password = ''.join(secrets.choice(alphabet) for _ in range(password_length))
        print(f"[DbManager] Generated {password_length} character password for bundle encryption.")

        with pyzipper.AESZipFile(
            output_zip,
            'w',
            compression=pyzipper.ZIP_DEFLATED,
            encryption=pyzipper.WZ_AES
        ) as zf:
            zf.setpassword(password.encode())
            zf.setencryption(pyzipper.WZ_AES, nbits=256)

            zf.write(input_zip, arcname=input_zip.name)
        print(f"[DbManager] Encrypted bundle saved to {output_zip}.")
        
        return password

    def _upload_bundle(self, zip_path: Path, expiry_seconds: int = 24 * 3600) -> str:
        file_name = zip_path.name
        destination = f"bundles/{file_name}"
        blob = bucket.blob(destination)

        blob.upload_from_filename(str(zip_path))

        blob.content_disposition = f'attachment; filename="{file_name}"'
        blob.patch()

        url = blob.generate_signed_url(
            version="v4",
            expiration=timedelta(seconds=expiry_seconds),
            method="GET"
        )
        print(f"[DbManager] Uploaded encrypted bundle to {destination} with signed URL valid for {expiry_seconds} seconds.")
        return url