import { useState, useEffect } from "react";
import Keycloak from "keycloak-js";
import "./App.css";

const keycloak = new Keycloak({
  url: window._env_?.KEYCLOAK_URL || "http://localhost:8080",
  realm: window._env_?.KEYCLOAK_REALM || "devportal",
  clientId: window._env_?.KEYCLOAK_CLIENT_ID || "devportal-app",
});

function parseJwt(token) {
  try { return JSON.parse(atob(token.split(".")[1])); } catch { return {}; }
}

function Avatar({ name }) {
  const initials = name?.split(" ").map(n => n[0]).join("").slice(0, 2).toUpperCase() || "?";
  return <div className="avatar">{initials}</div>;
}

function TokenViewer({ token }) {
  const [tab, setTab] = useState("payload");
  const parts = token?.split(".");
  const payload = parseJwt(token);
  return (
    <div className="token-card">
      <div className="token-tabs">
        {["header", "payload", "raw"].map(t => (
          <button key={t} className={`tab-btn ${tab === t ? "active" : ""}`} onClick={() => setTab(t)}>{t}</button>
        ))}
      </div>
      <div className="token-body">
        {tab === "payload" && <pre>{JSON.stringify(payload, null, 2)}</pre>}
        {tab === "header" && <pre>{JSON.stringify(JSON.parse(atob(parts[0])), null, 2)}</pre>}
        {tab === "raw" && <pre className="raw">{token}</pre>}
      </div>
    </div>
  );
}

