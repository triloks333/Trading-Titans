"""Trading Titans Backend - Comprehensive API Tests."""
import time
import uuid
import pytest


# =========================
# Health
# =========================
class TestHealth:
    def test_root(self, api_client, base_url):
        r = api_client.get(f"{base_url}/api/")
        assert r.status_code == 200
        data = r.json()
        assert data.get("status") == "ok"


# =========================
# Auth
# =========================
class TestAuth:
    def test_register_creates_user(self, test_user):
        u = test_user["user"]
        assert u["email"] == test_user["email"]
        assert u["name"] == test_user["name"]
        assert u["wallet_balance"] == 0.0
        assert u["subscription_active"] is False
        assert "id" in u
        assert test_user["token"]

    def test_duplicate_register_returns_400(self, api_client, base_url, test_user):
        r = api_client.post(f"{base_url}/api/auth/register",
                            json={"email": test_user["email"], "password": "AnotherPass123", "name": "Dup"})
        assert r.status_code == 400

    def test_login_success(self, api_client, base_url, test_user):
        r = api_client.post(f"{base_url}/api/auth/login",
                            json={"email": test_user["email"], "password": test_user["password"]})
        assert r.status_code == 200
        data = r.json()
        assert "access_token" in data
        assert data["user"]["email"] == test_user["email"]

    def test_login_wrong_password_returns_401(self, api_client, base_url, test_user):
        r = api_client.post(f"{base_url}/api/auth/login",
                            json={"email": test_user["email"], "password": "WrongPass999"})
        assert r.status_code == 401

    def test_me_returns_user(self, api_client, base_url, auth_headers, test_user):
        r = api_client.get(f"{base_url}/api/auth/me", headers=auth_headers)
        assert r.status_code == 200
        assert r.json()["email"] == test_user["email"]

    def test_me_without_token_returns_401_or_403(self, api_client, base_url):
        r = api_client.get(f"{base_url}/api/auth/me")
        # FastAPI HTTPBearer raises 403 when no auth header
        assert r.status_code in (401, 403)


# =========================
# Market Data (yfinance can rate limit - retry once)
# =========================
def _retry(fn, retries=2, sleep=2):
    last = None
    for i in range(retries):
        r = fn()
        if r.status_code == 200:
            return r
        last = r
        time.sleep(sleep)
    return last


class TestMarket:
    def test_overview(self, api_client, base_url):
        r = _retry(lambda: api_client.get(f"{base_url}/api/market/overview", timeout=30))
        assert r.status_code == 200
        data = r.json()
        assert isinstance(data, list)
        # Expect some entries; yfinance may rate-limit indices but crypto should work
        assert len(data) >= 1
        for item in data:
            assert "symbol" in item
            assert "price" in item
            assert "change_pct" in item

    def test_quote_stock(self, api_client, base_url):
        r = _retry(lambda: api_client.get(f"{base_url}/api/market/quote",
                                          params={"symbol": "RELIANCE", "market": "stock"}, timeout=30))
        assert r.status_code == 200, f"got {r.status_code}: {r.text}"
        data = r.json()
        assert data["symbol"] == "RELIANCE"
        assert data["market"] == "stock"
        assert data["price"] > 0

    def test_quote_crypto(self, api_client, base_url):
        r = _retry(lambda: api_client.get(f"{base_url}/api/market/quote",
                                          params={"symbol": "BTC", "market": "crypto"}, timeout=30))
        assert r.status_code == 200, f"got {r.status_code}: {r.text}"
        data = r.json()
        assert data["symbol"] == "BTC"
        assert data["market"] == "crypto"
        assert data["price"] > 0
        assert data["currency"] == "INR"

    def test_search_stock(self, api_client, base_url):
        r = api_client.get(f"{base_url}/api/market/search",
                           params={"q": "tcs", "market": "stock"}, timeout=15)
        assert r.status_code == 200
        data = r.json()
        assert isinstance(data, list)
        assert any(x["symbol"] == "TCS" for x in data)

    def test_history_stock(self, api_client, base_url):
        r = _retry(lambda: api_client.get(f"{base_url}/api/market/history",
                                          params={"symbol": "RELIANCE", "market": "stock", "range": "1mo"}, timeout=30))
        assert r.status_code == 200, f"got {r.status_code}: {r.text}"
        data = r.json()
        assert data["symbol"] == "RELIANCE"
        assert isinstance(data["points"], list)
        # 1mo of daily data should produce >5 points typically
        if len(data["points"]) > 0:
            p = data["points"][0]
            assert "t" in p and "v" in p


