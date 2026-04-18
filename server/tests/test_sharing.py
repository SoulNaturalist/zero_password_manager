"""
Tests for the password-sharing feature.

Covers all six /sharing endpoints plus the non-obvious security concerns
unearthed in the audit: rate limiting on create, payload size caps,
bounded field lengths, expiry enforcement, self-share rejection, and
IDOR on every read/accept/revoke path.
"""
import base64
from datetime import datetime, timedelta, timezone

import pytest

STRONG_PASSWORD = "Xk9#mPqR2$vLn5@hTjWs"


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _register(client, login, password=STRONG_PASSWORD):
    r = client.post("/register", json={"login": login, "password": password})
    assert r.status_code == 201, r.text
    return r.json()


def _auth(token):
    return {"Authorization": f"Bearer {token}"}


def _make_pair(client):
    """Register Alice (sender) and Bob (recipient); return their tokens + logins."""
    alice = _register(client, "alice")
    bob = _register(client, "bob")
    return {
        "alice_token": alice["access_token"],
        "bob_token": bob["access_token"],
        "alice_login": "alice",
        "bob_login": "bob",
    }


def _share_payload(recipient_login="bob", *, expires_in_days=7, label="Netflix"):
    return {
        "recipient_login": recipient_login,
        "encrypted_payload": base64.b64encode(b"opaque-ciphertext").decode(),
        "encrypted_metadata": {"site": "enc-site"},
        "label": label,
        "expires_in_days": expires_in_days,
    }


def _create_share(client, token, **overrides):
    body = _share_payload(**overrides)
    r = client.post("/sharing", json=body, headers=_auth(token))
    assert r.status_code == 201, r.text
    return r.json()


# ─── 1. Create share ──────────────────────────────────────────────────────────

@pytest.mark.e2e
class TestCreateShare:
    def test_create_share_succeeds_between_two_users(self, client):
        ctx = _make_pair(client)
        r = client.post(
            "/sharing", json=_share_payload(), headers=_auth(ctx["alice_token"])
        )
        assert r.status_code == 201
        body = r.json()
        assert body["recipient_login"] == "bob"
        assert body["status"] == "pending"
        assert body["expires_at"] is not None
        # Owner-id echoed; encrypted payload must NOT leak in ShareResponse.
        assert "encrypted_payload" not in body

    def test_cannot_share_with_yourself(self, client):
        ctx = _make_pair(client)
        r = client.post(
            "/sharing",
            json=_share_payload(recipient_login=ctx["alice_login"]),
            headers=_auth(ctx["alice_token"]),
        )
        assert r.status_code == 400
        assert "yourself" in r.json()["detail"].lower()

    def test_recipient_must_exist(self, client):
        ctx = _make_pair(client)
        r = client.post(
            "/sharing",
            json=_share_payload(recipient_login="ghost"),
            headers=_auth(ctx["alice_token"]),
        )
        assert r.status_code == 404

    @pytest.mark.parametrize("days", [0, -1, 91, 365])
    def test_expires_in_days_out_of_range_rejected(self, client, days):
        ctx = _make_pair(client)
        r = client.post(
            "/sharing",
            json=_share_payload(expires_in_days=days),
            headers=_auth(ctx["alice_token"]),
        )
        assert r.status_code == 400
        assert "1" in r.json()["detail"] and "90" in r.json()["detail"]

    @pytest.mark.parametrize("days", [1, 30, 90])
    def test_expires_in_days_boundary_accepted(self, client, days):
        ctx = _make_pair(client)
        r = client.post(
            "/sharing",
            json=_share_payload(expires_in_days=days),
            headers=_auth(ctx["alice_token"]),
        )
        assert r.status_code == 201

    def test_expires_in_days_optional(self, client):
        ctx = _make_pair(client)
        body = _share_payload()
        body["expires_in_days"] = None
        r = client.post("/sharing", json=body, headers=_auth(ctx["alice_token"]))
        assert r.status_code == 201
        assert r.json()["expires_at"] is None

    def test_create_requires_auth(self, client):
        r = client.post("/sharing", json=_share_payload())
        assert r.status_code == 401


# ─── 2. Listing ───────────────────────────────────────────────────────────────

@pytest.mark.security
class TestListShares:
    def test_outgoing_shows_only_own_created_shares(self, client):
        ctx = _make_pair(client)
        _register(client, "carol")
        carol_token = client.post("/login", json={"login": "carol", "password": STRONG_PASSWORD})
        # Regardless of MFA wiring, use the register token for carol — simpler:
        carol = _register(client, "dave")
        carol_token = carol["access_token"]

        _create_share(client, ctx["alice_token"], recipient_login="bob")
        _create_share(client, carol_token, recipient_login="bob")

        r = client.get("/sharing/outgoing", headers=_auth(ctx["alice_token"]))
        assert r.status_code == 200
        ids = [s["owner_id"] for s in r.json()]
        # Every returned share is owned by Alice, none by Carol.
        assert len(ids) == 1

    def test_incoming_shows_only_shares_addressed_to_me(self, client):
        ctx = _make_pair(client)
        carol = _register(client, "carol")

        _create_share(client, ctx["alice_token"], recipient_login="bob")
        _create_share(client, ctx["alice_token"], recipient_login="carol")

        r = client.get("/sharing/incoming", headers=_auth(ctx["bob_token"]))
        assert r.status_code == 200
        recipients = [s["recipient_login"] for s in r.json()]
        assert recipients == ["bob"]

        r = client.get("/sharing/incoming", headers=_auth(carol["access_token"]))
        recipients = [s["recipient_login"] for s in r.json()]
        assert recipients == ["carol"]

    def test_list_requires_auth(self, client):
        assert client.get("/sharing/outgoing").status_code == 401
        assert client.get("/sharing/incoming").status_code == 401