function Countdown({ expiresAt }) {
  const [secs, setSecs] = useState(0);
  useEffect(() => {
    const tick = () => setSecs(Math.max(0, Math.floor((expiresAt * 1000 - Date.now()) / 1000)));
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, [expiresAt]);
  const pct = Math.min(100, (secs / 300) * 100);
  const color = secs < 60 ? "#ef4444" : secs < 120 ? "#f59e0b" : "#10b981";
  return (
    <div className="countdown">
      <div className="countdown-label">Token expires in</div>
      <div className="countdown-timer" style={{ color }}>{Math.floor(secs / 60)}m {secs % 60}s</div>
      <div className="progress-bar"><div className="progress-fill" style={{ width: `${pct}%`, background: color }} /></div>
    </div>
  );
}

export default function App() {
  const [kc, setKc] = useState(null);
  const [initialized, setInitialized] = useState(false);
  const [apiResult, setApiResult] = useState(null);
  const [apiLoading, setApiLoading] = useState(false);

  useEffect(() => {
    keycloak.init({ onLoad: "check-sso", silentCheckSsoRedirectUri: window.location.origin + "/silent-check-sso.html" })
      .then(auth => { setKc({ ...keycloak, authenticated: auth }); setInitialized(true); })
      .catch(() => setInitialized(true));
  }, []);

  const login = () => keycloak.login();
  const logout = () => keycloak.logout({ redirectUri: window.location.origin });

  const callApi = async () => {
    setApiLoading(true);
    await new Promise(r => setTimeout(r, 1200));
    const payload = parseJwt(keycloak.token);
    setApiResult({
      status: 200,
      message: "Protected resource accessed successfully!",
      user: payload.preferred_username,
      roles: payload.realm_access?.roles?.filter(r => !r.startsWith("default")),
      timestamp: new Date().toISOString(),
      authorization: `Bearer ${keycloak.token?.slice(0, 40)}...`
    });
    setApiLoading(false);
  };

  if (!initialized) return (
    <div className="splash"><div className="spinner" /><p>Initializing auth...</p></div>
  );

  if (!kc?.authenticated) return (
    <div className="landing">
      <div className="landing-bg" />
      <div className="landing-content">
        <div className="logo-mark">⬡</div>
        <h1>DevPortal</h1>
        <p className="tagline">Internal Developer Platform — Secured by Keycloak SSO</p>
        <div className="tech-badges">
          {["Keycloak", "Kubernetes", "OIDC", "JWT", "React"].map(t => (
            <span key={t} className="badge">{t}</span>
          ))}
        </div>
        <button className="login-btn" onClick={login}>
          <span>Sign in with SSO</span>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4"/><polyline points="10 17 15 12 10 7"/><line x1="15" y1="12" x2="3" y2="12"/></svg>
        </button>
        <p className="hint">You will be redirected to Keycloak to authenticate</p>
      </div>
    </div>
  );

  const payload = parseJwt(keycloak.token);
  const roles = payload.realm_access?.roles?.filter(r => !r.startsWith("default")) || [];
  const username = payload.preferred_username || payload.name || "User";
  const email = payload.email || "";

  return (
    <div className="dashboard">
      <nav className="navbar">
        <div className="nav-brand"><span className="logo-mark-sm">⬡</span> DevPortal</div>
        <div className="nav-right">
          <div className="nav-user">
            <Avatar name={username} />
            <div>
              <div className="nav-username">{username}</div>
              <div className="nav-email">{email}</div>
            </div>
          </div>
          <button className="logout-btn" onClick={logout}>Sign Out</button>
        </div>
      </nav>
      <div className="main">
        <div className="welcome-bar">
          <div>
            <h2>Welcome back, {username.split(" ")[0]} 👋</h2>
            <p>Authenticated via Keycloak SSO on Kubernetes</p>
          </div>
          <div className="status-pill"><span className="dot" /> Session Active</div>
        </div>
        <div className="grid-4">
          {[
            { label: "Auth Method", value: "OIDC" },
            { label: "Token Type", value: "Bearer JWT" },
            { label: "Realm", value: payload.iss?.split("/").pop() || "devportal" },
            { label: "Roles", value: roles.length || 1 },
          ].map(s => (
            <div key={s.label} className="stat-card">
              <div className="stat-label">{s.label}</div>
              <div className="stat-value">{s.value}</div>
            </div>
          ))}
        </div>
        <div className="grid-2">
          <div className="card">
            <h3>Your Profile</h3>
            <div className="profile-row">
              <Avatar name={username} />
              <div>
                <div className="profile-name">{payload.name || username}</div>
                <div className="profile-email">{email}</div>
              </div>
            </div>
            <div className="field-list">
              <div className="field"><span>Subject ID</span><code>{payload.sub?.slice(0, 16)}...</code></div>
              <div className="field"><span>Client</span><code>{payload.azp}</code></div>
              <div className="field"><span>Session</span><code>{payload.session_state?.slice(0, 16)}...</code></div>
            </div>
            <div className="roles-section">
              <div className="roles-label">Assigned Roles</div>
              <div className="roles-list">
                {roles.length === 0 && <span className="role-badge role-viewer">user</span>}
                {roles.map(r => <span key={r} className={`role-badge ${r === "admin" ? "role-admin" : r === "developer" ? "role-dev" : "role-viewer"}`}>{r}</span>)}
              </div>
            </div>
            <Countdown expiresAt={payload.exp} />
          </div>
          <div className="card">
            <h3>JWT Token Inspector</h3>
            <p className="card-desc">This is the actual JWT Keycloak issued. Every API call sends this as a Bearer token.</p>
            <TokenViewer token={keycloak.token} />
          </div>
        </div>
        <div className="card">
          <h3>Protected API Simulator</h3>
          <p className="card-desc">Simulate calling a backend microservice with your JWT. In real apps every service verifies this token with Keycloak.</p>
          <button className="api-btn" onClick={callApi} disabled={apiLoading}>
            {apiLoading ? "Calling API..." : "Make Protected API Call"}
          </button>
          {apiResult && (
            <div className="api-result">
              <div className="api-status">
                <span className="status-ok">● {apiResult.status} OK</span>
                <span className="api-time">{apiResult.timestamp}</span>
              </div>
              <pre>{JSON.stringify(apiResult, null, 2)}</pre>
            </div>
          )}
        </div>
        <div className="card">
          <h3>Infrastructure — Running on Kubernetes</h3>
          <div className="k8s-grid">
            {[
              { name: "devportal-app", type: "Deployment", ns: "keycloak-demo", replicas: "2/2" },
              { name: "keycloak", type: "StatefulSet", ns: "keycloak-demo", replicas: "1/1" },
              { name: "postgres", type: "StatefulSet", ns: "keycloak-demo", replicas: "1/1" },
              { name: "nginx-ingress", type: "DaemonSet", ns: "ingress-nginx", replicas: "2/2" },
            ].map(pod => (
              <div key={pod.name} className="pod-card">
                <div className="pod-header"><span className="pod-dot" /><span className="pod-name">{pod.name}</span></div>
                <div className="pod-meta"><span>Type</span><span>{pod.type}</span></div>
                <div className="pod-meta"><span>Namespace</span><span>{pod.ns}</span></div>
                <div className="pod-meta"><span>Replicas</span><span className="replicas-ok">{pod.replicas}</span></div>
                <div className="pod-status">● Running</div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