# =========================
# Subscription (MOCKED)
# =========================
class TestSubscription:
    def test_create_order(self, api_client, base_url, auth_headers):
        r = api_client.post(f"{base_url}/api/subscription/create-order", headers=auth_headers)
        assert r.status_code == 200
        data = r.json()
        assert data["amount"] == 19900
        assert data["currency"] == "INR"
        assert "id" in data

    def test_activate_credits_wallet(self, api_client, base_url, auth_headers):
        r = api_client.post(f"{base_url}/api/subscription/activate", headers=auth_headers, json={})
        assert r.status_code == 200, r.text
        data = r.json()
        assert data["ok"] is True
        assert data["new_balance"] >= 100000.0

        # Verify via /me
        me = api_client.get(f"{base_url}/api/auth/me", headers=auth_headers)
        assert me.status_code == 200
        u = me.json()
        assert u["subscription_active"] is True
        assert u["wallet_balance"] >= 100000.0

    def test_activate_twice_returns_400(self, api_client, base_url, auth_headers):
        r = api_client.post(f"{base_url}/api/subscription/activate", headers=auth_headers, json={})
        assert r.status_code == 400


# =========================
# Trading
# =========================
@pytest.fixture(scope="session")
def reliance_price(api_client, base_url):
    r = _retry(lambda: api_client.get(f"{base_url}/api/market/quote",
                                      params={"symbol": "RELIANCE", "market": "stock"}, timeout=30))
    if r.status_code != 200:
        pytest.skip("Market data unavailable for trading tests")
    return r.json()["price"]


class TestTrading:
    def test_insufficient_balance_buy(self, api_client, base_url):
        # Create a fresh user without subscription
        email = f"poor_{uuid.uuid4().hex[:8]}@example.com"
        reg = api_client.post(f"{base_url}/api/auth/register",
                              json={"email": email, "password": "Pass1234", "name": "Poor"})
        assert reg.status_code == 201
        token = reg.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
        r = api_client.post(f"{base_url}/api/trade/order", headers=headers,
                            json={"symbol": "RELIANCE", "market": "stock", "side": "buy", "quantity": 1})
        assert r.status_code == 400

    def test_sell_without_holding(self, api_client, base_url, auth_headers):
        r = api_client.post(f"{base_url}/api/trade/order", headers=auth_headers,
                            json={"symbol": "TCS", "market": "stock", "side": "sell", "quantity": 1})
        assert r.status_code == 400

    def test_buy_then_sell_flow(self, api_client, base_url, auth_headers, reliance_price):
        # Buy 5 RELIANCE
        r = api_client.post(f"{base_url}/api/trade/order", headers=auth_headers,
                            json={"symbol": "RELIANCE", "market": "stock", "side": "buy", "quantity": 5})
        assert r.status_code == 200, r.text
        buy = r.json()
        assert buy["side"] == "buy"
        assert buy["quantity"] == 5
        assert buy["new_balance"] < 100000.0

        # Verify portfolio shows holding
        p = api_client.get(f"{base_url}/api/portfolio", headers=auth_headers)
        assert p.status_code == 200
        port = p.json()
        symbols = [h["symbol"] for h in port["holdings"]]
        assert "RELIANCE" in symbols
        h = next(h for h in port["holdings"] if h["symbol"] == "RELIANCE")
        assert h["quantity"] == 5
        assert "pnl" in h

        # Partial sell - 2 units
        r = api_client.post(f"{base_url}/api/trade/order", headers=auth_headers,
                            json={"symbol": "RELIANCE", "market": "stock", "side": "sell", "quantity": 2})
        assert r.status_code == 200, r.text
        sell1 = r.json()
        assert sell1["side"] == "sell"

        # Portfolio: 3 left
        p2 = api_client.get(f"{base_url}/api/portfolio", headers=auth_headers).json()
        h2 = next(h for h in p2["holdings"] if h["symbol"] == "RELIANCE")
        assert h2["quantity"] == 3

        # Full sell rest
        r = api_client.post(f"{base_url}/api/trade/order", headers=auth_headers,
                            json={"symbol": "RELIANCE", "market": "stock", "side": "sell", "quantity": 3})
        assert r.status_code == 200, r.text

        # Portfolio: holding gone
        p3 = api_client.get(f"{base_url}/api/portfolio", headers=auth_headers).json()
        assert all(h["symbol"] != "RELIANCE" for h in p3["holdings"])