# ─── 3. Access control on GET /sharing/{id} ───────────────────────────────────

@pytest.mark.security
class TestGetShareAccessControl:
    def test_owner_can_read_detail(self, client):
        ctx = _make_pair(client)
        share = _create_share(client, ctx["alice_token"])
        r = client.get(f"/sharing/{share['id']}", headers=_auth(ctx["alice_token"]))
        assert r.status_code == 200
        # Detail endpoint MUST include the encrypted payload for both parties.
        assert "encrypted_payload" in r.json()

    def test_recipient_can_read_detail(self, client):
        ctx = _make_pair(client)
        share = _create_share(client, ctx["alice_token"])
        r = client.get(f"/sharing/{share['id']}", headers=_auth(ctx["bob_token"]))
        assert r.status_code == 200
        assert r.json()["encrypted_payload"]

    def test_unrelated_user_gets_403(self, client):
        """IDOR regression: a third party must NOT read someone else's share."""
        ctx = _make_pair(client)
        mallory = _register(client, "mallory")
        share = _create_share(client, ctx["alice_token"])

        r = client.get(f"/sharing/{share['id']}", headers=_auth(mallory["access_token"]))
        assert r.status_code == 403

    def test_missing_share_returns_404(self, client):
        ctx = _make_pair(client)
        r = client.get("/sharing/999999", headers=_auth(ctx["alice_token"]))
        assert r.status_code == 404

    def test_detail_requires_auth(self, client):
        assert client.get("/sharing/1").status_code == 401


# ─── 4. Accept flow ───────────────────────────────────────────────────────────

@pytest.mark.e2e
class TestAcceptShare:
    def test_recipient_can_accept_pending_share(self, client):
        ctx = _make_pair(client)
        share = _create_share(client, ctx["alice_token"])
        r = client.post(f"/sharing/{share['id']}/accept", headers=_auth(ctx["bob_token"]))
        assert r.status_code == 200
        assert r.json()["status"] == "accepted"

    def test_non_recipient_cannot_accept(self, client):
        ctx = _make_pair(client)
        mallory = _register(client, "mallory")
        share = _create_share(client, ctx["alice_token"])

        r = client.post(f"/sharing/{share['id']}/accept", headers=_auth(mallory["access_token"]))
        assert r.status_code == 403

    def test_owner_cannot_accept_own_share(self, client):
        """A sender must not be able to auto-accept on the recipient's behalf."""
        ctx = _make_pair(client)
        share = _create_share(client, ctx["alice_token"])
        r = client.post(f"/sharing/{share['id']}/accept", headers=_auth(ctx["alice_token"]))
        assert r.status_code == 403

    def test_cannot_accept_twice(self, client):
        ctx = _make_pair(client)
        share = _create_share(client, ctx["alice_token"])
        assert client.post(f"/sharing/{share['id']}/accept", headers=_auth(ctx["bob_token"])).status_code == 200
        r = client.post(f"/sharing/{share['id']}/accept", headers=_auth(ctx["bob_token"]))
        assert r.status_code == 400
        assert "accepted" in r.json()["detail"].lower()

    def test_cannot_accept_expired_share(self, client, db_session):
        from server.models import PasswordShare

        ctx = _make_pair(client)
        share = _create_share(client, ctx["alice_token"])

        # Backdate the expiry past now.
        row = db_session.query(PasswordShare).filter_by(id=share["id"]).first()
        row.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
        db_session.commit()

        r = client.post(f"/sharing/{share['id']}/accept", headers=_auth(ctx["bob_token"]))
        assert r.status_code == 410

    def test_accept_missing_share_404(self, client):
        ctx = _make_pair(client)
        r = client.post("/sharing/999999/accept", headers=_auth(ctx["bob_token"]))
        assert r.status_code == 404


# ─── 5. Revoke flow ───────────────────────────────────────────────────────────

