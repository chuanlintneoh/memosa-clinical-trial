from firebase_admin import auth
from google.cloud import firestore
from google.cloud.firestore_v1.base_query import FieldFilter
from typing import Any, Dict, Optional, Tuple

from app.core.firebase import db
from app.models.user import UserRole

class UserManager:
    """Service for managing users in Firebase Auth and Firestore"""

    COLLECTION_NAME = "users"

    @staticmethod
    def get_users(
        limit: int = 5,
        start_after_id: Optional[str] = None,
        role: Optional[str] = None,
        name: Optional[str] = None,
        sort_desc: Optional[bool] = False
    ) -> Tuple[Dict[str, Any], str, bool]:
        try:
            query = db.collection(UserManager.COLLECTION_NAME)

            if role:
                query = query.where(filter=FieldFilter("role", "==", role))
            
            if name:
                query = query.where(filter=FieldFilter("name", ">=", name))
                query = query.where(filter=FieldFilter("name", "<=", name + "\uf8ff"))
            
            if sort_desc is not None:
                order = firestore.Query.DESCENDING if sort_desc else firestore.Query.ASCENDING
                query = query.order_by("email", direction=order)

            if start_after_id:
                start_after_doc = db.collection(UserManager.COLLECTION_NAME).document(start_after_id).get()
                if start_after_doc.exists:
                    query = query.start_after(start_after_doc)
                    print(f"[UserManager] Starting after user {start_after_id}")

            query = query.limit(limit + 1)
            docs = query.stream()

            users = []
            for doc in docs:
                user_data = doc.to_dict()
                user_data["user_id"] = doc.id

                for key, value in user_data.items():
                    if hasattr(value, 'isoformat'):
                        user_data[key] = value.isoformat()
                
                users.append(user_data)

            has_more = len(users) > limit
            if has_more:
                users = users[:limit]

            next_cursor = users[-1]["user_id"] if users and has_more else None

            print(f"[UserManager] Retrieved {len(users)} users. Has more: {has_more}, Next cursor: {next_cursor}")

            return {
                "users": users,
                "next_cursor": next_cursor,
                "has_more": has_more
            }, "Success", True
        except Exception as e:
            print(f"[UserManager] Error retrieving list of users: {str(e)}")
            return {}, f"Failed: {str(e)}", False

    @staticmethod
    def get_user_by_id(user_id: str) -> Tuple[Dict[str, Any], str, bool]:
        try:
            doc = db.collection(UserManager.COLLECTION_NAME).document(user_id).get()
            if doc.exists:
                print(f"[UserManager] Retrieved user {user_id} from Firestore.")
                user_data = doc.to_dict()
                user_data["user_id"] = doc.id
                for key, value in user_data.items():
                    if hasattr(value, 'isoformat'):
                        user_data[key] = value.isoformat()
                return user_data, "Success", True
            print(f"[UserManager] User {user_id} not found in Firestore.")
            return {}, "Success: No user found", True
        except Exception as e:
            print(f"[UserManager] Error retrieving user {user_id}: {str(e)}")
            return {}, f"Failed: {str(e)}", False

    @staticmethod
    def delete_user(
        user_id: str,
        hard_delete: bool = False
    ) -> Tuple[str, bool]:
        try:
            # Delete at Firestore
            doc_ref = db.collection(UserManager.COLLECTION_NAME).document(user_id)

            if hard_delete:
                doc_ref.delete()
                print(f"[UserManager] Hard deleted user {user_id} from Firestore")
                auth.delete_user(user_id)
                print(f"[UserManager] Hard deleted user {user_id} from Firebase Auth")
            else:
                doc_ref.update({
                    "status": "disabled",
                    "disabled_at": firestore.SERVER_TIMESTAMP
                })
                print(f"[UserManager] Disabled user {user_id} in Firestore")
                auth.update_user(user_id, disabled=True)
                print(f"[UserManager] Disabled user {user_id} in Firebase Auth")

            auth.revoke_refresh_tokens(user_id)
            print(f"[UserManager] Revoked user {user_id} tokens")
            return "Success", True

        except Exception as e:
            print(f"[UserManager] Error {'deleting' if hard_delete else 'disabling'} user {user_id}: {str(e)}")
            return f"Failed: {str(e)}", False

    @staticmethod
    def reactivate_user(user_id: str) -> Tuple[str, str, bool]:
        try:
            db.collection(UserManager.COLLECTION_NAME).document(user_id).update({
                "status": "reactivated",
                "reactivated_at": firestore.SERVER_TIMESTAMP
            })
            print(f"[UserManager] Reactivated user {user_id} in Firestore")
            auth.update_user(user_id, disabled=False)
            print(f"[UserManager] Reactivated user {user_id} in Firebase Auth")
            return user_id, "Success", True
        except Exception as e:
            print(f"[UserManager] Error reactivating user {user_id}: {str(e)}")
            return user_id, f"Failed: {str(e)}", False

    @staticmethod
    def edit_user(user_id: str, updates: Dict[str, Any]) -> Tuple[str, str, bool]:
        try:
            allowed_keys = {"email", "name", "role"}
            valid_roles = {role.value for role in UserRole}

            clean_updates = {}
            invalid_keys = []

            for k, v in updates.items():
                if k not in allowed_keys:
                    invalid_keys.append(k)
                    continue

                if k == "role":
                    if v in valid_roles:
                        clean_updates[k] = v
                    else:
                        print(f"[UserManager] Rejected invalid role: {v}")
                    continue

                clean_updates[k] = v

            if invalid_keys:
                print(f"[UserManager] Ignoring invalid fields: {invalid_keys}")

            if not clean_updates:
                return user_id, "Failed: No valid fields provided for update", False

            # Update Firebase Auth
            auth_kwargs = {}
            if "email" in clean_updates:
                auth_kwargs["email"] = clean_updates["email"]
            if "name" in clean_updates:
                auth_kwargs["display_name"] = clean_updates["name"]
            if auth_kwargs:
                auth.update_user(user_id, **auth_kwargs)
                print(f"[UserManager] Updated {list(auth_kwargs.keys())} for user {user_id} in Firebase Auth")
            if "role" in clean_updates:
                auth.set_custom_user_claims(user_id, {"role": clean_updates["role"]})
                print(f"[UserManager] Updated Custom Claims (role) for user {user_id} in Firebase Auth")
            
            # Update Firestore
            clean_updates["updated_at"] = firestore.SERVER_TIMESTAMP
            db.collection(UserManager.COLLECTION_NAME).document(user_id).update(clean_updates)
            print(f"[UserManager] Updated user {user_id} in Firestore")

            return user_id, "Success", True
        except Exception as e:
            print(f"[UserManager] Error editing user: {str(e)}")
            return user_id, f"Failed: {str(e)}", False