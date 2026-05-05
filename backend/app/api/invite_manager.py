import secrets
import string
from datetime import datetime, timedelta, timezone
from firebase_admin import firestore
from typing import List, Optional, Dict, Any

from app.core.firebase import db

class InviteManager:
    """Service for managing invite codes in Firestore"""

    COLLECTION_NAME = "invite_codes"
    CODE_LENGTH = 12

    @staticmethod
    def generate_code() -> str:
        """Generate a random invite code"""
        alphabet = string.ascii_uppercase + string.digits
        # Remove ambiguous characters (0, O, 1, I, L)
        alphabet = alphabet.replace('0', '').replace('O', '').replace('1', '').replace('I', '').replace('L', '')
        return ''.join(secrets.choice(alphabet) for _ in range(InviteManager.CODE_LENGTH))

    @staticmethod
    def create_invite_code(
        created_by_uid: str,
        restricted_email: Optional[str] = None,
        restricted_role: Optional[str] = None,
        max_uses: int = 1,
        expires_in_days: int = 30
    ) -> Dict[str, Any]:
        """
        Create a new invite code in Firestore

        Args:
            created_by_uid: UID of the admin creating the code
            restricted_email: Optional email restriction
            restricted_role: Optional role restriction
            max_uses: Maximum number of times code can be used (0 = unlimited)
            expires_in_days: Number of days until code expires

        Returns:
            Dictionary containing the created invite code data
        """
        code = InviteManager.generate_code()
        now = datetime.now(timezone.utc)
        expires_at = now + timedelta(days=expires_in_days)

        invite_data = {
            "code": code,
            "created_at": now,
            "created_by": created_by_uid,
            "expires_at": expires_at,
            "restricted_email": restricted_email,
            "restricted_role": restricted_role,
            "max_uses": max_uses,
            "times_used": 0,
            "is_active": True,
            "used_by": []  # List of UIDs who have used this code
        }

        # Store in Firestore using the code as document ID
        db.collection(InviteManager.COLLECTION_NAME).document(code).set(invite_data)

        return invite_data

    @staticmethod
    def validate_code(code: str, email: str, role: str) -> tuple[bool, Optional[str]]:
        """
        Validate an invite code

        Args:
            code: The invite code to validate
            email: Email of the user trying to register
            role: Role the user is trying to register with

        Returns:
            Tuple of (is_valid, error_message)
        """
        try:
            doc = db.collection(InviteManager.COLLECTION_NAME).document(code).get()

            if not doc.exists:
                return False, "Invalid invite code"

            data = doc.to_dict()

            # Check if code is active
            if not data.get("is_active", False):
                return False, "This invite code has been revoked"

            # Check if code has expired
            expires_at = data.get("expires_at")
            if expires_at and expires_at < datetime.now(timezone.utc):
                return False, "This invite code has expired"

            # Check email restriction
            if data.get("restricted_email") and data.get("restricted_email") != email:
                return False, "This invite code is not valid for your email address"

            # Check role restriction
            if data.get("restricted_role") and data.get("restricted_role") != role:
                return False, f"This invite code is only valid for {data.get('restricted_role')} role"

            # Check usage limit
            max_uses = data.get("max_uses", 1)
            times_used = data.get("times_used", 0)
            if max_uses > 0 and times_used >= max_uses:
                return False, "This invite code has reached its usage limit"

            return True, None

        except Exception as e:
            return False, f"Error validating invite code: {str(e)}"

    @staticmethod
    def consume_code(code: str, user_uid: str) -> bool:
        """
        Mark an invite code as used by incrementing times_used and adding user to used_by list

        Args:
            code: The invite code
            user_uid: UID of the user who used the code

        Returns:
            True if successful, False otherwise
        """
        try:
            doc_ref = db.collection(InviteManager.COLLECTION_NAME).document(code)
            doc = doc_ref.get()

            if not doc.exists:
                return False

            data = doc.to_dict()
            times_used = data.get("times_used", 0)
            used_by = data.get("used_by", [])

            # Update the document
            doc_ref.update({
                "times_used": times_used + 1,
                "used_by": firestore.ArrayUnion([user_uid])
            })

            return True

        except Exception as e:
            print(f"Error consuming invite code: {str(e)}")
            return False

    @staticmethod
    def list_codes(created_by_uid: Optional[str] = None) -> List[Dict[str, Any]]:
        """
        List all invite codes, optionally filtered by creator

        Args:
            created_by_uid: Optional UID to filter codes created by specific admin

        Returns:
            List of invite code dictionaries
        """
        query = db.collection(InviteManager.COLLECTION_NAME)

        if created_by_uid:
            query = query.where("created_by", "==", created_by_uid)

        docs = query.stream()
        codes = []

        for doc in docs:
            data = doc.to_dict()
            # Add computed fields
            data["is_expired"] = data.get("expires_at", datetime.now(timezone.utc)) < datetime.now(timezone.utc)
            codes.append(data)

        return codes

    @staticmethod
    def revoke_code(code: str) -> bool:
        """
        Revoke (deactivate) an invite code

        Args:
            code: The invite code to revoke

        Returns:
            True if successful, False otherwise
        """
        try:
            doc_ref = db.collection(InviteManager.COLLECTION_NAME).document(code)
            doc = doc_ref.get()

            if not doc.exists:
                return False

            doc_ref.update({"is_active": False})
            return True

        except Exception as e:
            print(f"Error revoking invite code: {str(e)}")
            return False

    @staticmethod
    def get_code_details(code: str) -> Optional[Dict[str, Any]]:
        """
        Get details of a specific invite code

        Args:
            code: The invite code

        Returns:
            Dictionary with code details or None if not found
        """
        try:
            doc = db.collection(InviteManager.COLLECTION_NAME).document(code).get()

            if not doc.exists:
                return None

            data = doc.to_dict()
            data["is_expired"] = data.get("expires_at", datetime.now(timezone.utc)) < datetime.now(timezone.utc)
            return data

        except Exception as e:
            print(f"Error getting invite code details: {str(e)}")
            return None