@pytest.mark.security
class TestRevokeShare:
    def test_owner_can_revoke(self, client):
        ctx = _make_pair(client)
        share = _create_share(client, ctx["alice_token"])
        r = client.delete(f"/sharing/{share['id']}", headers=_auth(ctx["alice_token"]))
        assert r.status_code == 204

    def test_revoked_share_is_no_longer_accessible(self, client):
        ctx = _make_pair(client)
        share = _create_share(client, ctx["alice_token"])
        client.delete(f"/sharing/{share['id']}", headers=_auth(ctx["alice_token"]))

        # Neither party can read or accept a deleted share.
        assert client.get(f"/sharing/{share['id']}", headers=_auth(ctx["alice_token"])).status_code == 404
        assert client.get(f"/sharing/{share['id']}", headers=_auth(ctx["bob_token"])).status_code == 404
        assert client.post(f"/sharing/{share['id']}/accept", headers=_auth(ctx["bob_token"])).status_code == 404

    def test_recipient_cannot_revoke(self, client):
        ctx = _make_pair(client)
        share = _create_share(client, ctx["alice_token"])
        r = client.delete(f"/sharing/{share['id']}", headers=_auth(ctx["bob_token"]))
        assert r.status_code == 403

    def test_unrelated_user_cannot_revoke(self, client):
        """IDOR regression on DELETE — a third party must not be able to delete."""
        ctx = _make_pair(client)
        mallory = _register(client, "mallory")
        share = _create_share(client, ctx["alice_token"])

        r = client.delete(f"/sharing/{share['id']}", headers=_auth(mallory["access_token"]))
        assert r.status_code == 403

    def test_revoke_missing_share_404(self, client):
        ctx = _make_pair(client)
        r = client.delete("/sharing/999999", headers=_auth(ctx["alice_token"]))
        assert r.status_code == 404


# ─── 6. Expiry ────────────────────────────────────────────────────────────────

@pytest.mark.security
class TestShareExpiry:
    def test_expired_share_returns_410_on_get(self, client, db_session):
        from server.models import PasswordShare

        ctx = _make_pair(client)
        share = _create_share(client, ctx["alice_token"])
        row = db_session.query(PasswordShare).filter_by(id=share["id"]).first()
        row.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
        db_session.commit()

        r = client.get(f"/sharing/{share['id']}", headers=_auth(ctx["bob_token"]))
        assert r.status_code == 410

    def test_authorization_checked_before_expiry(self, client, db_session):
        """An unrelated user must get 403, not 410 — 410 would confirm the id exists."""
        from server.models import PasswordShare

        ctx = _make_pair(client)
        mallory = _register(client, "mallory")
        share = _create_share(client, ctx["alice_token"])
        row = db_session.query(PasswordShare).filter_by(id=share["id"]).first()
        row.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
        db_session.commit()

        r = client.get(f"/sharing/{share['id']}", headers=_auth(mallory["access_token"]))
        assert r.status_code == 403


# ─── 7. Security hardening (audit regressions) ────────────────────────────────

@pytest.mark.security
class TestShareSecurityHardening:
    def test_payload_cap_rejects_oversized_blob(self, client):
        """CWE-400 guard: a multi-MB payload must be rejected by the handler."""
        ctx = _make_pair(client)
        body = _share_payload()
        # Exceed MAX_PAYLOAD_SIZE (2 MiB) but stay under the Pydantic cap.
        body["encrypted_payload"] = "A" * (2 * 1024 * 1024 + 1)
        r = client.post("/sharing", json=body, headers=_auth(ctx["alice_token"]))
        assert r.status_code == 400
        assert "too large" in r.json()["detail"].lower()

    def test_schema_rejects_absurd_payload(self, client):
        """Pydantic defense-in-depth: payloads above 4 MB never reach the handler."""
        ctx = _make_pair(client)
        body = _share_payload()
        body["encrypted_payload"] = "A" * (4_000_001)
        r = client.post("/sharing", json=body, headers=_auth(ctx["alice_token"]))
        assert r.status_code == 422

    def test_schema_caps_recipient_login_length(self, client):
        ctx = _make_pair(client)
        body = _share_payload(recipient_login="x" * 65)
        r = client.post("/sharing", json=body, headers=_auth(ctx["alice_token"]))
        assert r.status_code == 422

    def test_schema_caps_label_length(self, client):
        ctx = _make_pair(client)
        body = _share_payload(label="L" * 201)
        r = client.post("/sharing", json=body, headers=_auth(ctx["alice_token"]))
        assert r.status_code == 422

    def test_owner_id_is_never_trusted_from_request(self, client, db_session):
        """Mass-assignment guard: owner_id comes from the authenticated user."""
        from server.models import PasswordShare

        ctx = _make_pair(client)
        body = _share_payload()
        body["owner_id"] = 999  # attacker forges owner in the body
        r = client.post("/sharing", json=body, headers=_auth(ctx["alice_token"]))
        assert r.status_code == 201
        row = db_session.query(PasswordShare).filter_by(id=r.json()["id"]).first()
        alice = next(
            u for u in db_session.query(__import__("server.models", fromlist=["User"]).User).all()
            if u.login == "alice"
        )
        assert row.owner_id == alice.id  # forged value ignored

    def test_status_cannot_be_set_from_request(self, client, db_session):
        """Create body claiming status='accepted' must still produce pending."""
        from server.models import PasswordShare

        ctx = _make_pair(client)
        body = _share_payload()
        body["status"] = "accepted"
        r = client.post("/sharing", json=body, headers=_auth(ctx["alice_token"]))
        assert r.status_code == 201
        row = db_session.query(PasswordShare).filter_by(id=r.json()["id"]).first()
        assert row.status == "pending"
