from io import BytesIO
from threading import Lock, Timer
from typing import Any, Dict
import base64
import requests
import time
import logging

from app.core.config import AI_URL

logger = logging.getLogger(__name__)

class AIQueue:
    def __init__(
        self,
        dbmanager,
        flush_interval_seconds: int = 3600,
        flush_maximum_cases: int = 1,
        inference_timeout_seconds: int = 60,
        max_retries: int = 3,
        retry_backoff_base: float = 2.0
    ):
        self.dbmanager = dbmanager
        self.IMAGES_PER_CASE = 9
        self._new_cases: Dict[str, Dict[str, Any]] = {} # Cases waiting to be flushed
        self._flush_interval_seconds = flush_interval_seconds
        self._flush_maximum_cases = flush_maximum_cases
        self._inference_timeout_seconds = inference_timeout_seconds
        self._max_retries = max_retries
        self._retry_backoff_base = retry_backoff_base
        self._lock = Lock()
        self._start_periodic_flush()

    def _start_periodic_flush(self):
        self._flush()
        t = Timer(self._flush_interval_seconds, self._start_periodic_flush)
        t.daemon = True
        t.start()
        print(f"[AIQueue] Periodic flush started every {self._flush_interval_seconds} seconds.")

    def receive_new_case(self, case_id: str, images):
        with self._lock:
            self._new_cases[case_id] = {"images": images}
        print(f"[AIQueue] Received new case: {case_id}. Total cases in queue: {len(self._new_cases)}")
        self._check_cases_amount()
    
    def _check_cases_amount(self):
        with self._lock:
            if len(self._new_cases) >= self._flush_maximum_cases:
                print(f"[AIQueue] Cache reached maximum cases ({self._flush_maximum_cases}).")
                Timer(0, self._flush).start()

    def _flush(self):
        with self._lock:
            if len(self._new_cases) == 0:
                print("[AIQueue] No new cases to flush.")
                return

            flush_data = dict(self._new_cases)
            self._new_cases.clear()

        print(f"[AIQueue] Flushing {len(flush_data)} new cases to AI for diagnosis...")

        all_images = []
        case_to_slice = {}
        for case_id, case_data in flush_data.items():
            start_idx = len(all_images)
            all_images.extend(case_data["images"])
            case_to_slice[case_id] = (start_idx, start_idx + self.IMAGES_PER_CASE)

        image_payload = []
        for img in all_images:
            buffered = BytesIO()
            img.save(buffered, format="JPEG")
            image_b64 = base64.b64encode(buffered.getvalue()).decode('utf-8')
            image_payload.append(image_b64)

        # Attempt inference with retry mechanism
        predictions = None
        last_error = None

        for attempt in range(self._max_retries):
            try:
                print(f"[AIQueue] Inference attempt {attempt + 1}/{self._max_retries}...")
                response = requests.post(
                    url=f"{AI_URL}/inference/predict",
                    json={"images": image_payload},
                    timeout=self._inference_timeout_seconds
                )
                response.raise_for_status()
                predictions = response.json()["predictions"]
                print(f"[AIQueue] Inference successful on attempt {attempt + 1}")
                break
            except Exception as e:
                last_error = e
                logger.error(f"AI inference attempt {attempt + 1} failed: {e}", extra={"service": "ai_inference", "attempt": attempt + 1})

                # If not the last attempt, wait with exponential backoff
                if attempt < self._max_retries - 1:
                    backoff_time = self._retry_backoff_base ** attempt
                    print(f"[AIQueue] Retrying in {backoff_time} seconds...")
                    time.sleep(backoff_time)

        # If all retries failed, use NULL fallback values
        if predictions is None:
            logger.error(
                f"AI inference service DOWN - all {self._max_retries} retries failed. Last error: {last_error}. "
                f"Proceeding with NULL fallback values for {len(flush_data)} cases",
                extra={"service": "ai_inference", "status": "service_down", "total_retries": self._max_retries, "error": str(last_error)}
            )

            # Create NULL predictions for all images
            total_images = len(all_images)
            predictions = ["NULL"] * total_images

        # Build results dictionary
        results = {}
        for case_id, (start, end) in case_to_slice.items():
            case_preds = predictions[start:end]
            results[case_id] = case_preds

        # Always send results to DbManager (either real predictions or NULL values)
        self.dbmanager.receive_AI_results(results)