# =========================
# Orders & Analytics
# =========================
class TestOrdersAnalytics:
    def test_orders_list(self, api_client, base_url, auth_headers):
        r = api_client.get(f"{base_url}/api/orders", headers=auth_headers)
        assert r.status_code == 200
        orders = r.json()
        assert isinstance(orders, list)
        # Should have at least subscription credit + trade orders
        if len(orders) >= 2:
            # Verify chronological (desc) ordering
            times = [o["created_at"] for o in orders]
            assert times == sorted(times, reverse=True)

    def test_analytics(self, api_client, base_url, auth_headers):
        r = api_client.get(f"{base_url}/api/analytics", headers=auth_headers)
        assert r.status_code == 200
        data = r.json()
        for key in ["total_trades", "win_rate", "best_trade", "worst_trade",
                    "buy_trades", "sell_trades", "winning_trades", "losing_trades"]:
            assert key in data


# =========================
# Watchlist
# =========================
class TestWatchlist:
    def test_add_get_delete(self, api_client, base_url, auth_headers):
        # Add
        r = api_client.post(f"{base_url}/api/watchlist", headers=auth_headers,
                            json={"symbol": "INFY", "market": "stock"})
        assert r.status_code == 200

        # Get - INFY present
        r = api_client.get(f"{base_url}/api/watchlist", headers=auth_headers)
        assert r.status_code == 200
        items = r.json()
        assert any(it["symbol"] == "INFY" for it in items)

        # Delete
        r = api_client.delete(f"{base_url}/api/watchlist",
                              headers=auth_headers,
                              params={"symbol": "INFY", "market": "stock"})
        assert r.status_code == 200

        # Get - INFY gone
        r = api_client.get(f"{base_url}/api/watchlist", headers=auth_headers)
        items = r.json()
        assert not any(it["symbol"] == "INFY" for it in items)


# =========================
# Leaderboard
# =========================
class TestLeaderboard:
    def test_leaderboard_sorted(self, api_client, base_url, auth_headers, test_user):
        r = api_client.get(f"{base_url}/api/leaderboard", headers=auth_headers)
        assert r.status_code == 200
        data = r.json()
        assert isinstance(data, list)
        assert len(data) >= 1
        # Ranks ascending starting at 1
        ranks = [u["rank"] for u in data]
        assert ranks == list(range(1, len(ranks) + 1))
        # Sorted by realized_pnl desc
        pnls = [u["realized_pnl"] for u in data]
        assert pnls == sorted(pnls, reverse=True)
        # is_self flag for current user
        selfs = [u for u in data if u["is_self"]]
        assert len(selfs) == 1
        assert selfs[0]["user_id"] == test_user["user"]["id"]


# =========================
# What-If
# =========================
class TestWhatIf:
    def test_whatif_stock(self, api_client, base_url):
        r = _retry(lambda: api_client.post(f"{base_url}/api/whatif",
                                           json={"symbol": "RELIANCE", "market": "stock",
                                                 "amount": 10000, "years_ago": 5}, timeout=30))
        assert r.status_code == 200, r.text
        data = r.json()
        for key in ["amount_invested", "purchase_price", "current_price",
                    "units", "current_value", "pnl", "pnl_pct"]:
            assert key in data
        assert data["amount_invested"] == 10000


# =========================
# Autopsy
# =========================
class TestAutopsy:
    def test_autopsy_auth(self, api_client, base_url, auth_headers):
        r = api_client.get(f"{base_url}/api/autopsy", headers=auth_headers)
        assert r.status_code == 200
        data = r.json()
        assert "summary" in data
        assert "insights" in data
        assert isinstance(data["insights"], list)
